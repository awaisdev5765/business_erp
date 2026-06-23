import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../accounting/journal_entry.dart';
import '../sync/sync_queue_item.dart';
import '../sync/sync_queue_repository.dart';
import 'party.dart';

const _uuid = Uuid();

class PartyRepository {
  /// [syncQueue] is optional, same opt-in pattern as elsewhere — without
  /// one, Party creation/updates simply aren't queued for sync.
  PartyRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<Party> create({
    required String businessId,
    required PartyType type,
    required String name,
    String? phone,
    String? address,
    int? creditLimitMinorUnits,
  }) async {
    final now = DateTime.now();
    final party = Party(
      uuid: _uuid.v4(),
      businessId: businessId,
      type: type,
      name: name,
      phone: phone,
      address: address,
      creditLimitMinorUnits: creditLimitMinorUnits,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert(Party.tableName, party.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'Party',
        entityId: party.uuid,
        operation: SyncOperation.create,
      );
    }
    return party;
  }

  Future<void> update(Party party) async {
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: party.businessId,
        entityType: 'Party',
        entityId: party.uuid,
        operation: SyncOperation.update,
      );
    }
    await db.update(
      Party.tableName,
      party.toMap(),
      where: 'uuid = ?',
      whereArgs: [party.uuid],
    );
  }

  Future<List<Party>> list({
    required String businessId,
    required PartyType type,
    bool activeOnly = true,
  }) async {
    final rows = await db.query(
      Party.tableName,
      where: activeOnly
          ? 'business_id = ? AND type = ? AND is_active = 1'
          : 'business_id = ? AND type = ?',
      whereArgs: [businessId, type.name],
      orderBy: 'name ASC',
    );
    return rows.map(Party.fromMap).toList();
  }

  /// Every Party who could plausibly be on payroll — Captains/Crew/
  /// Drivers need salaries same as the generic `employee` role. See
  /// PHASES.md Phase 7.
  Future<List<Party>> listStaff({required String businessId}) async {
    const staffTypes = [PartyType.employee, PartyType.captain, PartyType.crew, PartyType.driver];
    final rows = await db.query(
      Party.tableName,
      where: 'business_id = ? AND type IN (?, ?, ?, ?) AND is_active = 1',
      whereArgs: [businessId, ...staffTypes.map((t) => t.name)],
      orderBy: 'name ASC',
    );
    return rows.map(Party.fromMap).toList();
  }

  Future<Party?> findByUuid(String uuid) async {
    final rows = await db.query(
      Party.tableName,
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : Party.fromMap(rows.first);
  }

  /// Outstanding balance for one party — the Customer/Supplier Ledger is
  /// this query, filtered/ordered for display. Positive = party owes the
  /// business (receivable); negative = business owes the party (payable).
  /// See PHASES.md Section 11 ("sub-ledgers are views, not separate tables").
  Future<int> outstandingBalanceMinorUnits(String partyUuid) async {
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(jl.debit_minor_units), 0) AS total_debit,
        COALESCE(SUM(jl.credit_minor_units), 0) AS total_credit
      FROM ${JournalLine.tableName} jl
      INNER JOIN ${JournalEntry.tableName} je ON je.uuid = jl.entry_uuid
      WHERE jl.party_uuid = ?
        AND je.status != ?
    ''', [partyUuid, JournalEntryStatus.void_.name]);

    final row = result.first;
    final debit = row['total_debit'] as int;
    final credit = row['total_credit'] as int;
    return debit - credit;
  }

  /// Statement of Account — every journal line touching this party,
  /// chronological, for the ledger detail screen.
  Future<List<Map<String, Object?>>> statementOfAccount(String partyUuid) async {
    return db.rawQuery('''
      SELECT je.uuid AS entry_uuid, je.date, je.source_type, je.source_id, je.description,
             jl.debit_minor_units, jl.credit_minor_units, je.status
      FROM ${JournalLine.tableName} jl
      INNER JOIN ${JournalEntry.tableName} je ON je.uuid = jl.entry_uuid
      WHERE jl.party_uuid = ?
      ORDER BY je.date ASC
    ''', [partyUuid]);
  }
}
