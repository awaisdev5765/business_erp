import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/accounting/journal_entry.dart';
import '../../core/accounting/ledger_repository.dart';
import '../../core/activity/trip_repository.dart';
import '../../core/sync/sync_queue_item.dart';
import '../../core/sync/sync_queue_repository.dart';
import 'trip_income.dart';

const _uuid = Uuid();

class TripIncomeRepository {
  TripIncomeRepository(this.db, this.ledger, this.trips, [this.syncQueue]);

  final Database db;
  final LedgerRepository ledger;
  final TripRepository trips;
  final SyncQueueRepository? syncQueue;

  Future<TripIncome> create({
    required String businessId,
    required String tripUuid,
    String? customerUuid,
    String? contractUuid,
    required int amountMinorUnits,
    String? description,
    required TripIncomePaymentMethod paymentMethod,
    required String createdBy,
    required String deviceId,
    DateTime? date,
  }) async {
    if (paymentMethod == TripIncomePaymentMethod.credit && customerUuid == null) {
      throw ArgumentError('Credit trip income must be tied to a customer');
    }

    final trip = await trips.findByUuid(tripUuid);
    if (trip == null) {
      throw StateError('Trip $tripUuid not found');
    }

    final income = TripIncome(
      uuid: _uuid.v4(),
      businessId: businessId,
      tripUuid: tripUuid,
      customerUuid: customerUuid,
      contractUuid: contractUuid,
      amountMinorUnits: amountMinorUnits,
      description: description,
      paymentMethod: paymentMethod,
      date: date ?? DateTime.now(),
    );

    await db.transaction((txn) async {
      await txn.insert(TripIncome.tableName, income.toMap());
      if (syncQueue != null) {
        await syncQueue!.enqueue(
          txn,
          businessId: businessId,
          entityType: 'TripIncome',
          entityId: income.uuid,
          operation: SyncOperation.create,
        );
      }

      await ledger.postWithin(
        txn,
        businessId: businessId,
        sourceType: 'TripIncome',
        sourceId: income.uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        date: income.date,
        description: description ?? 'Trip income',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: paymentMethod == TripIncomePaymentMethod.cash ? '1010' : '1030',
            debitMinorUnits: amountMinorUnits,
            creditMinorUnits: 0,
            partyUuid: paymentMethod == TripIncomePaymentMethod.credit ? customerUuid : null,
            dimensionUuid: trip.assetUuid,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: '4020', // Trip/Catch Income — shared with FishSale
            debitMinorUnits: 0,
            creditMinorUnits: amountMinorUnits,
            dimensionUuid: trip.assetUuid,
          ),
        ],
      );
    });

    return income;
  }

  Future<List<TripIncome>> listByTrip(String tripUuid) async {
    final rows = await db.query(TripIncome.tableName, where: 'trip_uuid = ?', whereArgs: [tripUuid]);
    return rows.map(TripIncome.fromMap).toList();
  }

  Future<int> totalForTrip(String tripUuid) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_minor_units), 0) AS total FROM ${TripIncome.tableName} WHERE trip_uuid = ?',
      [tripUuid],
    );
    return result.first['total'] as int;
  }

  /// Total revenue across every trip ever run by one vehicle — powers
  /// Vehicle Profitability (a per-asset rollup, vs totalForTrip's
  /// per-trip view). Joins through `trips` since TripIncome only stores
  /// `trip_uuid`, not the asset directly.
  Future<int> totalForAsset(String assetUuid) async {
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(ti.amount_minor_units), 0) AS total
      FROM ${TripIncome.tableName} ti
      INNER JOIN trips t ON t.uuid = ti.trip_uuid
      WHERE t.asset_uuid = ?
    ''', [assetUuid]);
    return result.first['total'] as int;
  }

  /// Total revenue across every trip captained/driven by one party —
  /// powers Driver Performance.
  Future<int> totalForDriver(String captainUuid) async {
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(ti.amount_minor_units), 0) AS total
      FROM ${TripIncome.tableName} ti
      INNER JOIN trips t ON t.uuid = ti.trip_uuid
      WHERE t.captain_uuid = ?
    ''', [captainUuid]);
    return result.first['total'] as int;
  }
}
