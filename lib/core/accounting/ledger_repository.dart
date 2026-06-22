import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'journal_entry.dart';

const _uuid = Uuid();

/// Posts and reads JournalEntries. This is the only write path for
/// financial data — modules call [post], never touch account balances
/// directly. See PHASES.md Section 11.
class LedgerRepository {
  LedgerRepository(this.db);

  final Database db;

  Future<JournalEntry> post({
    required String businessId,
    required String sourceType,
    required String sourceId,
    required String createdBy,
    required String deviceId,
    required List<JournalLine> rawLines,
    String? description,
    DateTime? date,
  }) async {
    final uuid = _uuid.v4();
    final lines = rawLines
        .map((l) => JournalLine(
              entryUuid: uuid,
              accountCode: l.accountCode,
              debitMinorUnits: l.debitMinorUnits,
              creditMinorUnits: l.creditMinorUnits,
              partyUuid: l.partyUuid,
              dimensionUuid: l.dimensionUuid,
            ))
        .toList();

    final entry = JournalEntry(
      uuid: uuid,
      businessId: businessId,
      date: date ?? DateTime.now(),
      sourceType: sourceType,
      sourceId: sourceId,
      description: description,
      status: JournalEntryStatus.posted,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      deviceId: deviceId,
      lines: lines,
    );

    if (!entry.isBalanced) {
      throw StateError(
        'JournalEntry rejected: debits != credits for source $sourceType/$sourceId',
      );
    }

    await db.transaction((txn) async {
      await txn.insert(JournalEntry.tableName, entry.toMap());
      for (final line in lines) {
        await txn.insert(JournalLine.tableName, line.toMap());
      }
    });

    return entry;
  }

  /// Reverses a posted entry by appending a new entry with flipped
  /// debits/credits. Never mutates the original's lines — see PHASES.md
  /// Section 11 ("Reversal, not edit"). Only the status flag changes.
  Future<JournalEntry> reverse(
    JournalEntry original, {
    required String createdBy,
    required String deviceId,
  }) async {
    if (original.status != JournalEntryStatus.posted) {
      throw StateError('Only posted entries can be reversed');
    }

    final reversalLines = original.lines
        .map((l) => JournalLine(
              entryUuid: '', // overwritten with the new uuid inside post()
              accountCode: l.accountCode,
              debitMinorUnits: l.creditMinorUnits,
              creditMinorUnits: l.debitMinorUnits,
              partyUuid: l.partyUuid,
              dimensionUuid: l.dimensionUuid,
            ))
        .toList();

    final reversal = await post(
      businessId: original.businessId,
      sourceType: original.sourceType,
      sourceId: original.sourceId,
      createdBy: createdBy,
      deviceId: deviceId,
      rawLines: reversalLines,
      description: 'Reversal of ${original.uuid}',
    );

    await db.update(
      JournalEntry.tableName,
      {'status': JournalEntryStatus.reversed.name},
      where: 'uuid = ?',
      whereArgs: [original.uuid],
    );

    return reversal;
  }

  Future<JournalEntry?> findByUuid(String uuid) async {
    final rows = await db.query(
      JournalEntry.tableName,
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final lineRows = await db.query(
      JournalLine.tableName,
      where: 'entry_uuid = ?',
      whereArgs: [uuid],
    );

    return JournalEntry.fromMap(
      rows.first,
      lines: lineRows.map(JournalLine.fromMap).toList(),
    );
  }

  /// Closing balance for one account, computed with SQL-side aggregation
  /// (SUM/GROUP BY) — the relational query Isar couldn't do cleanly. At
  /// scale this should be served from a rollup table instead (see
  /// PHASES.md Section 12); this direct aggregate query is fine through
  /// Phase 1 and for "today's activity" drill-downs after that.
  ///
  /// Posted AND reversed entries both actually happened — a reversed
  /// entry's effect is cancelled out by its offsetting reversal entry, not
  /// by excluding it from the balance. Only void_ entries are excluded.
  Future<int> accountBalanceMinorUnits({
    required String businessId,
    required String accountCode,
  }) async {
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(jl.debit_minor_units), 0) AS total_debit,
        COALESCE(SUM(jl.credit_minor_units), 0) AS total_credit
      FROM ${JournalLine.tableName} jl
      INNER JOIN ${JournalEntry.tableName} je ON je.uuid = jl.entry_uuid
      WHERE je.business_id = ?
        AND je.status != ?
        AND jl.account_code = ?
    ''', [businessId, JournalEntryStatus.void_.name, accountCode]);

    final row = result.first;
    final debit = row['total_debit'] as int;
    final credit = row['total_credit'] as int;
    return debit - credit;
  }
}
