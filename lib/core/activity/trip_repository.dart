import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'trip.dart';

const _uuid = Uuid();

class TripRepository {
  TripRepository(this.db);

  final Database db;

  Future<Trip> create({
    required String businessId,
    required TripType tripType,
    required String assetUuid,
    String? captainUuid,
    DateTime? startDate,
    String? notes,
  }) async {
    final trip = Trip(
      uuid: _uuid.v4(),
      businessId: businessId,
      tripType: tripType,
      assetUuid: assetUuid,
      captainUuid: captainUuid,
      status: TripStatus.planned,
      startDate: startDate ?? DateTime.now(),
      notes: notes,
    );
    await db.insert(Trip.tableName, trip.toMap());
    return trip;
  }

  Future<void> start(String tripUuid) async {
    await db.update(
      Trip.tableName,
      {'status': TripStatus.inProgress.name},
      where: 'uuid = ?',
      whereArgs: [tripUuid],
    );
  }

  Future<void> complete(String tripUuid, {DateTime? endDate}) async {
    await db.update(
      Trip.tableName,
      {
        'status': TripStatus.completed.name,
        'end_date': (endDate ?? DateTime.now()).toIso8601String(),
      },
      where: 'uuid = ?',
      whereArgs: [tripUuid],
    );
  }

  Future<Trip?> findByUuid(String uuid) async {
    final rows = await db.query(Trip.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : Trip.fromMap(rows.first);
  }

  Future<List<Trip>> list({required String businessId, required TripType tripType}) async {
    final rows = await db.query(
      Trip.tableName,
      where: 'business_id = ? AND trip_type = ?',
      whereArgs: [businessId, tripType.name],
      orderBy: 'start_date DESC',
    );
    return rows.map(Trip.fromMap).toList();
  }

  Future<List<Trip>> listByAsset({required String assetUuid}) async {
    final rows = await db.query(
      Trip.tableName,
      where: 'asset_uuid = ?',
      whereArgs: [assetUuid],
      orderBy: 'start_date DESC',
    );
    return rows.map(Trip.fromMap).toList();
  }
}
