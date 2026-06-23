import 'package:sqflite/sqflite.dart';

import 'approval_threshold.dart';

class ApprovalThresholdRepository {
  ApprovalThresholdRepository(this.db);

  final Database db;

  Future<void> setThreshold({
    required String businessId,
    required String transactionType,
    required int thresholdMinorUnits,
  }) async {
    final threshold = ApprovalThreshold(
      businessId: businessId,
      transactionType: transactionType,
      thresholdMinorUnits: thresholdMinorUnits,
    );
    await db.insert(
      ApprovalThreshold.tableName,
      threshold.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearThreshold({required String businessId, required String transactionType}) async {
    await db.delete(
      ApprovalThreshold.tableName,
      where: 'business_id = ? AND transaction_type = ?',
      whereArgs: [businessId, transactionType],
    );
  }

  /// Null means no threshold configured — the caller should treat that
  /// as "no approval required," not "require approval for everything."
  Future<int?> thresholdFor({required String businessId, required String transactionType}) async {
    final rows = await db.query(
      ApprovalThreshold.tableName,
      where: 'business_id = ? AND transaction_type = ?',
      whereArgs: [businessId, transactionType],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ApprovalThreshold.fromMap(rows.first).thresholdMinorUnits;
  }

  Future<List<ApprovalThreshold>> list({required String businessId}) async {
    final rows = await db.query(ApprovalThreshold.tableName, where: 'business_id = ?', whereArgs: [businessId]);
    return rows.map(ApprovalThreshold.fromMap).toList();
  }
}
