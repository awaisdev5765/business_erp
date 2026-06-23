import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/party/party.dart';
import 'package:business_erp/core/party/party_repository.dart';
import 'package:business_erp/core/system/database.dart';
import 'package:business_erp/core/transaction/salary_repository.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late LedgerRepository ledger;
  late PartyRepository parties;
  late SalaryRepository salaries;
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
    parties = PartyRepository(db);
    salaries = SalaryRepository(db, ledger);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('paying a salary posts Dr Salary Expense / Cr Cash, tagged to the employee', () async {
    final employee = await parties.create(businessId: businessId, type: PartyType.employee, name: 'Cashier Nimal');
    final record = await salaries.createRecord(businessId: businessId, partyUuid: employee.uuid, amountMinorUnits: 50000);

    await salaries.paySalary(record: record, period: '2026-06', createdBy: user, deviceId: deviceId);

    final expenseBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '5100');
    expect(expenseBalance, 50000);
    final cashBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(cashBalance, -50000);

    final statement = await parties.statementOfAccount(employee.uuid);
    expect(statement.length, 1);
    expect(statement.first['debit_minor_units'], 50000);
  });

  test('a salary record works for Captain/Crew/Driver party types too, not just employee', () async {
    final captain = await parties.create(businessId: businessId, type: PartyType.captain, name: 'Captain Silva');
    final record = await salaries.createRecord(businessId: businessId, partyUuid: captain.uuid, amountMinorUnits: 80000);

    final payment = await salaries.paySalary(record: record, period: '2026-06', createdBy: user, deviceId: deviceId);
    expect(payment.amountMinorUnits, 80000);
  });

  test('the same record cannot be paid twice for the same period', () async {
    final employee = await parties.create(businessId: businessId, type: PartyType.employee, name: 'Cashier Nimal');
    final record = await salaries.createRecord(businessId: businessId, partyUuid: employee.uuid, amountMinorUnits: 50000);

    await salaries.paySalary(record: record, period: '2026-06', createdBy: user, deviceId: deviceId);

    expect(
      () => salaries.paySalary(record: record, period: '2026-06', createdBy: user, deviceId: deviceId),
      throwsStateError,
    );
  });

  test('the same record can be paid for different periods', () async {
    final employee = await parties.create(businessId: businessId, type: PartyType.employee, name: 'Cashier Nimal');
    final record = await salaries.createRecord(businessId: businessId, partyUuid: employee.uuid, amountMinorUnits: 50000);

    await salaries.paySalary(record: record, period: '2026-06', createdBy: user, deviceId: deviceId);
    await salaries.paySalary(record: record, period: '2026-07', createdBy: user, deviceId: deviceId);

    final history = await salaries.paymentHistory(record.uuid);
    expect(history.length, 2);

    final expenseBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '5100');
    expect(expenseBalance, 100000);
  });
}
