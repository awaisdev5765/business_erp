import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/accounting/journal_entry.dart';
import '../../../core/accounting/ledger_repository.dart';
import '../../../core/sync/sync_queue_item.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../../../core/system/audit_log_repository.dart';
import '../../../core/system/number_sequence_service.dart';
import '../inventory/product.dart';
import '../inventory/product_repository.dart';
import 'refund.dart';
import 'sale.dart';
import 'sale_repository.dart';

const _uuid = Uuid();

class RefundLineInput {
  RefundLineInput({required this.saleLineId, required this.quantity});
  final int saleLineId;
  final int quantity;
}

/// One sale line paired with how much of it has already been refunded —
/// what RefundRepository.refundableLines() returns to drive the refund UI
/// (each line's stepper is capped at [refundableQty]).
class RefundableLine {
  RefundableLine({required this.line, required this.refundedQty});
  final SaleLine line;
  final int refundedQty;
  int get refundableQty => line.quantity - refundedQty;
}

/// Refunds some or all of a posted (or already partially-refunded) sale,
/// quantity by quantity, per line — generalizes SaleRepository.returnSale()
/// (whole-sale only) to cover "return 2 of these 5" as well as "return
/// everything left" (the latter is just this same call with every line's
/// quantity set to its [RefundableLine.refundableQty]). returnSale() is
/// left as-is for the sales/tests that already use it rather than merged
/// in, since both end at the same place (status `returned`) and merging
/// would mean rewriting passing coverage for no behavioral change.
class RefundRepository {
  RefundRepository(this.db, this.ledger, this.products, this.sales, this.numbering, [this.auditLog, this.syncQueue]);

  final Database db;
  final LedgerRepository ledger;
  final ProductRepository products;
  final SaleRepository sales;
  final NumberSequenceService numbering;
  final AuditLogRepository? auditLog;

  /// Optional, opt-in — see FirestoreSyncService.restoreFromCloud() for
  /// why a Refund enqueues itself the same way Party/Product do.
  final SyncQueueRepository? syncQueue;

  /// Every line of [saleUuid] alongside how much of it has already been
  /// refunded (summed across every prior Refund against this sale) — the
  /// refund UI uses this to cap each line's quantity stepper.
  Future<List<RefundableLine>> refundableLines(String saleUuid) async {
    final sale = await sales.findByUuid(saleUuid);
    if (sale == null) {
      throw StateError('Sale $saleUuid not found');
    }

    final refundedRows = await db.rawQuery('''
      SELECT rl.sale_line_id AS sale_line_id, SUM(rl.quantity) AS refunded_qty
      FROM ${RefundLine.tableName} rl
      INNER JOIN ${Refund.tableName} r ON r.uuid = rl.refund_uuid
      WHERE r.sale_uuid = ?
      GROUP BY rl.sale_line_id
    ''', [saleUuid]);
    final refundedByLineId = {
      for (final row in refundedRows) row['sale_line_id'] as int: row['refunded_qty'] as int,
    };

    return sale.lines
        .map((line) => RefundableLine(line: line, refundedQty: refundedByLineId[line.id] ?? 0))
        .toList();
  }

  /// Refunds [lines] (each a sale_line id + quantity to return) against
  /// [saleUuid]: restores stock, posts a JournalEntry mirroring the
  /// refunded portion of the original sale's entry, and flips the sale's
  /// status to `returned` (every line now fully refunded) or
  /// `partiallyReturned` (some, but not all).
  Future<Refund> refund({
    required String saleUuid,
    required List<RefundLineInput> lines,
    String? reason,
    required String refundedBy,
    required String deviceId,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('A refund must have at least one line');
    }

    final sale = await sales.findByUuid(saleUuid);
    if (sale == null) {
      throw StateError('Sale $saleUuid not found');
    }
    if (sale.status != SaleStatus.posted && sale.status != SaleStatus.partiallyReturned) {
      throw StateError('Only a posted or partially-returned sale can be refunded (this one is ${sale.status.name})');
    }

    final refundable = await refundableLines(saleUuid);
    final refundableById = {for (final r in refundable) r.line.id: r};

    final refundUuid = _uuid.v4();
    final refundLines = <RefundLine>[];
    for (final input in lines) {
      if (input.quantity <= 0) {
        throw ArgumentError('Refund quantity must be positive');
      }
      final candidate = refundableById[input.saleLineId];
      if (candidate == null) {
        throw StateError('Sale line ${input.saleLineId} does not belong to sale $saleUuid');
      }
      if (input.quantity > candidate.refundableQty) {
        throw StateError(
          'Cannot refund ${input.quantity} of sale line ${input.saleLineId} — only '
          '${candidate.refundableQty} left to refund',
        );
      }
      refundLines.add(RefundLine(
        refundUuid: refundUuid,
        saleLineId: input.saleLineId,
        productUuid: candidate.line.productUuid,
        quantity: input.quantity,
        unitPriceMinorUnits: candidate.line.unitPriceMinorUnits,
        unitCostMinorUnits: candidate.line.unitCostMinorUnits,
        taxRatePercent: candidate.line.taxRatePercent,
      ));
    }

    final refundSubtotal = refundLines.fold<int>(0, (sum, l) => sum + l.lineTotalMinorUnits);
    final refundTax = refundLines.fold<int>(0, (sum, l) => sum + l.lineTaxMinorUnits);
    final refundCost = refundLines.fold<int>(0, (sum, l) => sum + l.lineCostMinorUnits);

    // This refund's share of the sale's flat discount, prorated by
    // subtotal. Exact for a sale refunded in one shot (partial or full);
    // only approximate if the same sale is refunded across several
    // separate partial transactions, since each one prorates off the
    // *original* sale total rather than tracking discount remaining
    // after prior refunds — accepted for a small-business ERP rather
    // than building a discount-remaining ledger per sale.
    final discountForRefund = sale.totalMinorUnits == 0
        ? 0
        : (sale.discountMinorUnits * refundSubtotal / sale.totalMinorUnits).round();

    final documentNumber = await numbering.next(businessId: sale.businessId, docType: DocType.refund);
    final refund = Refund(
      uuid: refundUuid,
      businessId: sale.businessId,
      saleUuid: saleUuid,
      documentNumber: documentNumber,
      date: DateTime.now(),
      reason: reason,
      createdBy: refundedBy,
      createdAt: DateTime.now(),
      lines: refundLines,
      discountMinorUnits: discountForRefund,
    );

    await db.transaction((txn) async {
      await txn.insert(Refund.tableName, refund.toMap());
      for (final line in refundLines) {
        await txn.insert(RefundLine.tableName, line.toMap());
      }
      if (syncQueue != null) {
        await syncQueue!.enqueue(
          txn,
          businessId: sale.businessId,
          entityType: 'Refund',
          entityId: refundUuid,
          operation: SyncOperation.create,
        );
      }

      for (final line in refundLines) {
        await products.adjustStock(
          txn,
          businessId: sale.businessId,
          productUuid: line.productUuid,
          quantityChange: line.quantity,
          reason: StockMovementReason.saleReturn,
          sourceType: 'Refund',
          sourceId: refundUuid,
        );
      }

      final netRefundMinorUnits = refundSubtotal + refundTax - discountForRefund;
      await ledger.postWithin(
        txn,
        businessId: sale.businessId,
        sourceType: 'Refund',
        sourceId: refundUuid,
        createdBy: refundedBy,
        deviceId: deviceId,
        date: refund.date,
        description: 'Refund $documentNumber for Sale ${sale.documentNumber}',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: '4010', // Sales Income — reverse the revenue portion being refunded
            debitMinorUnits: refundSubtotal,
            creditMinorUnits: 0,
          ),
          if (refundTax > 0)
            JournalLine(
              entryUuid: '',
              accountCode: '2020', // Tax Payable
              debitMinorUnits: refundTax,
              creditMinorUnits: 0,
            ),
          if (discountForRefund > 0)
            JournalLine(
              entryUuid: '',
              accountCode: '5110', // Discount Allowed — give back this refund's share
              debitMinorUnits: 0,
              creditMinorUnits: discountForRefund,
            ),
          JournalLine(
            entryUuid: '',
            accountCode: sale.paymentMethod == PaymentMethod.cash ? '1010' : '1030',
            debitMinorUnits: 0,
            creditMinorUnits: netRefundMinorUnits,
            partyUuid: sale.paymentMethod == PaymentMethod.credit ? sale.customerUuid : null,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: '1040', // Inventory — stock is coming back
            debitMinorUnits: refundCost,
            creditMinorUnits: 0,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: '5010', // Cost of Goods Sold
            debitMinorUnits: 0,
            creditMinorUnits: refundCost,
          ),
        ],
      );

      final fullyRefunded = await _isFullyRefunded(txn, sale, justRefunded: refundLines);
      await txn.update(
        Sale.tableName,
        {'status': (fullyRefunded ? SaleStatus.returned : SaleStatus.partiallyReturned).name},
        where: 'uuid = ?',
        whereArgs: [saleUuid],
      );
    });

    await auditLog?.log(
      businessId: sale.businessId,
      action: 'refund',
      entityType: 'Sale',
      entityId: saleUuid,
      performedBy: refundedBy,
      details: '$documentNumber — ${refundLines.length} line(s)'
          '${reason != null && reason.isNotEmpty ? ' ($reason)' : ''}',
    );

    return refund;
  }

  Future<Refund?> findByUuid(String uuid) async {
    final rows = await db.query(Refund.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    if (rows.isEmpty) return null;
    final lineRows = await db.query(RefundLine.tableName, where: 'refund_uuid = ?', whereArgs: [uuid]);
    return Refund.fromMap(rows.first, lines: lineRows.map(RefundLine.fromMap).toList());
  }

  /// Every Refund ever issued in [businessId] dated within [from]/[to] —
  /// same date-range shape as SaleRepository.listForDateRange, for the
  /// Daily/Month-End reports' refund total.
  Future<List<Refund>> listForDateRange({
    required String businessId,
    DateTime? from,
    DateTime? to,
  }) async {
    final conditions = ['business_id = ?'];
    final args = <Object?>[businessId];
    if (from != null) {
      conditions.add('date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      conditions.add('date <= ?');
      args.add(to.toIso8601String());
    }

    final rows = await db.query(Refund.tableName, where: conditions.join(' AND '), whereArgs: args, orderBy: 'date DESC');
    if (rows.isEmpty) return [];
    final refundUuids = rows.map((r) => r['uuid'] as String).toList();
    final lineRows = await db.query(
      RefundLine.tableName,
      where: 'refund_uuid IN (${refundUuids.map((_) => '?').join(', ')})',
      whereArgs: refundUuids,
    );
    final linesByRefund = <String, List<RefundLine>>{};
    for (final row in lineRows) {
      final line = RefundLine.fromMap(row);
      linesByRefund.putIfAbsent(line.refundUuid, () => []).add(line);
    }
    return rows.map((r) => Refund.fromMap(r, lines: linesByRefund[r['uuid']] ?? const [])).toList();
  }

  /// Re-sums every refund against [sale] (including the one just inserted
  /// in the same transaction via [justRefunded]) and checks whether every
  /// original line is now fully accounted for.
  Future<bool> _isFullyRefunded(
    DatabaseExecutor txn,
    Sale sale, {
    required List<RefundLine> justRefunded,
  }) async {
    final rows = await txn.rawQuery('''
      SELECT rl.sale_line_id AS sale_line_id, SUM(rl.quantity) AS refunded_qty
      FROM ${RefundLine.tableName} rl
      INNER JOIN ${Refund.tableName} r ON r.uuid = rl.refund_uuid
      WHERE r.sale_uuid = ?
      GROUP BY rl.sale_line_id
    ''', [sale.uuid]);
    final refundedByLineId = {for (final row in rows) row['sale_line_id'] as int: row['refunded_qty'] as int};

    return sale.lines.every((line) => (refundedByLineId[line.id] ?? 0) >= line.quantity);
  }
}
