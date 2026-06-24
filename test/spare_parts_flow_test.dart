import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/party/party.dart';
import 'package:business_erp/core/party/party_repository.dart';
import 'package:business_erp/core/system/database.dart';
import 'package:business_erp/core/system/number_sequence_service.dart';
import 'package:business_erp/core/transaction/payment.dart';
import 'package:business_erp/core/transaction/payment_repository.dart';
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
  late PaymentRepository payments;

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
    payments = PaymentRepository(db, ledger, numbering);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('purchase increases stock and posts Dr Inventory / Cr Payable', () async {
    final supplier = await parties.create(businessId: businessId, type: PartyType.supplier, name: 'Acme Parts Co');
    final product = await products.create(
      businessId: businessId,
      sku: 'BRK-001',
      name: 'Brake Pad XL',
      costPriceMinorUnits: 1000,
      salePriceMinorUnits: 1500,
    );

    await purchases.create(
      businessId: businessId,
      supplierUuid: supplier.uuid,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [PurchaseLineInput(productUuid: product.uuid, quantity: 10, unitCostMinorUnits: 1000)],
    );

    final restocked = await products.findByUuid(product.uuid);
    expect(restocked!.stockQuantity, 10);

    final inventoryBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1040');
    expect(inventoryBalance, 10000); // Dr Inventory 10 * 1000

    final supplierPayable = await parties.outstandingBalanceMinorUnits(supplier.uuid);
    expect(supplierPayable, -10000); // Cr balance: we owe the supplier
  });

  test('credit sale decrements stock, posts revenue+COGS, and updates customer receivable', () async {
    final customer = await parties.create(businessId: businessId, type: PartyType.customer, name: 'Walk-in Customer');
    final supplier = await parties.create(businessId: businessId, type: PartyType.supplier, name: 'Acme Parts Co');
    final product = await products.create(
      businessId: businessId,
      sku: 'BRK-001',
      name: 'Brake Pad XL',
      costPriceMinorUnits: 1000,
      salePriceMinorUnits: 1500,
    );

    await purchases.create(
      businessId: businessId,
      supplierUuid: supplier.uuid,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [PurchaseLineInput(productUuid: product.uuid, quantity: 10, unitCostMinorUnits: 1000)],
    );

    await sales.create(
      businessId: businessId,
      customerUuid: customer.uuid,
      paymentMethod: PaymentMethod.credit,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 2, unitPriceMinorUnits: 1500)],
    );

    final afterSale = await products.findByUuid(product.uuid);
    expect(afterSale!.stockQuantity, 8); // 10 - 2

    final salesIncome = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '4010');
    expect(salesIncome, -3000); // Cr 2 * 1500

    final cogs = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '5010');
    expect(cogs, 2000); // Dr 2 * 1000

    final customerReceivable = await parties.outstandingBalanceMinorUnits(customer.uuid);
    expect(customerReceivable, 3000); // customer owes us 3000

    // Customer pays half.
    await payments.record(
      businessId: businessId,
      partyUuid: customer.uuid,
      direction: PaymentDirection.receiveFromCustomer,
      amountMinorUnits: 1500,
      createdBy: user,
      deviceId: deviceId,
    );

    final remainingReceivable = await parties.outstandingBalanceMinorUnits(customer.uuid);
    expect(remainingReceivable, 1500);

    final cashBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(cashBalance, 1500);
  });

  test('returning a sale restores stock and reverses the original entry', () async {
    final customer = await parties.create(businessId: businessId, type: PartyType.customer, name: 'Walk-in Customer');
    final supplier = await parties.create(businessId: businessId, type: PartyType.supplier, name: 'Acme Parts Co');
    final product = await products.create(
      businessId: businessId,
      sku: 'BRK-003',
      name: 'Oil Filter',
      costPriceMinorUnits: 500,
      salePriceMinorUnits: 900,
    );

    await purchases.create(
      businessId: businessId,
      supplierUuid: supplier.uuid,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [PurchaseLineInput(productUuid: product.uuid, quantity: 5, unitCostMinorUnits: 500)],
    );

    final sale = await sales.create(
      businessId: businessId,
      customerUuid: customer.uuid,
      paymentMethod: PaymentMethod.credit,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 3, unitPriceMinorUnits: 900)],
    );

    expect((await products.findByUuid(product.uuid))!.stockQuantity, 2); // 5 - 3
    expect(await parties.outstandingBalanceMinorUnits(customer.uuid), 2700); // 3 * 900

    await sales.returnSale(sale.uuid, returnedBy: user, deviceId: deviceId);

    expect((await products.findByUuid(product.uuid))!.stockQuantity, 5); // restored
    expect(await parties.outstandingBalanceMinorUnits(customer.uuid), 0); // reversed
    expect(await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '4010'), 0);
    expect(await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '5010'), 0);

    final returned = await sales.findByUuid(sale.uuid);
    expect(returned!.status, SaleStatus.returned);
  });

  test('returning an already-returned sale throws', () async {
    final product = await products.create(
      businessId: businessId,
      sku: 'BRK-004',
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
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 1, unitPriceMinorUnits: 600)],
    );

    await sales.returnSale(sale.uuid, returnedBy: user, deviceId: deviceId);

    expect(
      () => sales.returnSale(sale.uuid, returnedBy: user, deviceId: deviceId),
      throwsStateError,
    );
  });

  test('cash sale rejects when stock is insufficient', () async {
    final product = await products.create(
      businessId: businessId,
      sku: 'BRK-002',
      name: 'Chain Set',
      costPriceMinorUnits: 2000,
      salePriceMinorUnits: 4200,
    );

    expect(
      () => sales.create(
        businessId: businessId,
        paymentMethod: PaymentMethod.cash,
        createdBy: user,
        deviceId: deviceId,
        lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 1, unitPriceMinorUnits: 4200)],
      ),
      throwsStateError,
    );
  });
}
