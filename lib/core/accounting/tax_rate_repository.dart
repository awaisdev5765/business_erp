import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../sync/sync_queue_item.dart';
import '../sync/sync_queue_repository.dart';
import 'tax_rate.dart';

const _uuid = Uuid();

class TaxRateRepository {
  TaxRateRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<TaxRate> create({
    required String businessId,
    required String name,
    required double ratePercent,
  }) async {
    final rate = TaxRate(uuid: _uuid.v4(), businessId: businessId, name: name, ratePercent: ratePercent);
    await db.insert(TaxRate.tableName, rate.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'TaxRate',
        entityId: rate.uuid,
        operation: SyncOperation.create,
      );
    }
    return rate;
  }

  Future<List<TaxRate>> list({required String businessId, bool activeOnly = true}) async {
    final rows = await db.query(
      TaxRate.tableName,
      where: activeOnly ? 'business_id = ? AND is_active = 1' : 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'rate_percent ASC',
    );
    return rows.map(TaxRate.fromMap).toList();
  }
}
