import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/accounting/approval_threshold_repository.dart';
import '../../../core/accounting/journal_entry.dart';
import '../../../core/accounting/ledger_repository.dart';
import '../../../core/system/number_sequence_service.dart';
import '../inventory/product.dart';
import '../inventory/product_repository.dart';
import 'sale.dart';

const _uuid = Uuid();

class SaleLineInput {
  SaleLineInput({required this.productUuid, required this.quantity, required this.unitPriceMinorUnits});
  final String productUuid;
  final int quantity;
  final int unitPriceMinorUnits;
}

/// Records a sale, decrements stock, and posts one balanced JournalEntry
/// covering both the revenue side and the cost-of-goods side:
///   Dr Cash(1010)-or-Receivable(1030)   Cr Sales Income(4010)
///   Dr COGS(5010)                       Cr Inventory(1040)
/// A credit sale's receivable line is tagged with the customer's uuid so
/// it surfaces in their ledger. See PHASES.md Sections 9.1 and 11.
///
/// Phase 6: if [approvalThresholds] has a "sale" threshold configured for
/// the business and this is a credit sale above it, the sale is created
/// as `pendingApproval` instead — no stock movement, no JournalEntry —
/// until [approve] runs. [approvalThresholds] is optional, same opt-in
/// pattern as `fiscalPeriods` elsewhere: without one, every sale posts
/// immediately, unchanged from Phase 1.
class SaleRepository {
  SaleRepository(this.db, this.ledger, this.products, this.numbering, [this.approvalThresholds]);

  final Database db;
  final LedgerRepository ledger;
  final ProductRepository products;
  final NumberSequenceService numbering;
  final ApprovalThresholdRepository? approvalThresholds;

  Future<Sale> create({
    required String businessId,
    String? customerUuid,
    required PaymentMethod paymentMethod,
    required String createdBy,
    required String deviceId,
    required List<SaleLineInput> lineInputs,
    DateTime? date,
  }) async {
    if (lineInputs.isEmpty) {
      throw ArgumentError('A sale must have at least one line');
    }
    if (paymentMethod == PaymentMethod.credit && customerUuid == null) {
      throw ArgumentError('Credit sales must be tied to a customer');
    }

    final documentNumber = await numbering.next(businessId: businessId, docType: DocType.sale);
    final uuid = _uuid.v4();
    final saleDate = date ?? DateTime.now();

    // Snapshot unit cost at sale time for accurate COGS/profit reporting,
    // and to validate there's enough stock before committing.
    final lines = <SaleLine>[];
    for (final input in lineInputs) {
      final product = await products.findByUuid(input.productUuid);
      if (product == null) {
        throw StateError('Product ${input.productUuid} not found');
      }
      if (product.stockQuantity < input.quantity) {
        throw StateError('Insufficient stock for "${product.name}": '
            'have ${product.stockQuantity}, need ${input.quantity}');
      }
      lines.add(SaleLine(
        saleUuid: uuid,
        productUuid: input.productUuid,
        quantity: input.quantity,
        unitPriceMinorUnits: input.unitPriceMinorUnits,
        unitCostMinorUnits: product.costPriceMinorUnits,
        taxRatePercent: product.taxRatePercent,
      ));
    }

    var requiresApproval = false;
    if (paymentMethod == PaymentMethod.credit && approvalThresholds != null) {
      final threshold = await approvalThresholds!.thresholdFor(businessId: businessId, transactionType: 'sale');
      final grandTotal = lines.fold<int>(0, (sum, l) => sum + l.lineTotalMinorUnits + l.lineTaxMinorUnits);
      requiresApproval = threshold != null && grandTotal > threshold;
    }

    final sale = Sale(
      uuid: uuid,
      businessId: businessId,
      documentNumber: documentNumber,
      customerUuid: customerUuid,
      paymentMethod: paymentMethod,
      date: saleDate,
      status: requiresApproval ? SaleStatus.pendingApproval : SaleStatus.posted,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      lines: lines,
    );

    await db.transaction((txn) async {
      await txn.insert(Sale.tableName, sale.toMap());
      for (final line in lines) {
        await txn.insert(SaleLine.tableName, line.toMap());
      }

      if (!requiresApproval) {
        await _postSale(txn, sale, createdBy: createdBy, deviceId: deviceId);
      }
    });

    return sale;
  }

  /// Posts a `pendingApproval` sale: adjusts stock and posts the
  /// JournalEntry that [create] would have posted immediately had it not
  /// needed approval. Throws if the sale isn't actually pending.
  Future<void> approve(String saleUuid, {required String approvedBy, required String deviceId}) async {
    final sale = await findByUuid(saleUuid);
    if (sale == null) {
      throw StateError('Sale $saleUuid not found');
    }
    if (sale.status != SaleStatus.pendingApproval) {
      throw StateError('Sale $saleUuid is not pending approval');
    }

    await db.transaction((txn) async {
      await _postSale(txn, sale, createdBy: approvedBy, deviceId: deviceId);
      await txn.update(
        Sale.tableName,
        {'status': SaleStatus.posted.name},
        where: 'uuid = ?',
        whereArgs: [saleUuid],
      );
    });
  }

  Future<void> _postSale(
    DatabaseExecutor txn,
    Sale sale, {
    required String createdBy,
    required String deviceId,
  }) async {
    // Re-validate stock here, not just in create(): a pendingApproval
    // sale can sit for a while before approve() calls this, and other
    // sales may have consumed the stock in the meantime. Queries against
    // [txn], not products.findByUuid (which reads via the raw Database) —
    // reading through `db` from inside an active transaction risks a
    // deadlock with sqflite.
    for (final line in sale.lines) {
      final rows = await txn.query(Product.tableName, where: 'uuid = ?', whereArgs: [line.productUuid], limit: 1);
      if (rows.isEmpty) {
        throw StateError('Product ${line.productUuid} not found');
      }
      final product = Product.fromMap(rows.first);
      if (product.stockQuantity < line.quantity) {
        throw StateError('Insufficient stock for "${product.name}": '
            'have ${product.stockQuantity}, need ${line.quantity}');
      }
    }

    for (final line in sale.lines) {
      await products.adjustStock(
        txn,
        businessId: sale.businessId,
        productUuid: line.productUuid,
        quantityChange: -line.quantity,
        reason: StockMovementReason.sale,
        sourceType: 'Sale',
        sourceId: sale.uuid,
      );
    }

    final totalMinorUnits = sale.totalMinorUnits;
    final totalCostMinorUnits = sale.totalCostMinorUnits;
    final totalTaxMinorUnits = sale.totalTaxMinorUnits;
    final grandTotalMinorUnits = sale.grandTotalMinorUnits;

    await ledger.postWithin(
      txn,
      businessId: sale.businessId,
      sourceType: 'Sale',
      sourceId: sale.uuid,
      createdBy: createdBy,
      deviceId: deviceId,
      date: sale.date,
      description: 'Sale ${sale.documentNumber}',
      rawLines: [
        JournalLine(
          entryUuid: '',
          accountCode: sale.paymentMethod == PaymentMethod.cash ? '1010' : '1030',
          // Customer pays/owes the tax-inclusive amount.
          debitMinorUnits: grandTotalMinorUnits,
          creditMinorUnits: 0,
          partyUuid: sale.paymentMethod == PaymentMethod.credit ? sale.customerUuid : null,
        ),
        JournalLine(
          entryUuid: '',
          accountCode: '4010', // Sales Income (tax-exclusive)
          debitMinorUnits: 0,
          creditMinorUnits: totalMinorUnits,
        ),
        if (totalTaxMinorUnits > 0)
          JournalLine(
            entryUuid: '',
            accountCode: '2020', // Tax Payable — output tax collected
            debitMinorUnits: 0,
            creditMinorUnits: totalTaxMinorUnits,
          ),
        JournalLine(
          entryUuid: '',
          accountCode: '5010', // Cost of Goods Sold
          debitMinorUnits: totalCostMinorUnits,
          creditMinorUnits: 0,
        ),
        JournalLine(
          entryUuid: '',
          accountCode: '1040', // Inventory
          debitMinorUnits: 0,
          creditMinorUnits: totalCostMinorUnits,
        ),
      ],
    );
  }

  Future<Sale?> findByUuid(String uuid) async {
    final rows = await db.query(Sale.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    if (rows.isEmpty) return null;
    final lineRows = await db.query(SaleLine.tableName, where: 'sale_uuid = ?', whereArgs: [uuid]);
    return Sale.fromMap(rows.first, lines: lineRows.map(SaleLine.fromMap).toList());
  }

  Future<List<Sale>> list({required String businessId}) async {
    final rows = await db.query(
      Sale.tableName,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'date DESC',
    );
    return rows.map(Sale.fromMap).toList();
  }

  Future<List<Sale>> pendingApproval({required String businessId}) async {
    final rows = await db.query(
      Sale.tableName,
      where: 'business_id = ? AND status = ?',
      whereArgs: [businessId, SaleStatus.pendingApproval.name],
      orderBy: 'date ASC',
    );
    return rows.map(Sale.fromMap).toList();
  }
}
