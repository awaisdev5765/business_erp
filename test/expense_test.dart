import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/expense.dart';
import 'package:business_erp/core/accounting/expense_repository.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/system/database.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late LedgerRepository ledger;
  late ExpenseRepository expenses;
  const businessId = 'business-1';
  const user = 'tester';
  const deviceId = 'device-1';

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
    expenses = ExpenseRepository(db, ledger);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('recording a cash expense posts Dr expense account / Cr Cash on Hand', () async {
    await expenses.create(
      businessId: businessId,
      accountCode: '5120', // Rent Expense
      amountMinorUnits: 50000,
      description: 'Shop rent — June',
      createdBy: user,
      deviceId: deviceId,
    );

    final rentExpense = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '5120');
    expect(rentExpense, 50000);

    final cashBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(cashBalance, -50000);
  });

  test('a bank-transfer or cheque expense hits Bank Accounts, not Cash on Hand', () async {
    await expenses.create(
      businessId: businessId,
      accountCode: '5130', // Utilities Expense
      amountMinorUnits: 12000,
      method: ExpensePaymentMethod.bankTransfer,
      createdBy: user,
      deviceId: deviceId,
    );

    final cashBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(cashBalance, 0);

    final bankBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1020');
    expect(bankBalance, -12000);
  });

  test('listing expenses returns them newest first', () async {
    await expenses.create(
      businessId: businessId,
      accountCode: '5120',
      amountMinorUnits: 1000,
      createdBy: user,
      deviceId: deviceId,
      date: DateTime(2026, 1, 1),
    );
    await expenses.create(
      businessId: businessId,
      accountCode: '5130',
      amountMinorUnits: 2000,
      createdBy: user,
      deviceId: deviceId,
      date: DateTime(2026, 2, 1),
    );

    final list = await expenses.list(businessId: businessId);
    expect(list.length, 2);
    expect(list.first.accountCode, '5130'); // Feb expense listed first
  });

  test('a non-positive expense amount is rejected', () async {
    expect(
      () => expenses.create(
        businessId: businessId,
        accountCode: '5120',
        amountMinorUnits: 0,
        createdBy: user,
        deviceId: deviceId,
      ),
      throwsArgumentError,
    );
  });
}
