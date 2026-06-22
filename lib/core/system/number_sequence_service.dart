import 'package:sqflite/sqflite.dart';

import 'number_sequence.dart';

/// Document types whose numbering this service issues.
enum DocType { sale, purchase, paymentIn, paymentOut }

/// Atomically issues the next sequential number for a (business, docType)
/// pair, formatted with a fixed-width zero-padded counter, e.g.
/// "LOCAL-SALE-000042". See [NumberSequence] for why the prefix exists.
class NumberSequenceService {
  NumberSequenceService(this.db);

  final Database db;

  Future<String> next({
    required String businessId,
    required DocType docType,
  }) async {
    return db.transaction((txn) async {
      final rows = await txn.query(
        NumberSequence.tableName,
        where: 'business_id = ? AND doc_type = ?',
        whereArgs: [businessId, docType.name],
        limit: 1,
      );

      final nextNumber = (rows.isEmpty ? 0 : rows.first['last_number'] as int) + 1;

      if (rows.isEmpty) {
        await txn.insert(NumberSequence.tableName, {
          'business_id': businessId,
          'doc_type': docType.name,
          'last_number': nextNumber,
        });
      } else {
        await txn.update(
          NumberSequence.tableName,
          {'last_number': nextNumber},
          where: 'business_id = ? AND doc_type = ?',
          whereArgs: [businessId, docType.name],
        );
      }

      final prefix = docType.name.toUpperCase();
      return 'LOCAL-$prefix-${nextNumber.toString().padLeft(6, '0')}';
    });
  }
}
