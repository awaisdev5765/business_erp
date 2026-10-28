import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../accounting/journal_entry.dart';
import '../accounting/ledger_repository.dart';
import '../sync/sync_queue_item.dart';
import '../sync/sync_queue_repository.dart';
import 'trip_expense.dart';
import 'trip_repository.dart';

const _uuid = Uuid();

class TripExpenseRepository {
  TripExpenseRepository(this.db, this.ledger, this.trips, [this.syncQueue]);

  final Database db;
  final LedgerRepository ledger;
  final TripRepository trips;
  final SyncQueueRepository? syncQueue;

  Future<TripExpense> record({
    required String businessId,
    required String tripUuid,
    required TripExpenseCategory category,
    required int amountMinorUnits,
    String? description,
    required String createdBy,
    required String deviceId,
    DateTime? date,
  }) async {
    final trip = await trips.findByUuid(tripUuid);
    if (trip == null) {
      throw StateError('Trip $tripUuid not found');
    }

    return _insertAndPost(
      businessId: businessId,
      tripUuid: tripUuid,
      assetUuid: trip.assetUuid,
      category: category,
      amountMinorUnits: amountMinorUnits,
      description: description,
      createdBy: createdBy,
      deviceId: deviceId,
      date: date,
    );
  }

  /// Vehicle khata expense — no trip. Same accounts as trip expenses,
  /// tagged directly to the vehicle so the khata shows fuel/tyre/repair.
  Future<TripExpense> recordForVehicle({
    required String businessId,
    required String assetUuid,
    required TripExpenseCategory category,
    required int amountMinorUnits,
    String? description,
    required String createdBy,
    required String deviceId,
    DateTime? date,
  }) {
    return _insertAndPost(
      businessId: businessId,
      tripUuid: null,
      assetUuid: assetUuid,
      category: category,
      amountMinorUnits: amountMinorUnits,
      description: description,
      createdBy: createdBy,
      deviceId: deviceId,
      date: date,
    );
  }

  Future<TripExpense> _insertAndPost({
    required String businessId,
    required String? tripUuid,
    required String assetUuid,
    required TripExpenseCategory category,
    required int amountMinorUnits,
    String? description,
    required String createdBy,
    required String deviceId,
    DateTime? date,
  }) async {
    final expense = TripExpense(
      uuid: _uuid.v4(),
      tripUuid: tripUuid,
      assetUuid: assetUuid,
      businessId: businessId,
      category: category,
      amountMinorUnits: amountMinorUnits,
      description: description,
      date: date ?? DateTime.now(),
    );

    await db.transaction((txn) async {
      await txn.insert(TripExpense.tableName, expense.toMap());
      if (syncQueue != null) {
        await syncQueue!.enqueue(
          txn,
          businessId: businessId,
          entityType: 'TripExpense',
          entityId: expense.uuid,
          operation: SyncOperation.create,
        );
      }

      await ledger.postWithin(
        txn,
        businessId: businessId,
        sourceType: 'TripExpense',
        sourceId: expense.uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        date: expense.date,
        description: description ?? '${category.name} expense',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: tripExpenseAccountCode[category]!,
            debitMinorUnits: amountMinorUnits,
            creditMinorUnits: 0,
            dimensionUuid: assetUuid,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: '1010', // Cash on Hand
            debitMinorUnits: 0,
            creditMinorUnits: amountMinorUnits,
            dimensionUuid: assetUuid,
          ),
        ],
      );
    });

    return expense;
  }

  Future<List<TripExpense>> listByTrip(String tripUuid) async {
    final rows = await db.query(TripExpense.tableName, where: 'trip_uuid = ?', whereArgs: [tripUuid]);
    return rows.map(TripExpense.fromMap).toList();
  }

  Future<List<TripExpense>> listByAsset(String assetUuid) async {
    final rows = await db.query(
      TripExpense.tableName,
      where: 'asset_uuid = ?',
      whereArgs: [assetUuid],
      orderBy: 'date DESC',
    );
    return rows.map(TripExpense.fromMap).toList();
  }

  Future<int> totalForTrip(String tripUuid) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_minor_units), 0) AS total FROM ${TripExpense.tableName} WHERE trip_uuid = ?',
      [tripUuid],
    );
    return result.first['total'] as int;
  }

  /// Total expenses across every trip ever run by one asset (boat or
  /// vehicle) — powers Boat/Vehicle Profitability rollups, the per-asset
  /// counterpart to totalForTrip's per-trip view.
  Future<int> totalForAsset(String assetUuid) async {
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(te.amount_minor_units), 0) AS total
      FROM ${TripExpense.tableName} te
      LEFT JOIN trips t ON t.uuid = te.trip_uuid
      WHERE te.asset_uuid = ? OR t.asset_uuid = ?
    ''', [assetUuid, assetUuid]);
    return result.first['total'] as int;
  }

  /// Total expenses across every trip captained/driven by one party —
  /// powers Driver Performance.
  Future<int> totalForDriver(String captainUuid) async {
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(te.amount_minor_units), 0) AS total
      FROM ${TripExpense.tableName} te
      INNER JOIN trips t ON t.uuid = te.trip_uuid
      WHERE t.captain_uuid = ?
    ''', [captainUuid]);
    return result.first['total'] as int;
  }
}
