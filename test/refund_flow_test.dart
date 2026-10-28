import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/party/party.dart';
import 'package:business_erp/core/party/party_repository.dart';
import 'package:business_erp/core/system/database.dart';
import 'package:business_erp/core/system/number_sequence_service.dart';
import 'package:business_erp/features/spare_parts/inventory/product_repository.dart';
import 'package:business_erp/features/spare_parts/sales/refund_repository.dart';
import 'package:business_erp/features/spare_parts/sales/sale.dart';
import 'package:business_erp/features/spare_parts/sales/sale_repository.dart';

void main() {
  late Database db;
  late Directory tempDir;
  const businessId = 'business-1';
  const deviceId = 'device-1';
  const user = 'tester';

  late LedgerRepository ledger;
  late ProductRepository products;
  late PartyRepository parties;
  late NumberSequenceService numbering;
  late SaleRepository sales;
  late RefundRepository refunds;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sqlite_test_');
    db = await databaseFactory.openDatabase(
      '${tempDir.path}/test.db',
      options: OpenDatabaseOptions(version: 1, onCreate: (db, version) => createSchema(db)),
    );
    await seedChartOfAccounts(db, businessId);

    ledger = LedgerRepository(db);
    products = ProductRepository(db);
    parties = PartyRepository(db);
    numbering = NumberSequenceService(db);
    sales = SaleRepository(db, ledger, products, numbering);
    refunds = RefundRepository(db, ledger, products, sales, numbering);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('partial qty-wise refund restores some stock, leaves the sale partiallyReturned, and caps further refunds', () async {
    final customer = await parties.create(businessId: businessId, type: PartyType.customer, name: 'Walk-in Customer');
    final brakePad = await products.create(
      businessId: businessId,
      sku: 'BRK-001',
      name: 'Brake Pad',
      costPriceMinorUnits: 1000,
      salePriceMinorUnits: 1500,
      openingStock: 10,
    );
    final oilFilter = await products.create(
      businessId: businessId,
      sku: 'OIL-001',
      name: 'Oil Filter',
      costPriceMinorUnits: 500,
      salePriceMinorUnits: 900,
      openingStock: 10,
    );

    final sale = await sales.create(
      businessId: businessId,
      customerUuid: customer.uuid,
      paymentMethod: PaymentMethod.credit,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [
        SaleLineInput(productUuid: brakePad.uuid, quantity: 5, unitPriceMinorUnits: 1500),
        SaleLineInput(productUuid: oilFilter.uuid, quantity: 4, unitPriceMinorUnits: 900),
      ],
    );

    expect((await products.findByUuid(brakePad.uuid))!.stockQuantity, 5); // 10 - 5
    expect((await products.findByUuid(oilFilter.uuid))!.stockQuantity, 6); // 10 - 4
    expect(await parties.outstandingBalanceMinorUnits(customer.uuid), 5 * 1500 + 4 * 900);

    final refundable = await refunds.refundableLines(sale.uuid);
    expect(refundable.length, 2);
    final brakePadLine = refundable.firstWhere((r) => r.line.productUuid == brakePad.uuid);
    expect(brakePadLine.refundableQty, 5);

    // Refund 2 of the 5 brake pads only — a partial, qty-wise refund.
    await refunds.refund(
      saleUuid: sale.uuid,
      lines: [RefundLineInput(saleLineId: brakePadLine.line.id!, quantity: 2)],
      refundedBy: user,
      deviceId: deviceId,
    );

    expect((await products.findByUuid(brakePad.uuid))!.stockQuantity, 7); // 5 + 2 back
    expect((await products.findByUuid(oilFilter.uuid))!.stockQuantity, 6); // untouched

    final afterPartial = await sales.findByUuid(sale.uuid);
    expect(afterPartial!.status, SaleStatus.partiallyReturned);

    expect(await parties.outstandingBalanceMinorUnits(customer.uuid), 5 * 1500 + 4 * 900 - 2 * 1500);

    final refundableAfter = await refunds.refundableLines(sale.uuid);
    final brakePadAfter = refundableAfter.firstWhere((r) => r.line.productUuid == brakePad.uuid);
    expect(brakePadAfter.refundableQty, 3); // 5 - 2

    // Trying to refund more than what's left on that line is rejected.
    expect(
      () => refunds.refund(
        saleUuid: sale.uuid,
        lines: [RefundLineInput(saleLineId: brakePadLine.line.id!, quantity: 10)],
        refundedBy: user,
        deviceId: deviceId,
      ),
      throwsStateError,
    );

    // Full refund: max out every remaining line in one call.
    final remaining = await refunds.refundableLines(sale.uuid);
    await refunds.refund(
      saleUuid: sale.uuid,
      lines: remaining.where((r) => r.refundableQty > 0).map((r) => RefundLineInput(saleLineId: r.line.id!, quantity: r.refundableQty)).toList(),
      refundedBy: user,
      deviceId: deviceId,
    );

    expect((await products.findByUuid(brakePad.uuid))!.stockQuantity, 10); // fully restored
    expect((await products.findByUuid(oilFilter.uuid))!.stockQuantity, 10); // fully restored
    expect(await parties.outstandingBalanceMinorUnits(customer.uuid), 0);

    final afterFull = await sales.findByUuid(sale.uuid);
    expect(afterFull!.status, SaleStatus.returned);

    // Nothing left to refund now.
    expect(
      () => refunds.refund(
        saleUuid: sale.uuid,
        lines: [RefundLineInput(saleLineId: brakePadLine.line.id!, quantity: 1)],
        refundedBy: user,
        deviceId: deviceId,
      ),
      throwsStateError,
    );
  });

  test('listForDateRange returns refunds scoped to the given window', () async {
    final product = await products.create(
      businessId: businessId,
      sku: 'BRK-002',
      name: 'Spark Plug',
      costPriceMinorUnits: 300,
      salePriceMinorUnits: 600,
      openingStock: 5,
    );

    final sale = await sales.create(
      businessId: businessId,
      paymentMethod: PaymentMethod.cash,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 2, unitPriceMinorUnits: 600)],
    );

    final lineId = (await refunds.refundableLines(sale.uuid)).first.line.id!;
    await refunds.refund(
      saleUuid: sale.uuid,
      lines: [RefundLineInput(saleLineId: lineId, quantity: 1)],
      refundedBy: user,
      deviceId: deviceId,
    );

    final today = DateTime.now();
    final inRange = await refunds.listForDateRange(
      businessId: businessId,
      from: DateTime(today.year, today.month, today.day),
      to: DateTime(today.year, today.month, today.day, 23, 59, 59),
    );
    expect(inRange.length, 1);
    expect(inRange.first.lines.single.quantity, 1);

    final outOfRange = await refunds.listForDateRange(
      businessId: businessId,
      from: today.add(const Duration(days: 1)),
    );
    expect(outOfRange, isEmpty);
  });
}
