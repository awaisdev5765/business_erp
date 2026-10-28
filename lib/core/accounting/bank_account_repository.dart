import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../sync/sync_queue_item.dart';
import '../sync/sync_queue_repository.dart';
import 'bank_account.dart';

const _uuid = Uuid();

class BankAccountRepository {
  BankAccountRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<BankAccount> create({
    required String businessId,
    required String name,
    String? bankName,
    String? accountNumber,
    int openingBalanceMinorUnits = 0,
  }) async {
    final account = BankAccount(
      uuid: _uuid.v4(),
      businessId: businessId,
      name: name,
      bankName: bankName,
      accountNumber: accountNumber,
      openingBalanceMinorUnits: openingBalanceMinorUnits,
    );
    await db.insert(BankAccount.tableName, account.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'BankAccount',
        entityId: account.uuid,
        operation: SyncOperation.create,
      );
    }
    return account;
  }

  Future<List<BankAccount>> list({required String businessId}) async {
    final rows = await db.query(
      BankAccount.tableName,
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'name ASC',
    );
    return rows.map(BankAccount.fromMap).toList();
  }

  Future<BankStatementLine> addStatementLine({
    required String bankAccountUuid,
    required DateTime date,
    required String description,
    required int amountMinorUnits,
  }) async {
    final line = BankStatementLine(
      uuid: _uuid.v4(),
      bankAccountUuid: bankAccountUuid,
      date: date,
      description: description,
      amountMinorUnits: amountMinorUnits,
    );
    await db.insert(BankStatementLine.tableName, line.toMap());
    if (syncQueue != null) {
      // BankStatementLine has no business_id column of its own (it only
      // references bankAccountUuid) — look up the owning account's
      // business so the sync queue item, which every other entity keys
      // by businessId, can still be scoped/filtered the same way.
      final accountRows = await db.query(BankAccount.tableName, where: 'uuid = ?', whereArgs: [bankAccountUuid], limit: 1);
      if (accountRows.isNotEmpty) {
        await syncQueue!.enqueue(
          db,
          businessId: accountRows.first['business_id'] as String,
          entityType: 'BankStatementLine',
          entityId: line.uuid,
          operation: SyncOperation.create,
        );
      }
    }
    return line;
  }

  Future<void> setCleared(String statementLineUuid, bool isCleared) async {
    await db.update(
      BankStatementLine.tableName,
      {'is_cleared': isCleared ? 1 : 0},
      where: 'uuid = ?',
      whereArgs: [statementLineUuid],
    );
  }

  Future<List<BankStatementLine>> statementLines({required String bankAccountUuid}) async {
    final rows = await db.query(
      BankStatementLine.tableName,
      where: 'bank_account_uuid = ?',
      whereArgs: [bankAccountUuid],
      orderBy: 'date ASC',
    );
    return rows.map(BankStatementLine.fromMap).toList();
  }

  /// Cleared balance = opening balance + every cleared statement line's
  /// signed amount. Reconciliation is "does this equal the bank's stated
  /// closing balance for the same period" — the UI does that comparison.
  Future<int> clearedBalanceMinorUnits(BankAccount account) async {
    final lines = await statementLines(bankAccountUuid: account.uuid);
    final clearedTotal = lines.where((l) => l.isCleared).fold<int>(0, (sum, l) => sum + l.amountMinorUnits);
    return account.openingBalanceMinorUnits + clearedTotal;
  }
}
