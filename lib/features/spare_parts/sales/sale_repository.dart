import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

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
class SaleRepository {
  SaleRepository(this.db, this.ledger, this.products, this.numbering);

  final Database db;
  final LedgerRepository ledger;
  final ProductRepository products;
  final NumberSequenceService numbering;

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

    final sale = Sale(
      uuid: uuid,
      businessId: businessId,
      documentNumber: documentNumber,
      customerUuid: customerUuid,
      paymentMethod: paymentMethod,
      date: saleDate,
      status: SaleStatus.posted,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      lines: lines,
    );

    final totalMinorUnits = sale.totalMinorUnits;
    final totalCostMinorUnits = sale.totalCostMinorUnits;
    final totalTaxMinorUnits = sale.totalTaxMinorUnits;
    final grandTotalMinorUnits = sale.grandTotalMinorUnits;

    await db.transaction((txn) async {
      await txn.insert(Sale.tableName, sale.toMap());
      for (final line in lines) {
        await txn.insert(SaleLine.tableName, line.toMap());
      }

      for (final input in lineInputs) {
        await products.adjustStock(
          txn,
          businessId: businessId,
          productUuid: input.productUuid,
          quantityChange: -input.quantity,
          reason: StockMovementReason.sale,
          sourceType: 'Sale',
          sourceId: uuid,
        );
      }

      await ledger.postWithin(
        txn,
        businessId: businessId,
        sourceType: 'Sale',
        sourceId: uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        date: saleDate,
        description: 'Sale $documentNumber',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: paymentMethod == PaymentMethod.cash ? '1010' : '1030',
            // Customer pays/owes the tax-inclusive amount.
            debitMinorUnits: grandTotalMinorUnits,
            creditMinorUnits: 0,
            partyUuid: paymentMethod == PaymentMethod.credit ? customerUuid : null,
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
    });

    return sale;
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
}
