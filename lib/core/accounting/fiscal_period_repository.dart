import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../sync/sync_queue_item.dart';
import '../sync/sync_queue_repository.dart';
import 'fiscal_period.dart';

const _uuid = Uuid();

class FiscalPeriodRepository {
  FiscalPeriodRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<FiscalPeriod> create({
    required String businessId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final period = FiscalPeriod(
      uuid: _uuid.v4(),
      businessId: businessId,
      startDate: startDate,
      endDate: endDate,
      status: FiscalPeriodStatus.open,
    );
    await db.insert(FiscalPeriod.tableName, period.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'FiscalPeriod',
        entityId: period.uuid,
        operation: SyncOperation.create,
      );
    }
    return period;
  }

  Future<List<FiscalPeriod>> list({required String businessId}) async {
    final rows = await db.query(
      FiscalPeriod.tableName,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'start_date DESC',
    );
    return rows.map(FiscalPeriod.fromMap).toList();
  }

  Future<void> setStatus(String uuid, FiscalPeriodStatus status) async {
    await db.update(
      FiscalPeriod.tableName,
      {'status': status.name},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  /// Throws if [date] falls inside a Closed or Locked period for
  /// [businessId]. A date with no period defined at all is allowed —
  /// fiscal periods are opt-in; a business that hasn't set any up yet
  /// posts freely, same as Phase 0/1 behavior. Runs against [exec] so it
  /// participates in the caller's transaction (see LedgerRepository).
  Future<void> assertOpenForPosting(
    DatabaseExecutor exec, {
    required String businessId,
    required DateTime date,
  }) async {
    final dateIso = date.toIso8601String();
    final rows = await exec.query(
      FiscalPeriod.tableName,
      where: 'business_id = ? AND start_date <= ? AND end_date >= ?',
      whereArgs: [businessId, dateIso, dateIso],
      limit: 1,
    );
    if (rows.isEmpty) return; // no period configured for this date — allow

    final period = FiscalPeriod.fromMap(rows.first);
    if (period.status != FiscalPeriodStatus.open) {
      throw StateError(
        'Cannot post to ${date.toIso8601String().split('T').first}: '
        'fiscal period is ${period.status.name}. Use a reversing entry dated in the current open period instead.',
      );
    }
  }
}
