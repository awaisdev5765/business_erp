import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../system/audit_log_repository.dart';
import 'account.dart';
import 'fiscal_period_repository.dart';
import 'journal_entry.dart';

const _uuid = Uuid();

/// Posts and reads JournalEntries. This is the only write path for
/// financial data — modules call [post], never touch account balances
/// directly. See PHASES.md Section 11.
class LedgerRepository {
  /// [fiscalPeriods] and [auditLog] are both optional — a business that
  /// hasn't configured fiscal periods posts freely (Phase 0/1 behavior
  /// unchanged), and without an audit log wired in, void/reverse simply
  /// skip writing an audit entry rather than failing.
  LedgerRepository(this.db, [this.fiscalPeriods, this.auditLog]);

  final Database db;
  final FiscalPeriodRepository? fiscalPeriods;
  final AuditLogRepository? auditLog;

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
    return db.transaction((txn) => postWithin(
          txn,
          businessId: businessId,
          sourceType: sourceType,
          sourceId: sourceId,
          createdBy: createdBy,
          deviceId: deviceId,
          rawLines: rawLines,
          description: description,
          date: date,
        ));
  }

  /// Same as [post], but runs against an already-open [DatabaseExecutor]
  /// (i.e. inside someone else's `db.transaction`). Use this from
  /// composed flows — e.g. Sale posting both a JournalEntry and a
  /// StockMovement — so both writes commit or roll back together.
  /// sqflite doesn't support nested transactions, which is why this can't
  /// just call [post] internally.
  Future<JournalEntry> postWithin(
    DatabaseExecutor txn, {
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

    if (fiscalPeriods != null) {
      await fiscalPeriods!.assertOpenForPosting(txn, businessId: businessId, date: entry.date);
    }

    await txn.insert(JournalEntry.tableName, entry.toMap());
    for (final line in lines) {
      await txn.insert(JournalLine.tableName, line.toMap());
    }

    return entry;
  }

  /// Reverses a posted entry by appending a new entry with flipped
  /// debits/credits. Never mutates the original's lines — see PHASES.md
  /// Section 11 ("Reversal, not edit"). Only the status flag changes.
  /// Use this when the entry was correct *at the time* but later needs
  /// correcting (a refund, a pricing error caught after the fact) — the
  /// original's effect stays in history, offset by the reversal. Contrast
  /// with [void_], which is for entries that should never have counted at
  /// all (e.g. a duplicate or test entry caught the same day).
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

    if (auditLog != null) {
      await auditLog!.log(
        businessId: original.businessId,
        action: 'reverse',
        entityType: 'JournalEntry',
        entityId: original.uuid,
        performedBy: createdBy,
        details: 'Reversed by new entry ${reversal.uuid}',
      );
    }

    return reversal;
  }

  /// Voids a posted entry: marks it `void_` and nothing else. No
  /// offsetting entry is needed — every balance/statement/trial-balance
  /// query already filters `status != void_` (see accountBalanceMinorUnits
  /// etc. below), so a voided entry simply stops contributing anywhere,
  /// while the row itself is kept forever (no hard deletes, per PHASES.md
  /// Section 11). Use this only for entries that should never have had any
  /// effect — for entries that genuinely happened and need correcting
  /// later, use [reverse] instead.
  Future<void> void_(
    JournalEntry original, {
    required String voidedBy,
    required String reason,
  }) async {
    if (original.status != JournalEntryStatus.posted) {
      throw StateError('Only posted entries can be voided');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('A void requires a reason — this is permanent audit trail text');
    }

    await db.update(
      JournalEntry.tableName,
      {
        'status': JournalEntryStatus.void_.name,
        'description': 'VOIDED by $voidedBy: $reason'
            '${original.description != null ? ' (was: ${original.description})' : ''}',
      },
      where: 'uuid = ?',
      whereArgs: [original.uuid],
    );

    if (auditLog != null) {
      await auditLog!.log(
        businessId: original.businessId,
        action: 'void',
        entityType: 'JournalEntry',
        entityId: original.uuid,
        performedBy: voidedBy,
        details: reason,
      );
    }
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

  /// Every JournalLine posted to one account, chronological — the Cash
  /// Book is this query against account "1010", same pattern as
  /// PartyRepository.statementOfAccount(). See PHASES.md Section 11.
  Future<List<Map<String, Object?>>> accountStatement({
    required String businessId,
    required String accountCode,
  }) async {
    return db.rawQuery('''
      SELECT je.uuid AS entry_uuid, je.date, je.source_type, je.source_id, je.description, je.status,
             jl.debit_minor_units, jl.credit_minor_units
      FROM ${JournalLine.tableName} jl
      INNER JOIN ${JournalEntry.tableName} je ON je.uuid = jl.entry_uuid
      WHERE je.business_id = ?
        AND je.status != ?
        AND jl.account_code = ?
      ORDER BY je.date ASC
    ''', [businessId, JournalEntryStatus.void_.name, accountCode]);
  }

  /// Every JournalLine tagged with one dimension (a Boat or Vehicle uuid),
  /// across *all* accounts — the Boat/Vehicle Ledger is this query,
  /// chronological. Unlike accountStatement() (one account, any
  /// dimension), this is one dimension, any account — e.g. a boat's fuel
  /// expense (5020), ice expense (5040), and catch revenue (4020) all show
  /// up together here. See PHASES.md Section 11.
  Future<List<Map<String, Object?>>> dimensionStatement({
    required String businessId,
    required String dimensionUuid,
  }) async {
    return db.rawQuery('''
      SELECT je.uuid AS entry_uuid, je.date, je.source_type, je.source_id, je.description, je.status,
             jl.account_code, jl.debit_minor_units, jl.credit_minor_units
      FROM ${JournalLine.tableName} jl
      INNER JOIN ${JournalEntry.tableName} je ON je.uuid = jl.entry_uuid
      WHERE je.business_id = ?
        AND je.status != ?
        AND jl.dimension_uuid = ?
      ORDER BY je.date ASC
    ''', [businessId, JournalEntryStatus.void_.name, dimensionUuid]);
  }

  /// Trial Balance: every account's Dr/Cr totals and net balance, in one
  /// grouped query — the SQL aggregation Isar couldn't do cleanly (this is
  /// the concrete payoff of the sqflite switch documented in PHASES.md
  /// Phase 0).
  ///
  /// Joins journal_entries (business-scoped) before journal_lines, rather
  /// than joining lines on account_code directly — account codes are only
  /// unique *within* a business (UNIQUE(business_id, code)), so joining
  /// lines straight to accounts on code alone would pull in another
  /// business's lines if they happened to share a code (e.g. both have a
  /// "1010" account). Multi-tenant isolation has to hold at the query
  /// level, not just the UI level — see PHASES.md Section 16.
  Future<List<Map<String, Object?>>> trialBalance({required String businessId}) async {
    return db.rawQuery('''
      SELECT a.code, a.name, a.type,
             COALESCE(SUM(jl.debit_minor_units), 0) AS total_debit,
             COALESCE(SUM(jl.credit_minor_units), 0) AS total_credit
      FROM ${Account.tableName} a
      LEFT JOIN ${JournalEntry.tableName} je
        ON je.business_id = a.business_id AND je.status != ?
      LEFT JOIN ${JournalLine.tableName} jl
        ON jl.entry_uuid = je.uuid AND jl.account_code = a.code
      WHERE a.business_id = ?
      GROUP BY a.code, a.name, a.type
      ORDER BY a.code ASC
    ''', [JournalEntryStatus.void_.name, businessId]);
  }
}
