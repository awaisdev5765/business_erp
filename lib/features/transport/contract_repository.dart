import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/sync/sync_queue_item.dart';
import '../../core/sync/sync_queue_repository.dart';
import 'contract.dart';

const _uuid = Uuid();

class ContractRepository {
  ContractRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<Contract> create({
    required String businessId,
    required String customerUuid,
    required String description,
    int? ratePerTripMinorUnits,
    int? ratePerTonMinorUnits,
    DateTime? startDate,
  }) async {
    final contract = Contract(
      uuid: _uuid.v4(),
      businessId: businessId,
      customerUuid: customerUuid,
      description: description,
      ratePerTripMinorUnits: ratePerTripMinorUnits,
      ratePerTonMinorUnits: ratePerTonMinorUnits,
      startDate: startDate ?? DateTime.now(),
    );
    await db.insert(Contract.tableName, contract.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'Contract',
        entityId: contract.uuid,
        operation: SyncOperation.create,
      );
    }
    return contract;
  }

  Future<List<Contract>> list({required String businessId}) async {
    final rows = await db.query(
      Contract.tableName,
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'start_date DESC',
    );
    return rows.map(Contract.fromMap).toList();
  }

  Future<Contract?> findByUuid(String uuid) async {
    final rows = await db.query(Contract.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : Contract.fromMap(rows.first);
  }

  Future<Contract?> findForCustomer({required String businessId, required String customerUuid}) async {
    final rows = await db.query(
      Contract.tableName,
      where: 'business_id = ? AND customer_uuid = ? AND is_active = 1',
      whereArgs: [businessId, customerUuid],
      orderBy: 'start_date DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Contract.fromMap(rows.first);
  }
}
