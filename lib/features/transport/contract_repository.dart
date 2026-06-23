import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'contract.dart';

const _uuid = Uuid();

class ContractRepository {
  ContractRepository(this.db);

  final Database db;

  Future<Contract> create({
    required String businessId,
    required String customerUuid,
    required String description,
    int? ratePerTripMinorUnits,
    DateTime? startDate,
  }) async {
    final contract = Contract(
      uuid: _uuid.v4(),
      businessId: businessId,
      customerUuid: customerUuid,
      description: description,
      ratePerTripMinorUnits: ratePerTripMinorUnits,
      startDate: startDate ?? DateTime.now(),
    );
    await db.insert(Contract.tableName, contract.toMap());
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
}
