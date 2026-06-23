import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/bank_account_repository.dart';
import 'package:business_erp/core/system/database.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late BankAccountRepository bankAccounts;
  const businessId = 'business-1';

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
    bankAccounts = BankAccountRepository(db);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('cleared balance is opening balance plus only the cleared statement lines', () async {
    final account = await bankAccounts.create(
      businessId: businessId,
      name: 'Main Account',
      openingBalanceMinorUnits: 10000,
    );

    final deposit = await bankAccounts.addStatementLine(
      bankAccountUuid: account.uuid,
      date: DateTime(2026, 1, 5),
      description: 'Customer deposit',
      amountMinorUnits: 5000,
    );
    await bankAccounts.addStatementLine(
      bankAccountUuid: account.uuid,
      date: DateTime(2026, 1, 6),
      description: 'Uncleared withdrawal',
      amountMinorUnits: -2000,
    );

    // Only the deposit is marked cleared; the withdrawal stays pending.
    await bankAccounts.setCleared(deposit.uuid, true);

    final balance = await bankAccounts.clearedBalanceMinorUnits(account);
    expect(balance, 15000); // 10000 opening + 5000 cleared deposit, withdrawal excluded
  });

  test('toggling a line back to uncleared removes it from the cleared balance again', () async {
    final account = await bankAccounts.create(
      businessId: businessId,
      name: 'Main Account',
      openingBalanceMinorUnits: 0,
    );

    final line = await bankAccounts.addStatementLine(
      bankAccountUuid: account.uuid,
      date: DateTime(2026, 1, 5),
      description: 'Deposit',
      amountMinorUnits: 3000,
    );

    await bankAccounts.setCleared(line.uuid, true);
    expect(await bankAccounts.clearedBalanceMinorUnits(account), 3000);

    await bankAccounts.setCleared(line.uuid, false);
    expect(await bankAccounts.clearedBalanceMinorUnits(account), 0);
  });
}
