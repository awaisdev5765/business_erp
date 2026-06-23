import 'package:sqflite/sqflite.dart';

import '../party/party.dart';
import 'account.dart';
import 'balance_rollup.dart';
import 'journal_entry.dart';

/// Maintains and reads [AccountBalanceRollup]/[PartyBalanceRollup]. The
/// only writer is [applyLine], called from `LedgerRepository.postWithin()`
/// for every line of every posting (and with negated deltas from
/// `void_()`, to un-count a voided entry's effect — see PHASES.md Phase 8).
class BalanceRollupRepository {
  BalanceRollupRepository(this.db);

  final Database db;

  /// Adds [debitDelta]/[creditDelta] to the rollup for [accountCode] (and
  /// for [partyUuid]'s rollup, if given). Pass negative deltas to undo a
  /// voided entry's contribution. Uses `INSERT ... ON CONFLICT DO UPDATE`
  /// so the very first line for an account/party creates its row.
  Future<void> applyLine(
    DatabaseExecutor txn, {
    required String businessId,
    required String accountCode,
    required int debitDelta,
    required int creditDelta,
    String? partyUuid,
  }) async {
    await txn.rawInsert('''
      INSERT INTO ${AccountBalanceRollup.tableName} (business_id, account_code, debit_total, credit_total)
      VALUES (?, ?, ?, ?)
      ON CONFLICT (business_id, account_code) DO UPDATE SET
        debit_total = debit_total + excluded.debit_total,
        credit_total = credit_total + excluded.credit_total
    ''', [businessId, accountCode, debitDelta, creditDelta]);

    if (partyUuid != null) {
      await txn.rawInsert('''
        INSERT INTO ${PartyBalanceRollup.tableName} (party_uuid, debit_total, credit_total)
        VALUES (?, ?, ?)
        ON CONFLICT (party_uuid) DO UPDATE SET
          debit_total = debit_total + excluded.debit_total,
          credit_total = credit_total + excluded.credit_total
      ''', [partyUuid, debitDelta, creditDelta]);
    }
  }

  Future<int> accountBalance({required String businessId, required String accountCode}) async {
    final rows = await db.query(
      AccountBalanceRollup.tableName,
      where: 'business_id = ? AND account_code = ?',
      whereArgs: [businessId, accountCode],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['debit_total'] as int) - (rows.first['credit_total'] as int);
  }

  Future<int> partyBalance(String partyUuid) async {
    final rows = await db.query(PartyBalanceRollup.tableName, where: 'party_uuid = ?', whereArgs: [partyUuid], limit: 1);
    if (rows.isEmpty) return 0;
    return (rows.first['debit_total'] as int) - (rows.first['credit_total'] as int);
  }

  /// Every account's Dr/Cr totals for [businessId] — the rollup-backed
  /// Trial Balance. Naturally business-scoped: the rollup's primary key
  /// is `(business_id, account_code)`, so unlike the original
  /// `journal_lines`-scanning version (see PHASES.md Section 16's
  /// multi-tenant bug note from Phase 1), there's no join condition to
  /// get wrong here — a join on `business_id` is correct by construction.
  Future<List<Map<String, Object?>>> trialBalance({required String businessId}) async {
    return db.rawQuery('''
      SELECT a.code, a.name, a.type,
             COALESCE(r.debit_total, 0) AS total_debit,
             COALESCE(r.credit_total, 0) AS total_credit
      FROM ${Account.tableName} a
      LEFT JOIN ${AccountBalanceRollup.tableName} r
        ON r.business_id = a.business_id AND r.account_code = a.code
      WHERE a.business_id = ?
      ORDER BY a.code ASC
    ''', [businessId]);
  }

  /// Recomputes every rollup row for [businessId] from raw
  /// `journal_lines`/`journal_entries` — the same aggregation the
  /// pre-rollup implementation always did. Not run automatically; this
  /// is the migration path for a database that had entries posted before
  /// the rollup tables existed (see PHASES.md Phase 8), or a manual
  /// "fix drift" tool if a rollup and the raw ledger ever disagree.
  Future<void> rebuildAll(String businessId) async {
    await db.transaction((txn) async {
      await txn.delete(AccountBalanceRollup.tableName, where: 'business_id = ?', whereArgs: [businessId]);

      // Clear every rollup for this business's parties first — not just
      // the ones that still have non-void lines. Otherwise a party whose
      // only entries all got voided since the last rebuild would keep a
      // stale nonzero rollup forever (nothing in the loop below would
      // ever touch their row, since they wouldn't appear in partyTotals).
      await txn.delete(
        PartyBalanceRollup.tableName,
        where: 'party_uuid IN (SELECT uuid FROM ${Party.tableName} WHERE business_id = ?)',
        whereArgs: [businessId],
      );

      final accountTotals = await txn.rawQuery('''
        SELECT jl.account_code AS account_code,
               COALESCE(SUM(jl.debit_minor_units), 0) AS debit_total,
               COALESCE(SUM(jl.credit_minor_units), 0) AS credit_total
        FROM ${JournalLine.tableName} jl
        INNER JOIN ${JournalEntry.tableName} je ON je.uuid = jl.entry_uuid
        WHERE je.business_id = ? AND je.status != ?
        GROUP BY jl.account_code
      ''', [businessId, JournalEntryStatus.void_.name]);

      for (final row in accountTotals) {
        await txn.insert(AccountBalanceRollup.tableName, {
          'business_id': businessId,
          'account_code': row['account_code'],
          'debit_total': row['debit_total'],
          'credit_total': row['credit_total'],
        });
      }

      final partyTotals = await txn.rawQuery('''
        SELECT jl.party_uuid AS party_uuid,
               COALESCE(SUM(jl.debit_minor_units), 0) AS debit_total,
               COALESCE(SUM(jl.credit_minor_units), 0) AS credit_total
        FROM ${JournalLine.tableName} jl
        INNER JOIN ${JournalEntry.tableName} je ON je.uuid = jl.entry_uuid
        WHERE je.business_id = ? AND je.status != ? AND jl.party_uuid IS NOT NULL
        GROUP BY jl.party_uuid
      ''', [businessId, JournalEntryStatus.void_.name]);

      for (final row in partyTotals) {
        await txn.insert(PartyBalanceRollup.tableName, {
          'party_uuid': row['party_uuid'],
          'debit_total': row['debit_total'],
          'credit_total': row['credit_total'],
        });
      }
    });
  }
}
