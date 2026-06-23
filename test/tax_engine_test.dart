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
import 'package:business_erp/features/spare_parts/purchases/purchase_repository.dart';
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
  late PurchaseRepository purchases;
  late SaleRepository sales;

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
    purchases = PurchaseRepository(db, ledger, products, numbering);
    sales = SaleRepository(db, ledger, products, numbering);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('cash sale of a taxed product splits revenue and tax, and charges the customer the tax-inclusive total', () async {
    final product = await products.create(
      businessId: businessId,
      sku: 'TAX-001',
      name: 'Taxed Widget',
      costPriceMinorUnits: 1000,
      salePriceMinorUnits: 2000, // tax-exclusive
      taxRatePercent: 10,
      openingStock: 5,
    );

    await sales.create(
      businessId: businessId,
      paymentMethod: PaymentMethod.cash,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 1, unitPriceMinorUnits: 2000)],
    );

    final cash = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(cash, 2200); // customer paid tax-inclusive: 2000 + 10%

    final salesIncome = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '4010');
    expect(salesIncome, -2000); // revenue recorded tax-exclusive

    final taxPayable = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '2020');
    expect(taxPayable, -200); // output tax collected, owed to the tax authority
  });

  test('untaxed product (rate 0) posts no tax line at all', () async {
    final product = await products.create(
      businessId: businessId,
      sku: 'NOTAX-001',
      name: 'Untaxed Widget',
      costPriceMinorUnits: 500,
      salePriceMinorUnits: 1000,
      openingStock: 5,
    );

    await sales.create(
      businessId: businessId,
      paymentMethod: PaymentMethod.cash,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 1, unitPriceMinorUnits: 1000)],
    );

    final cash = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(cash, 1000); // no tax added

    final taxPayable = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '2020');
    expect(taxPayable, 0);
  });

  test('purchase of a taxed product claims input tax and owes the supplier the tax-inclusive total', () async {
    final supplier = await parties.create(businessId: businessId, type: PartyType.supplier, name: 'Acme Co');
    final product = await products.create(
      businessId: businessId,
      sku: 'TAX-002',
      name: 'Taxed Part',
      costPriceMinorUnits: 1000,
      salePriceMinorUnits: 1500,
      taxRatePercent: 10,
    );

    await purchases.create(
      businessId: businessId,
      supplierUuid: supplier.uuid,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [PurchaseLineInput(productUuid: product.uuid, quantity: 1, unitCostMinorUnits: 1000)],
    );

    final inventory = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1040');
    expect(inventory, 1000); // recorded tax-exclusive

    // Tax Payable: input tax (Dr 100) nets against nothing else here, so balance is +100 (Dr).
    final taxAccount = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '2020');
    expect(taxAccount, 100);

    final supplierPayable = await parties.outstandingBalanceMinorUnits(supplier.uuid);
    expect(supplierPayable, -1100); // owe the supplier the tax-inclusive total
  });
}
