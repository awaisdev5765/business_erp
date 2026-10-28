import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/sync/sync_queue_item.dart';
import '../../core/sync/sync_queue_repository.dart';
import 'weight_entry.dart';

const _uuid = Uuid();

class WeightEntryRepository {
  WeightEntryRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<WeightEntry> create({
    required String businessId,
    required String vehicleUuid,
    required String companyUuid,
    required double weightKg,
    DateTime? date,
    String? notes,
  }) async {
    if (weightKg <= 0) {
      throw ArgumentError('Weight must be greater than zero');
    }

    final day = date ?? DateTime.now();
    final entry = WeightEntry(
      uuid: _uuid.v4(),
      businessId: businessId,
      vehicleUuid: vehicleUuid,
      companyUuid: companyUuid,
      date: DateTime(day.year, day.month, day.day),
      weightKg: weightKg,
      notes: notes,
    );

    await db.insert(WeightEntry.tableName, entry.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'WeightEntry',
        entityId: entry.uuid,
        operation: SyncOperation.create,
      );
    }
    return entry;
  }

  Future<List<WeightEntry>> list({
    required String businessId,
    String? vehicleUuid,
    String? companyUuid,
    DateTime? from,
    DateTime? to,
  }) async {
    final where = <String>['business_id = ?'];
    final args = <Object>[businessId];
    if (vehicleUuid != null) {
      where.add('vehicle_uuid = ?');
      args.add(vehicleUuid);
    }
    if (companyUuid != null) {
      where.add('company_uuid = ?');
      args.add(companyUuid);
    }
    if (from != null) {
      where.add('date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('date < ?');
      args.add(to.toIso8601String());
    }

    final rows = await db.query(
      WeightEntry.tableName,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, uuid DESC',
    );
    return rows.map(WeightEntry.fromMap).toList();
  }

  Future<List<WeightEntry>> listUnsettledForMonth({
    required String businessId,
    required String companyUuid,
    required int year,
    required int month,
  }) async {
    final from = DateTime(year, month, 1);
    final to = DateTime(year, month + 1, 1);
    final rows = await db.query(
      WeightEntry.tableName,
      where: 'business_id = ? AND company_uuid = ? AND settlement_uuid IS NULL AND date >= ? AND date < ?',
      whereArgs: [businessId, companyUuid, from.toIso8601String(), to.toIso8601String()],
      orderBy: 'date ASC',
    );
    return rows.map(WeightEntry.fromMap).toList();
  }

  Future<List<WeightEntry>> listBySettlement(String settlementUuid) async {
    final rows = await db.query(
      WeightEntry.tableName,
      where: 'settlement_uuid = ?',
      whereArgs: [settlementUuid],
      orderBy: 'date ASC',
    );
    return rows.map(WeightEntry.fromMap).toList();
  }

  Future<void> applySettlementWithin(
    Transaction txn, {
    required String uuid,
    required String businessId,
    required String settlementUuid,
    required int amountMinorUnits,
  }) async {
    await txn.update(
      WeightEntry.tableName,
      {
        'settlement_uuid': settlementUuid,
        'amount_minor_units': amountMinorUnits,
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        txn,
        businessId: businessId,
        entityType: 'WeightEntry',
        entityId: uuid,
        operation: SyncOperation.update,
      );
    }
  }

  Future<WeightEntry?> findByUuid(String uuid) async {
    final rows = await db.query(WeightEntry.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : WeightEntry.fromMap(rows.first);
  }

  /// Only unsettled rows — settled bills are locked after month hisaab.
  Future<WeightEntry> update({
    required String uuid,
    required String vehicleUuid,
    required String companyUuid,
    required double weightKg,
    required DateTime date,
    String? notes,
  }) async {
    if (weightKg <= 0) throw ArgumentError('Weight must be greater than zero');
    final existing = await findByUuid(uuid);
    if (existing == null) throw StateError('Entry not found');
    if (existing.isSettled) throw StateError('Settled bill change nahi ho sakti');

    final updated = WeightEntry(
      uuid: existing.uuid,
      businessId: existing.businessId,
      vehicleUuid: vehicleUuid,
      companyUuid: companyUuid,
      date: DateTime(date.year, date.month, date.day),
      weightKg: weightKg,
      notes: notes,
      settlementUuid: existing.settlementUuid,
      amountMinorUnits: existing.amountMinorUnits,
    );
    await db.update(WeightEntry.tableName, updated.toMap(), where: 'uuid = ?', whereArgs: [uuid]);
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: existing.businessId,
        entityType: 'WeightEntry',
        entityId: uuid,
        operation: SyncOperation.update,
      );
    }
    return updated;
  }

  Future<void> delete(String uuid) async {
    final existing = await findByUuid(uuid);
    if (existing == null) return;
    if (existing.isSettled) throw StateError('Settled bill delete nahi ho sakti');
    await db.delete(WeightEntry.tableName, where: 'uuid = ?', whereArgs: [uuid]);
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: existing.businessId,
        entityType: 'WeightEntry',
        entityId: uuid,
        operation: SyncOperation.delete,
      );
    }
  }

  /// Settled revenue tagged to one vehicle — vehicle khata / profitability.
  Future<int> totalSettledForAsset(String assetUuid) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_minor_units), 0) AS total FROM ${WeightEntry.tableName} '
      'WHERE vehicle_uuid = ? AND amount_minor_units IS NOT NULL',
      [assetUuid],
    );
    return result.first['total'] as int;
  }
}
