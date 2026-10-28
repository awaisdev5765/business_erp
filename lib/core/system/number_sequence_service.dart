import 'package:sqflite/sqflite.dart';

import 'number_sequence.dart';

/// Document types whose numbering this service issues.
enum DocType { sale, purchase, paymentIn, paymentOut, refund }

/// Atomically issues the next sequential number for a (business, docType,
/// year) triple, formatted as "TYPE-YEAR-000042" (e.g. "SALE-2026-000042")
/// — the counter resets to 1 every new year, the standard invoice-
/// numbering convention. [date] defaults to now and decides which year's
/// counter is incremented; pass it explicitly for a backdated document so
/// it numbers into the right year's sequence rather than today's.
class NumberSequenceService {
  NumberSequenceService(this.db);

  final Database db;

  Future<String> next({
    required String businessId,
    required DocType docType,
    DateTime? date,
  }) async {
    final year = (date ?? DateTime.now()).year;

    return db.transaction((txn) async {
      final rows = await txn.query(
        NumberSequence.tableName,
        where: 'business_id = ? AND doc_type = ? AND year = ?',
        whereArgs: [businessId, docType.name, year],
        limit: 1,
      );

      final nextNumber = (rows.isEmpty ? 0 : rows.first['last_number'] as int) + 1;

      if (rows.isEmpty) {
        await txn.insert(NumberSequence.tableName, {
          'business_id': businessId,
          'doc_type': docType.name,
          'year': year,
          'last_number': nextNumber,
        });
      } else {
        await txn.update(
          NumberSequence.tableName,
          {'last_number': nextNumber},
          where: 'business_id = ? AND doc_type = ? AND year = ?',
          whereArgs: [businessId, docType.name, year],
        );
      }

      final prefix = docType.name.toUpperCase();
      return '$prefix-$year-${nextNumber.toString().padLeft(6, '0')}';
    });
  }

  /// Fixes the gap a naive restore would otherwise leave: `next()`'s
  /// counter (`number_sequences.last_number`) lives only in local SQLite
  /// and was never itself synced to Firestore, so after
  /// FirestoreSyncService.restoreFromCloud() repopulates `sales`/
  /// `purchases`/`refunds`/`payments` but not their counters, the very
  /// next document created on the restored device would start back at
  /// `SALE-2026-000001` — a number that already exists. Rather than
  /// syncing the raw counter (which risks two devices' counters
  /// disagreeing about what the *actual* high-water mark is), this
  /// recomputes it from the one source of truth that's unambiguous: the
  /// document numbers already issued, all of them now present locally
  /// after the rest of the restore. Only ever raises `last_number`
  /// (never lowers it), so calling this when nothing was actually lost
  /// is always a safe no-op.
  Future<void> resyncFromIssuedNumbers(String businessId) async {
    final issuedNumbers = <String>[
      ...await _documentNumbersFor('sales', businessId),
      ...await _documentNumbersFor('purchases', businessId),
      ...await _documentNumbersFor('refunds', businessId),
      ...await _documentNumbersFor('payments', businessId),
    ];

    // (docType, year) -> highest number actually issued.
    final highWaterMarks = <(DocType, int), int>{};
    final pattern = RegExp(r'^([A-Z]+)-(\d{4})-(\d+)$');
    for (final documentNumber in issuedNumbers) {
      final match = pattern.firstMatch(documentNumber);
      if (match == null) continue;
      final prefix = match.group(1)!;
      final year = int.parse(match.group(2)!);
      final number = int.parse(match.group(3)!);

      DocType? docType;
      for (final candidate in DocType.values) {
        if (candidate.name.toUpperCase() == prefix) {
          docType = candidate;
          break;
        }
      }
      if (docType == null) continue;

      final key = (docType, year);
      if ((highWaterMarks[key] ?? 0) < number) {
        highWaterMarks[key] = number;
      }
    }

    await db.transaction((txn) async {
      for (final entry in highWaterMarks.entries) {
        final (docType, year) = entry.key;
        final issuedMax = entry.value;

        final rows = await txn.query(
          NumberSequence.tableName,
          where: 'business_id = ? AND doc_type = ? AND year = ?',
          whereArgs: [businessId, docType.name, year],
          limit: 1,
        );
        final currentLast = rows.isEmpty ? 0 : rows.first['last_number'] as int;
        if (issuedMax <= currentLast) continue; // already at least this high — don't lower it

        if (rows.isEmpty) {
          await txn.insert(NumberSequence.tableName, {
            'business_id': businessId,
            'doc_type': docType.name,
            'year': year,
            'last_number': issuedMax,
          });
        } else {
          await txn.update(
            NumberSequence.tableName,
            {'last_number': issuedMax},
            where: 'business_id = ? AND doc_type = ? AND year = ?',
            whereArgs: [businessId, docType.name, year],
          );
        }
      }
    });
  }

  Future<List<String>> _documentNumbersFor(String table, String businessId) async {
    final rows = await db.query(table, columns: ['document_number'], where: 'business_id = ?', whereArgs: [businessId]);
    return rows.map((r) => r['document_number'] as String).toList();
  }
}
