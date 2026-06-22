import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/accounting/journal_entry.dart';
import '../../../core/accounting/ledger_repository.dart';
import '../../../core/system/number_sequence_service.dart';
import '../inventory/product.dart';
import '../inventory/product_repository.dart';
import 'purchase.dart';

const _uuid = Uuid();

class PurchaseLineInput {
  PurchaseLineInput({required this.productUuid, required this.quantity, required this.unitCostMinorUnits});
  final String productUuid;
  final int quantity;
  final int unitCostMinorUnits;
}

/// Credit purchase from a supplier: stock increases, supplier payable
/// increases. Posts Dr Inventory(1040) / Cr Accounts Payable(2010), with
/// the payable line tagged to the supplier so it shows up in their ledger
/// (PartyRepository.outstandingBalanceMinorUnits). See PHASES.md Section 11.
class PurchaseRepository {
  PurchaseRepository(this.db, this.ledger, this.products, this.numbering);

  final Database db;
  final LedgerRepository ledger;
  final ProductRepository products;
  final NumberSequenceService numbering;

  Future<Purchase> create({
    required String businessId,
    required String supplierUuid,
    required String createdBy,
    required String deviceId,
    required List<PurchaseLineInput> lineInputs,
    DateTime? date,
  }) async {
    if (lineInputs.isEmpty) {
      throw ArgumentError('A purchase must have at least one line');
    }

    final documentNumber = await numbering.next(businessId: businessId, docType: DocType.purchase);
    final uuid = _uuid.v4();
    final purchaseDate = date ?? DateTime.now();

    final lines = lineInputs
        .map((l) => PurchaseLine(
              purchaseUuid: uuid,
              productUuid: l.productUuid,
              quantity: l.quantity,
              unitCostMinorUnits: l.unitCostMinorUnits,
            ))
        .toList();

    final purchase = Purchase(
      uuid: uuid,
      businessId: businessId,
      documentNumber: documentNumber,
      supplierUuid: supplierUuid,
      date: purchaseDate,
      status: PurchaseStatus.posted,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      lines: lines,
    );

    final totalMinorUnits = purchase.totalMinorUnits;

    await db.transaction((txn) async {
      await txn.insert(Purchase.tableName, purchase.toMap());
      for (final line in lines) {
        await txn.insert(PurchaseLine.tableName, line.toMap());
      }

      for (final line in lineInputs) {
        await products.adjustStock(
          txn,
          businessId: businessId,
          productUuid: line.productUuid,
          quantityChange: line.quantity,
          reason: StockMovementReason.purchase,
          sourceType: 'Purchase',
          sourceId: uuid,
        );
      }

      await ledger.postWithin(
        txn,
        businessId: businessId,
        sourceType: 'Purchase',
        sourceId: uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        date: purchaseDate,
        description: 'Purchase $documentNumber',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: '1040', // Inventory
            debitMinorUnits: totalMinorUnits,
            creditMinorUnits: 0,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: '2010', // Accounts Payable
            debitMinorUnits: 0,
            creditMinorUnits: totalMinorUnits,
            partyUuid: supplierUuid,
          ),
        ],
      );
    });

    return purchase;
  }

  Future<Purchase?> findByUuid(String uuid) async {
    final rows = await db.query(Purchase.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    if (rows.isEmpty) return null;
    final lineRows = await db.query(PurchaseLine.tableName, where: 'purchase_uuid = ?', whereArgs: [uuid]);
    return Purchase.fromMap(rows.first, lines: lineRows.map(PurchaseLine.fromMap).toList());
  }

  Future<List<Purchase>> list({required String businessId}) async {
    final rows = await db.query(
      Purchase.tableName,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'date DESC',
    );
    return rows.map(Purchase.fromMap).toList();
  }
}
