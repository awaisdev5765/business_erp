import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/approval_threshold_repository.dart';
import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/party/party.dart';
import 'package:business_erp/core/party/party_repository.dart';
import 'package:business_erp/core/system/database.dart';
import 'package:business_erp/core/system/number_sequence_service.dart';
import 'package:business_erp/features/spare_parts/inventory/product_repository.dart';
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
  late ApprovalThresholdRepository thresholds;
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
    thresholds = ApprovalThresholdRepository(db);
    sales = SaleRepository(db, ledger, products, numbering, thresholds);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('without a threshold configured, credit sales post immediately regardless of size (opt-in)', () async {
    final customer = await parties.create(businessId: businessId, type: PartyType.customer, name: 'Big Co');
    final product = await products.create(
      businessId: businessId,
      sku: 'P1',
      name: 'Expensive Part',
      costPriceMinorUnits: 50000,
      salePriceMinorUnits: 100000,
      openingStock: 10,
    );

    final sale = await sales.create(
      businessId: businessId,
      customerUuid: customer.uuid,
      paymentMethod: PaymentMethod.credit,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 5, unitPriceMinorUnits: 100000)],
    );

    expect(sale.status, SaleStatus.posted);
    final stock = await products.findByUuid(product.uuid);
    expect(stock!.stockQuantity, 5); // already decremented
  });

  test('a credit sale above the configured threshold is held pending approval: no stock change, no posting', () async {
    await thresholds.setThreshold(businessId: businessId, transactionType: 'sale', thresholdMinorUnits: 200000);

    final customer = await parties.create(businessId: businessId, type: PartyType.customer, name: 'Big Co');
    final product = await products.create(
      businessId: businessId,
      sku: 'P1',
      name: 'Expensive Part',
      costPriceMinorUnits: 50000,
      salePriceMinorUnits: 100000,
      openingStock: 10,
    );

    // 5 * 100000 = 500000 > 200000 threshold.
    final sale = await sales.create(
      businessId: businessId,
      customerUuid: customer.uuid,
      paymentMethod: PaymentMethod.credit,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 5, unitPriceMinorUnits: 100000)],
    );

    expect(sale.status, SaleStatus.pendingApproval);

    final stock = await products.findByUuid(product.uuid);
    expect(stock!.stockQuantity, 10); // unchanged — not yet posted

    final receivable = await parties.outstandingBalanceMinorUnits(customer.uuid);
    expect(receivable, 0); // no ledger impact yet

    final pending = await sales.pendingApproval(businessId: businessId);
    expect(pending.map((s) => s.uuid), contains(sale.uuid));
  });

  test('a credit sale at or below the threshold posts immediately (threshold is exclusive)', () async {
    await thresholds.setThreshold(businessId: businessId, transactionType: 'sale', thresholdMinorUnits: 500000);

    final customer = await parties.create(businessId: businessId, type: PartyType.customer, name: 'Small Co');
    final product = await products.create(
      businessId: businessId,
      sku: 'P1',
      name: 'Part',
      costPriceMinorUnits: 50000,
      salePriceMinorUnits: 100000,
      openingStock: 10,
    );

    final sale = await sales.create(
      businessId: businessId,
      customerUuid: customer.uuid,
      paymentMethod: PaymentMethod.credit,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 5, unitPriceMinorUnits: 100000)], // exactly 500000
    );

    expect(sale.status, SaleStatus.posted);
  });

  test('cash sales are never gated by the approval threshold', () async {
    await thresholds.setThreshold(businessId: businessId, transactionType: 'sale', thresholdMinorUnits: 1);

    final product = await products.create(
      businessId: businessId,
      sku: 'P1',
      name: 'Part',
      costPriceMinorUnits: 50000,
      salePriceMinorUnits: 100000,
      openingStock: 10,
    );

    final sale = await sales.create(
      businessId: businessId,
      paymentMethod: PaymentMethod.cash,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 5, unitPriceMinorUnits: 100000)],
    );

    expect(sale.status, SaleStatus.posted);
  });

  test('approving a pending sale adjusts stock and posts the ledger entry', () async {
    await thresholds.setThreshold(businessId: businessId, transactionType: 'sale', thresholdMinorUnits: 200000);

    final customer = await parties.create(businessId: businessId, type: PartyType.customer, name: 'Big Co');
    final product = await products.create(
      businessId: businessId,
      sku: 'P1',
      name: 'Expensive Part',
      costPriceMinorUnits: 50000,
      salePriceMinorUnits: 100000,
      openingStock: 10,
    );

    final sale = await sales.create(
      businessId: businessId,
      customerUuid: customer.uuid,
      paymentMethod: PaymentMethod.credit,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 5, unitPriceMinorUnits: 100000)],
    );

    await sales.approve(sale.uuid, approvedBy: 'manager', deviceId: deviceId);

    final approved = await sales.findByUuid(sale.uuid);
    expect(approved!.status, SaleStatus.posted);

    final stock = await products.findByUuid(product.uuid);
    expect(stock!.stockQuantity, 5);

    final receivable = await parties.outstandingBalanceMinorUnits(customer.uuid);
    expect(receivable, 500000);

    final pending = await sales.pendingApproval(businessId: businessId);
    expect(pending, isEmpty);
  });

  test('approving an already-posted sale throws', () async {
    final product = await products.create(
      businessId: businessId,
      sku: 'P1',
      name: 'Part',
      costPriceMinorUnits: 50000,
      salePriceMinorUnits: 100000,
      openingStock: 10,
    );

    final sale = await sales.create(
      businessId: businessId,
      paymentMethod: PaymentMethod.cash,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 1, unitPriceMinorUnits: 100000)],
    );

    expect(
      () => sales.approve(sale.uuid, approvedBy: 'manager', deviceId: deviceId),
      throwsStateError,
    );
  });

  test('approving a sale whose stock was consumed elsewhere in the meantime fails and posts nothing', () async {
    await thresholds.setThreshold(businessId: businessId, transactionType: 'sale', thresholdMinorUnits: 100000);

    final customerA = await parties.create(businessId: businessId, type: PartyType.customer, name: 'A');
    final customerB = await parties.create(businessId: businessId, type: PartyType.customer, name: 'B');
    final product = await products.create(
      businessId: businessId,
      sku: 'P1',
      name: 'Scarce Part',
      costPriceMinorUnits: 50000,
      salePriceMinorUnits: 100000,
      openingStock: 5,
    );

    final pendingSale = await sales.create(
      businessId: businessId,
      customerUuid: customerA.uuid,
      paymentMethod: PaymentMethod.credit,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 5, unitPriceMinorUnits: 100000)],
    );
    expect(pendingSale.status, SaleStatus.pendingApproval);

    // Someone else sells the same stock for cash in the meantime.
    await sales.create(
      businessId: businessId,
      customerUuid: customerB.uuid,
      paymentMethod: PaymentMethod.cash,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 5, unitPriceMinorUnits: 100000)],
    );

    expect(
      () => sales.approve(pendingSale.uuid, approvedBy: 'manager', deviceId: deviceId),
      throwsStateError,
    );

    final stillPending = await sales.findByUuid(pendingSale.uuid);
    expect(stillPending!.status, SaleStatus.pendingApproval); // unchanged
  });
}
