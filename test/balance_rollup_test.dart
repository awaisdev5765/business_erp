import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/balance_rollup.dart';
import 'package:business_erp/core/accounting/balance_rollup_repository.dart';
import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/journal_entry.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/party/party.dart';
import 'package:business_erp/core/party/party_repository.dart';
import 'package:business_erp/core/system/database.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late BalanceRollupRepository rollups;
  late LedgerRepository ledgerWithRollups;
  late LedgerRepository ledgerWithoutRollups;
  late PartyRepository partiesWithRollups;
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

    rollups = BalanceRollupRepository(db);
    ledgerWithRollups = LedgerRepository(db, null, null, null, rollups);
    ledgerWithoutRollups = LedgerRepository(db);
    partiesWithRollups = PartyRepository(db, null, rollups);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  Future<JournalEntry> postCashSale(LedgerRepository ledger, {String? customerUuid, int amount = 1000}) =>
      ledger.post(
        businessId: businessId,
        sourceType: 'Sale',
        sourceId: 'sale-${DateTime.now().microsecondsSinceEpoch}',
        createdBy: user,
        deviceId: deviceId,
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: customerUuid != null ? '1030' : '1010',
            debitMinorUnits: amount,
            creditMinorUnits: 0,
            partyUuid: customerUuid,
          ),
          JournalLine(entryUuid: '', accountCode: '4010', debitMinorUnits: 0, creditMinorUnits: amount),
        ],
      );

  test('posting updates the rollup, and accountBalanceMinorUnits reads it directly', () async {
    await postCashSale(ledgerWithRollups, amount: 1500);

    final balance = await ledgerWithRollups.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(balance, 1500);

    // Confirm it's actually coming from the rollup table, not a lucky
    // coincidence with the scan-based fallback.
    final rollupBalance = await rollups.accountBalance(businessId: businessId, accountCode: '1010');
    expect(rollupBalance, 1500);
  });

  test('the rollup path and the scan-based fallback agree on the same data', () async {
    await postCashSale(ledgerWithRollups, amount: 2500);

    final viaRollup = await ledgerWithRollups.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    final viaScan = await ledgerWithoutRollups.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(viaRollup, viaScan);
    expect(viaRollup, 2500);
  });

  test('voiding an entry decrements the rollup so the balance matches the scan-based answer', () async {
    final entry = await postCashSale(ledgerWithRollups, amount: 3000);
    await ledgerWithRollups.void_(entry, voidedBy: user, reason: 'mistake');

    final viaRollup = await ledgerWithRollups.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    final viaScan = await ledgerWithoutRollups.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(viaRollup, 0);
    expect(viaRollup, viaScan);
  });

  test('reversing an entry does NOT touch the rollup directly — the reversal entry posts its own offsetting rollup update', () async {
    final entry = await postCashSale(ledgerWithRollups, amount: 4000);
    await ledgerWithRollups.reverse(entry, createdBy: user, deviceId: deviceId);

    final viaRollup = await ledgerWithRollups.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(viaRollup, 0); // original 4000 + reversal -4000
  });

  test('trialBalance from the rollup matches the scan-based trialBalance', () async {
    await postCashSale(ledgerWithRollups, amount: 5000);

    final viaRollup = await ledgerWithRollups.trialBalance(businessId: businessId);
    final viaScan = await ledgerWithoutRollups.trialBalance(businessId: businessId);

    final rollupCash = viaRollup.firstWhere((r) => r['code'] == '1010');
    final scanCash = viaScan.firstWhere((r) => r['code'] == '1010');
    expect(rollupCash['total_debit'], scanCash['total_debit']);
    expect(rollupCash['total_credit'], scanCash['total_credit']);
  });

  test('outstandingBalanceMinorUnits reads from the party rollup when wired in', () async {
    final customer = await partiesWithRollups.create(businessId: businessId, type: PartyType.customer, name: 'Acme');
    await postCashSale(ledgerWithRollups, customerUuid: customer.uuid, amount: 7500);

    final balance = await partiesWithRollups.outstandingBalanceMinorUnits(customer.uuid);
    expect(balance, 7500);

    final rollupBalance = await rollups.partyBalance(customer.uuid);
    expect(rollupBalance, 7500);
  });

  test('rebuildAll() recomputes rollups from raw journal_lines, matching what was there before', () async {
    final customer = await partiesWithRollups.create(businessId: businessId, type: PartyType.customer, name: 'Acme');
    await postCashSale(ledgerWithRollups, customerUuid: customer.uuid, amount: 9000);
    await postCashSale(ledgerWithRollups, amount: 1200);

    final beforeAccount = await rollups.accountBalance(businessId: businessId, accountCode: '1030');
    final beforeParty = await rollups.partyBalance(customer.uuid);

    // Simulate corruption/drift: wipe the rollups directly, bypassing
    // the normal increment path.
    await db.delete(AccountBalanceRollup.tableName, where: 'business_id = ?', whereArgs: [businessId]);
    await db.delete(PartyBalanceRollup.tableName, where: 'party_uuid = ?', whereArgs: [customer.uuid]);
    expect(await rollups.accountBalance(businessId: businessId, accountCode: '1030'), 0);

    await rollups.rebuildAll(businessId);

    expect(await rollups.accountBalance(businessId: businessId, accountCode: '1030'), beforeAccount);
    expect(await rollups.partyBalance(customer.uuid), beforeParty);
  });

  test('rebuildAll() clears a stale party rollup even when that party has no remaining non-void lines', () async {
    final customer = await partiesWithRollups.create(businessId: businessId, type: PartyType.customer, name: 'Acme');
    final entry = await postCashSale(ledgerWithRollups, customerUuid: customer.uuid, amount: 6000);
    expect(await rollups.partyBalance(customer.uuid), 6000);

    await ledgerWithRollups.void_(entry, voidedBy: user, reason: 'mistake');
    expect(await rollups.partyBalance(customer.uuid), 0); // void_ already decremented it correctly

    // Force the rollup back out of sync with reality, then prove
    // rebuildAll() still zeroes it even though this customer has no
    // non-void lines left to aggregate from.
    await db.update(PartyBalanceRollup.tableName, {'debit_total': 9999}, where: 'party_uuid = ?', whereArgs: [customer.uuid]);
    expect(await rollups.partyBalance(customer.uuid), 9999);

    await rollups.rebuildAll(businessId);
    expect(await rollups.partyBalance(customer.uuid), 0);
  });
}
