import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';

import '../accounting/journal_entry.dart';
import '../accounting/ledger_repository.dart';
import 'sync_queue_item.dart';
import 'sync_queue_repository.dart';

/// Drains [SyncQueueRepository]'s outbox by uploading JournalEntries to
/// Firestore — the upload half of the sync engine described in
/// PHASES.md Phase 5. No Cloud Functions (free Spark plan): atomic
/// document numbering uses a Firestore client-side `runTransaction`
/// against a counter document instead of a server-side function, and
/// there's no server-side balance re-validation (already enforced
/// client-side before anything reaches this far — see
/// `JournalEntry.isBalanced`/`LedgerRepository.postWithin`).
///
/// This is upload-only. Download/merge (pulling another device's
/// changes, real multi-device conflict detection) is the other half of
/// Phase 5, still pending — see PHASES.md.
class FirestoreSyncService {
  FirestoreSyncService({
    required this.db,
    required this.firestore,
    required this.syncQueue,
    required this.ledger,
  });

  final Database db;
  final FirebaseFirestore firestore;
  final SyncQueueRepository syncQueue;
  final LedgerRepository ledger;

  /// Uploads every pending/failed queue item for [businessId]. Returns
  /// the number of items successfully synced. Items that fail (offline,
  /// permission denied, etc.) are marked `failed` with the error and
  /// left for the next call to retry — see SyncQueueRepository.markFailed.
  Future<int> uploadPending(String businessId) async {
    final items = await syncQueue.pending(businessId: businessId);
    var succeeded = 0;

    for (final item in items) {
      if (item.entityType != 'JournalEntry') {
        // Only JournalEntry sync is wired up so far — master data
        // (Party, Product...) enqueuing is future work, same mechanical
        // pattern. Skip rather than fail so it doesn't loop forever.
        continue;
      }

      try {
        await _uploadJournalEntry(businessId, item);
        await syncQueue.markSynced(item.id);
        succeeded++;
      } catch (e) {
        await syncQueue.markFailed(item.id, e.toString());
      }
    }

    return succeeded;
  }

  Future<void> _uploadJournalEntry(String businessId, SyncQueueItem item) async {
    final entry = await ledger.findByUuid(item.entityId);
    if (entry == null) return; // nothing to upload — already gone locally

    var entryNumber = entry.entryNumber;
    if (entryNumber == 0 && item.operation == SyncOperation.create) {
      entryNumber = await _claimSequenceNumber(businessId, entry.sourceType);
      await db.update(
        JournalEntry.tableName,
        {'entry_number': entryNumber},
        where: 'uuid = ?',
        whereArgs: [entry.uuid],
      );
    }

    final docData = {
      'uuid': entry.uuid,
      'businessId': entry.businessId,
      'entryNumber': entryNumber,
      'date': entry.date.toIso8601String(),
      'sourceType': entry.sourceType,
      'sourceId': entry.sourceId,
      'description': entry.description,
      'status': entry.status.name,
      'reversalOfUuid': entry.reversalOfUuid,
      'createdBy': entry.createdBy,
      'createdAt': entry.createdAt.toIso8601String(),
      'deviceId': entry.deviceId,
      'lines': entry.lines
          .map((l) => {
                'accountCode': l.accountCode,
                'debitMinorUnits': l.debitMinorUnits,
                'creditMinorUnits': l.creditMinorUnits,
                'partyUuid': l.partyUuid,
                'dimensionUuid': l.dimensionUuid,
              })
          .toList(),
    };

    await firestore
        .collection('businesses')
        .doc(businessId)
        .collection('journalEntries')
        .doc(entry.uuid)
        .set(docData);
  }

  /// Atomic counter via a Firestore client-side transaction — the free-
  /// plan substitute for a Cloud Function issuing sequence numbers. See
  /// PHASES.md Section 14 ("gapless sequential invoice numbers") and the
  /// header note on this class.
  Future<int> _claimSequenceNumber(String businessId, String docType) {
    final ref = firestore
        .collection('businesses')
        .doc(businessId)
        .collection('numberSequences')
        .doc(docType);

    return firestore.runTransaction<int>((txn) async {
      final snapshot = await txn.get(ref);
      final next = ((snapshot.data()?['lastNumber'] as int?) ?? 0) + 1;
      txn.set(ref, {'lastNumber': next});
      return next;
    });
  }
}
