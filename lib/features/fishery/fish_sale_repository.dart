import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/accounting/journal_entry.dart';
import '../../core/accounting/ledger_repository.dart';
import '../../core/activity/trip_repository.dart';
import '../../core/sync/sync_queue_item.dart';
import '../../core/sync/sync_queue_repository.dart';
import 'fish_sale.dart';

const _uuid = Uuid();

class FishSaleRepository {
  FishSaleRepository(this.db, this.ledger, this.trips, [this.syncQueue]);

  final Database db;
  final LedgerRepository ledger;
  final TripRepository trips;
  final SyncQueueRepository? syncQueue;

  Future<FishSale> create({
    required String businessId,
    required String tripUuid,
    String? customerUuid,
    required String fishCategoryUuid,
    required double weightKg,
    required int unitPriceMinorUnitsPerKg,
    required FishSalePaymentMethod paymentMethod,
    required String createdBy,
    required String deviceId,
    DateTime? date,
  }) async {
    if (paymentMethod == FishSalePaymentMethod.credit && customerUuid == null) {
      throw ArgumentError('Credit fish sales must be tied to a customer');
    }

    final trip = await trips.findByUuid(tripUuid);
    if (trip == null) {
      throw StateError('Trip $tripUuid not found');
    }

    final sale = FishSale(
      uuid: _uuid.v4(),
      businessId: businessId,
      tripUuid: tripUuid,
      customerUuid: customerUuid,
      fishCategoryUuid: fishCategoryUuid,
      weightKg: weightKg,
      unitPriceMinorUnitsPerKg: unitPriceMinorUnitsPerKg,
      paymentMethod: paymentMethod,
      date: date ?? DateTime.now(),
    );

    final totalMinorUnits = sale.totalMinorUnits;

    await db.transaction((txn) async {
      await txn.insert(FishSale.tableName, sale.toMap());
      if (syncQueue != null) {
        await syncQueue!.enqueue(
          txn,
          businessId: businessId,
          entityType: 'FishSale',
          entityId: sale.uuid,
          operation: SyncOperation.create,
        );
      }

      await ledger.postWithin(
        txn,
        businessId: businessId,
        sourceType: 'FishSale',
        sourceId: sale.uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        date: sale.date,
        description: 'Fish sale ${weightKg}kg',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: paymentMethod == FishSalePaymentMethod.cash ? '1010' : '1030',
            debitMinorUnits: totalMinorUnits,
            creditMinorUnits: 0,
            partyUuid: paymentMethod == FishSalePaymentMethod.credit ? customerUuid : null,
            dimensionUuid: trip.assetUuid,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: '4020', // Trip/Catch Income
            debitMinorUnits: 0,
            creditMinorUnits: totalMinorUnits,
            dimensionUuid: trip.assetUuid,
          ),
        ],
      );
    });

    return sale;
  }

  Future<List<FishSale>> listByTrip(String tripUuid) async {
    final rows = await db.query(FishSale.tableName, where: 'trip_uuid = ?', whereArgs: [tripUuid]);
    return rows.map(FishSale.fromMap).toList();
  }

  Future<int> totalForTrip(String tripUuid) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(weight_kg * unit_price_minor_units_per_kg), 0) AS total FROM ${FishSale.tableName} WHERE trip_uuid = ?',
      [tripUuid],
    );
    final raw = result.first['total'];
    return raw is int ? raw : (raw as double).round();
  }
}
