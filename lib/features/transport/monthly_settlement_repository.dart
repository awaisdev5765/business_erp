import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/accounting/journal_entry.dart';
import '../../core/accounting/ledger_repository.dart';
import '../../core/sync/sync_queue_item.dart';
import '../../core/sync/sync_queue_repository.dart';
import 'monthly_settlement.dart';
import 'vehicle_khata_repository.dart';
import 'weight_entry_repository.dart';

const _uuid = Uuid();

/// Company bills store kg; rate is Rs per ton (1000 kg).
int amountForWeight({required double weightKg, required int ratePerTonMinorUnits}) {
  return (weightKg / 1000.0 * ratePerTonMinorUnits).round();
}

class MonthlySettlementRepository {
  MonthlySettlementRepository(
    this.db,
    this.ledger,
    this.weightEntries,
    this.vehicleKhata, [
    this.syncQueue,
  ]);

  final Database db;
  final LedgerRepository ledger;
  final WeightEntryRepository weightEntries;
  final VehicleKhataRepository vehicleKhata;
  final SyncQueueRepository? syncQueue;

  Future<MonthlySettlement?> findForMonth({
    required String businessId,
    required String companyUuid,
    required int year,
    required int month,
  }) async {
    final rows = await db.query(
      MonthlySettlement.tableName,
      where: 'business_id = ? AND company_uuid = ? AND year = ? AND month = ?',
      whereArgs: [businessId, companyUuid, year, month],
      limit: 1,
    );
    return rows.isEmpty ? null : MonthlySettlement.fromMap(rows.first);
  }

  Future<List<MonthlySettlement>> list({required String businessId}) async {
    final rows = await db.query(
      MonthlySettlement.tableName,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'year DESC, month DESC',
    );
    return rows.map(MonthlySettlement.fromMap).toList();
  }

  /// Month-end hisaab: sum kg × rate/ton → company khata + gari khata jama.
  Future<MonthlySettlement> settle({
    required String businessId,
    required String companyUuid,
    required int year,
    required int month,
    required int ratePerTonMinorUnits,
    required String createdBy,
    required String deviceId,
    String? companyName,
  }) async {
    if (ratePerTonMinorUnits <= 0) {
      throw ArgumentError('Rate per ton must be greater than zero');
    }

    final existing = await findForMonth(
      businessId: businessId,
      companyUuid: companyUuid,
      year: year,
      month: month,
    );
    if (existing != null) {
      throw StateError('Hisaab for this company is already done for $month/$year');
    }

    final entries = await weightEntries.listUnsettledForMonth(
      businessId: businessId,
      companyUuid: companyUuid,
      year: year,
      month: month,
    );
    if (entries.isEmpty) {
      throw StateError('No pending weight entries for this company in $month/$year');
    }

    final perVehicle = <String, int>{};
    var totalWeightKg = 0.0;
    var totalAmount = 0;
    final amounts = <String, int>{};
    for (final entry in entries) {
      final amount = amountForWeight(weightKg: entry.weightKg, ratePerTonMinorUnits: ratePerTonMinorUnits);
      amounts[entry.uuid] = amount;
      totalWeightKg += entry.weightKg;
      totalAmount += amount;
      perVehicle[entry.vehicleUuid] = (perVehicle[entry.vehicleUuid] ?? 0) + amount;
    }
    if (totalAmount <= 0) {
      throw StateError('Calculated amount is zero — check weight and rate');
    }

    final settlementDate = DateTime(year, month + 1, 0);
    final settlement = MonthlySettlement(
      uuid: _uuid.v4(),
      businessId: businessId,
      companyUuid: companyUuid,
      year: year,
      month: month,
      ratePerTonMinorUnits: ratePerTonMinorUnits,
      totalWeightKg: totalWeightKg,
      amountMinorUnits: totalAmount,
      date: settlementDate,
    );

    final monthLabel = '${month.toString().padLeft(2, '0')}/$year';
    final who = companyName ?? 'company';

    await db.transaction((txn) async {
      try {
        await txn.insert(MonthlySettlement.tableName, settlement.toMap());
      } on DatabaseException catch (e) {
        if (e.isUniqueConstraintError()) {
          throw StateError('Hisaab for this company is already done for $month/$year');
        }
        rethrow;
      }

      if (syncQueue != null) {
        await syncQueue!.enqueue(
          txn,
          businessId: businessId,
          entityType: 'MonthlySettlement',
          entityId: settlement.uuid,
          operation: SyncOperation.create,
        );
      }

      for (final entry in entries) {
        await weightEntries.applySettlementWithin(
          txn,
          uuid: entry.uuid,
          businessId: businessId,
          settlementUuid: settlement.uuid,
          amountMinorUnits: amounts[entry.uuid]!,
        );
      }

      for (final vehicle in perVehicle.entries) {
        if (vehicle.value <= 0) continue;
        await vehicleKhata.addSettlementJamaWithin(
          txn,
          businessId: businessId,
          vehicleUuid: vehicle.key,
          tafseel: '$who bill $monthLabel',
          amountMinorUnits: vehicle.value,
          date: settlementDate,
          settlementUuid: settlement.uuid,
        );
      }

      final creditLines = perVehicle.entries
          .where((e) => e.value > 0)
          .map(
            (e) => JournalLine(
              entryUuid: '',
              accountCode: '4020',
              debitMinorUnits: 0,
              creditMinorUnits: e.value,
              dimensionUuid: e.key,
            ),
          )
          .toList();

      await ledger.postWithin(
        txn,
        businessId: businessId,
        sourceType: 'MonthlySettlement',
        sourceId: settlement.uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        date: settlementDate,
        description: 'Month hisaab $monthLabel — $who',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: '1030',
            debitMinorUnits: totalAmount,
            creditMinorUnits: 0,
            partyUuid: companyUuid,
          ),
          ...creditLines,
        ],
      );
    });

    return settlement;
  }
}
