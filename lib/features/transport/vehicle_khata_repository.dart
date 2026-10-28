import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/accounting/journal_entry.dart';
import '../../core/accounting/ledger_repository.dart';
import '../../core/sync/sync_queue_item.dart';
import '../../core/sync/sync_queue_repository.dart';
import 'vehicle_khata_line.dart';

const _uuid = Uuid();

class VehicleKhataRepository {
  VehicleKhataRepository(this.db, this.ledger, [this.syncQueue]);

  final Database db;
  final LedgerRepository ledger;
  final SyncQueueRepository? syncQueue;

  Future<List<VehicleKhataRow>> statement(String vehicleUuid) async {
    final rows = await db.query(
      VehicleKhataLine.tableName,
      where: 'vehicle_uuid = ?',
      whereArgs: [vehicleUuid],
      orderBy: 'date ASC, uuid ASC',
    );
    final lines = rows.map(VehicleKhataLine.fromMap).toList();
    var running = 0;
    return [
      for (final line in lines)
        VehicleKhataRow(
          line: line,
          runningBalanceMinorUnits: running += line.jamaMinorUnits - line.kharchaMinorUnits,
        ),
    ];
  }

  Future<int> totalKharcha(String vehicleUuid) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(kharcha_minor_units), 0) AS total FROM ${VehicleKhataLine.tableName} '
      "WHERE vehicle_uuid = ? AND kind != 'opening'",
      [vehicleUuid],
    );
    return result.first['total'] as int;
  }

  Future<int> totalJama(String vehicleUuid) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(jama_minor_units), 0) AS total FROM ${VehicleKhataLine.tableName} '
      "WHERE vehicle_uuid = ? AND kind != 'opening'",
      [vehicleUuid],
    );
    return result.first['total'] as int;
  }

  Future<VehicleKhataLine> addKharcha({
    required String businessId,
    required String vehicleUuid,
    required String tafseel,
    required int amountMinorUnits,
    required String createdBy,
    required String deviceId,
    DateTime? date,
  }) {
    return _add(
      businessId: businessId,
      vehicleUuid: vehicleUuid,
      tafseel: tafseel,
      kind: VehicleKhataKind.kharcha,
      kharchaMinorUnits: amountMinorUnits,
      jamaMinorUnits: 0,
      createdBy: createdBy,
      deviceId: deviceId,
      date: date,
      postLedger: true,
    );
  }

  Future<VehicleKhataLine> addJama({
    required String businessId,
    required String vehicleUuid,
    required String tafseel,
    required int amountMinorUnits,
    required String createdBy,
    required String deviceId,
    DateTime? date,
  }) {
    return _add(
      businessId: businessId,
      vehicleUuid: vehicleUuid,
      tafseel: tafseel,
      kind: VehicleKhataKind.jama,
      kharchaMinorUnits: 0,
      jamaMinorUnits: amountMinorUnits,
      createdBy: createdBy,
      deviceId: deviceId,
      date: date,
      postLedger: true,
    );
  }

  Future<VehicleKhataLine> setOpening({
    required String businessId,
    required String vehicleUuid,
    required int amountMinorUnits,
    DateTime? date,
  }) async {
    final existing = await db.query(
      VehicleKhataLine.tableName,
      where: "vehicle_uuid = ? AND kind = 'opening'",
      whereArgs: [vehicleUuid],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw StateError('Opening balance already set for this vehicle');
    }
    return _add(
      businessId: businessId,
      vehicleUuid: vehicleUuid,
      tafseel: 'Pichla baqaya',
      kind: VehicleKhataKind.opening,
      kharchaMinorUnits: amountMinorUnits < 0 ? -amountMinorUnits : 0,
      jamaMinorUnits: amountMinorUnits > 0 ? amountMinorUnits : 0,
      createdBy: 'system',
      deviceId: 'system',
      date: date ?? DateTime(2000, 1, 1),
      postLedger: false,
    );
  }

  Future<VehicleKhataLine> addSettlementJamaWithin(
    Transaction txn, {
    required String businessId,
    required String vehicleUuid,
    required String tafseel,
    required int amountMinorUnits,
    required DateTime date,
    required String settlementUuid,
  }) async {
    final line = VehicleKhataLine(
      uuid: _uuid.v4(),
      businessId: businessId,
      vehicleUuid: vehicleUuid,
      date: DateTime(date.year, date.month, date.day),
      tafseel: tafseel,
      kind: VehicleKhataKind.jama,
      jamaMinorUnits: amountMinorUnits,
      sourceType: 'MonthlySettlement',
      sourceId: settlementUuid,
    );
    await txn.insert(VehicleKhataLine.tableName, line.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        txn,
        businessId: businessId,
        entityType: 'VehicleKhataLine',
        entityId: line.uuid,
        operation: SyncOperation.create,
      );
    }
    return line;
  }

  Future<VehicleKhataLine> _add({
    required String businessId,
    required String vehicleUuid,
    required String tafseel,
    required VehicleKhataKind kind,
    required int kharchaMinorUnits,
    required int jamaMinorUnits,
    required String createdBy,
    required String deviceId,
    DateTime? date,
    required bool postLedger,
  }) async {
    final text = tafseel.trim();
    if (text.isEmpty) {
      throw ArgumentError('Tafseel likhein');
    }
    if (kharchaMinorUnits < 0 || jamaMinorUnits < 0) {
      throw ArgumentError('Amount must be positive');
    }
    if (kind != VehicleKhataKind.opening && kharchaMinorUnits + jamaMinorUnits <= 0) {
      throw ArgumentError('Amount must be greater than zero');
    }

    final day = date ?? DateTime.now();
    final line = VehicleKhataLine(
      uuid: _uuid.v4(),
      businessId: businessId,
      vehicleUuid: vehicleUuid,
      date: DateTime(day.year, day.month, day.day),
      tafseel: text,
      kind: kind,
      kharchaMinorUnits: kharchaMinorUnits,
      jamaMinorUnits: jamaMinorUnits,
      sourceType: 'manual',
    );

    await db.transaction((txn) async {
      await txn.insert(VehicleKhataLine.tableName, line.toMap());
      if (syncQueue != null) {
        await syncQueue!.enqueue(
          txn,
          businessId: businessId,
          entityType: 'VehicleKhataLine',
          entityId: line.uuid,
          operation: SyncOperation.create,
        );
      }
      if (postLedger && kharchaMinorUnits > 0) {
        await ledger.postWithin(
          txn,
          businessId: businessId,
          sourceType: 'VehicleKhata',
          sourceId: line.uuid,
          createdBy: createdBy,
          deviceId: deviceId,
          date: line.date,
          description: text,
          rawLines: [
            JournalLine(
              entryUuid: '',
              accountCode: '5050',
              debitMinorUnits: kharchaMinorUnits,
              creditMinorUnits: 0,
              dimensionUuid: vehicleUuid,
            ),
            JournalLine(
              entryUuid: '',
              accountCode: '1010',
              debitMinorUnits: 0,
              creditMinorUnits: kharchaMinorUnits,
              dimensionUuid: vehicleUuid,
            ),
          ],
        );
      }
      if (postLedger && jamaMinorUnits > 0) {
        await ledger.postWithin(
          txn,
          businessId: businessId,
          sourceType: 'VehicleKhata',
          sourceId: line.uuid,
          createdBy: createdBy,
          deviceId: deviceId,
          date: line.date,
          description: text,
          rawLines: [
            JournalLine(
              entryUuid: '',
              accountCode: '1010',
              debitMinorUnits: jamaMinorUnits,
              creditMinorUnits: 0,
              dimensionUuid: vehicleUuid,
            ),
            JournalLine(
              entryUuid: '',
              accountCode: '4020',
              debitMinorUnits: 0,
              creditMinorUnits: jamaMinorUnits,
              dimensionUuid: vehicleUuid,
            ),
          ],
        );
      }
    });

    return line;
  }

  Future<VehicleKhataLine?> findByUuid(String uuid) async {
    final rows = await db.query(VehicleKhataLine.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : VehicleKhataLine.fromMap(rows.first);
  }

  /// Manual kharcha/jama only — month-hisaab jama cannot be edited here.
  Future<VehicleKhataLine> updateManual({
    required String uuid,
    required String tafseel,
    required int amountMinorUnits,
    required DateTime date,
    required String createdBy,
    required String deviceId,
  }) async {
    final existing = await findByUuid(uuid);
    if (existing == null) throw StateError('Entry not found');
    if (existing.sourceType == 'MonthlySettlement') {
      throw StateError('Month hisaab ki entry yahan change nahi hoti');
    }
    if (existing.kind == VehicleKhataKind.opening) {
      throw StateError('Opening change ke liye pehle delete karke dobara set karein');
    }
    if (amountMinorUnits <= 0) throw ArgumentError('Amount must be greater than zero');
    final text = tafseel.trim();
    if (text.isEmpty) throw ArgumentError('Tafseel likhein');

    final isKharcha = existing.kind == VehicleKhataKind.kharcha;
    final updated = VehicleKhataLine(
      uuid: existing.uuid,
      businessId: existing.businessId,
      vehicleUuid: existing.vehicleUuid,
      date: DateTime(date.year, date.month, date.day),
      tafseel: text,
      kind: existing.kind,
      kharchaMinorUnits: isKharcha ? amountMinorUnits : 0,
      jamaMinorUnits: isKharcha ? 0 : amountMinorUnits,
      sourceType: existing.sourceType,
      sourceId: existing.sourceId,
    );

    final oldEntry = await ledger.findBySource(sourceType: 'VehicleKhata', sourceId: uuid);
    if (oldEntry != null) {
      await ledger.void_(oldEntry, voidedBy: createdBy, reason: 'Khata entry edit');
    }

    await db.update(VehicleKhataLine.tableName, updated.toMap(), where: 'uuid = ?', whereArgs: [uuid]);
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: existing.businessId,
        entityType: 'VehicleKhataLine',
        entityId: uuid,
        operation: SyncOperation.update,
      );
    }

    if (isKharcha) {
      await ledger.post(
        businessId: existing.businessId,
        sourceType: 'VehicleKhata',
        sourceId: uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        date: updated.date,
        description: text,
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: '5050',
            debitMinorUnits: amountMinorUnits,
            creditMinorUnits: 0,
            dimensionUuid: existing.vehicleUuid,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: '1010',
            debitMinorUnits: 0,
            creditMinorUnits: amountMinorUnits,
            dimensionUuid: existing.vehicleUuid,
          ),
        ],
      );
    } else {
      await ledger.post(
        businessId: existing.businessId,
        sourceType: 'VehicleKhata',
        sourceId: uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        date: updated.date,
        description: text,
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: '1010',
            debitMinorUnits: amountMinorUnits,
            creditMinorUnits: 0,
            dimensionUuid: existing.vehicleUuid,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: '4020',
            debitMinorUnits: 0,
            creditMinorUnits: amountMinorUnits,
            dimensionUuid: existing.vehicleUuid,
          ),
        ],
      );
    }
    return updated;
  }

  Future<void> deleteManual({
    required String uuid,
    required String deletedBy,
  }) async {
    final existing = await findByUuid(uuid);
    if (existing == null) return;
    if (existing.sourceType == 'MonthlySettlement') {
      throw StateError('Month hisaab ki entry delete nahi hoti');
    }

    final entry = await ledger.findBySource(sourceType: 'VehicleKhata', sourceId: uuid);
    if (entry != null) {
      await ledger.void_(entry, voidedBy: deletedBy, reason: 'Khata entry delete');
    }

    await db.delete(VehicleKhataLine.tableName, where: 'uuid = ?', whereArgs: [uuid]);
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: existing.businessId,
        entityType: 'VehicleKhataLine',
        entityId: uuid,
        operation: SyncOperation.delete,
      );
    }
  }
}
