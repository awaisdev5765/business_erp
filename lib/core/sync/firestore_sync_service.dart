import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/spare_parts/inventory/product.dart';
import '../accounting/journal_entry.dart';
import '../accounting/ledger_repository.dart';
import '../party/party.dart';
import 'conflict_record_repository.dart';
import 'sync_queue_item.dart';
import 'sync_queue_repository.dart';

class DownloadResult {
  DownloadResult({required this.inserted, required this.statusUpdated, required this.conflicts});
  final int inserted;
  final int statusUpdated;
  final int conflicts;
}

/// The sync engine described in PHASES.md Phase 5. No Cloud Functions
/// (free Spark plan): atomic document numbering uses a Firestore
/// client-side `runTransaction` against a counter document instead of a
/// server-side function, and there's no server-side balance
/// re-validation (already enforced client-side before anything reaches
/// this far — see `JournalEntry.isBalanced`/`LedgerRepository.postWithin`).
///
/// [uploadPending] is the local-to-remote half; [downloadAndMerge] is
/// remote-to-local. JournalEntry lines are immutable once posted (see
/// PHASES.md Section 11 — "Reversal, not edit"), so the only thing that
/// can actually disagree between two devices' copies of the same entry is
/// its `status` (posted/reversed/void_). That makes merge conflicts much
/// narrower than the general case: see [downloadAndMerge]'s status-merge
/// logic.
class FirestoreSyncService {
  FirestoreSyncService({
    required this.db,
    required this.firestore,
    required this.syncQueue,
    required this.ledger,
    required this.conflictRecords,
  });

  final Database db;
  final FirebaseFirestore firestore;
  final SyncQueueRepository syncQueue;
  final LedgerRepository ledger;
  final ConflictRecordRepository conflictRecords;

  /// Upload then download — the one call both the manual "Sync Now"
  /// button and any periodic/foreground trigger should use, so both
  /// directions always run together rather than callers having to
  /// remember to call both.
  Future<DownloadResult> syncAll(String businessId) async {
    await uploadPending(businessId);
    return downloadAndMerge(businessId);
  }

  /// Uploads every pending/failed queue item for [businessId]. Returns
  /// the number of items successfully synced. Items that fail (offline,
  /// permission denied, etc.) are marked `failed` with the error and
  /// left for the next call to retry — see SyncQueueRepository.markFailed.
  Future<int> uploadPending(String businessId) async {
    final items = await syncQueue.pending(businessId: businessId);
    var succeeded = 0;

    for (final item in items) {
      try {
        switch (item.entityType) {
          case 'JournalEntry':
            await _uploadJournalEntry(businessId, item);
            break;
          case 'Party':
            await _uploadParty(businessId, item);
            break;
          case 'Product':
            await _uploadProduct(businessId, item);
            break;
          default:
            // Other entity types aren't wired up yet — same mechanical
            // pattern as Party/Product, just not applied everywhere.
            // Skip rather than fail so it doesn't loop forever.
            continue;
        }
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

  Future<void> _uploadParty(String businessId, SyncQueueItem item) async {
    final rows = await db.query(Party.tableName, where: 'uuid = ?', whereArgs: [item.entityId], limit: 1);
    if (rows.isEmpty) return; // gone locally — nothing to upload
    final party = Party.fromMap(rows.first);

    await firestore.collection('businesses').doc(businessId).collection('parties').doc(party.uuid).set({
      'uuid': party.uuid,
      'businessId': party.businessId,
      'type': party.type.name,
      'name': party.name,
      'phone': party.phone,
      'address': party.address,
      'creditLimitMinorUnits': party.creditLimitMinorUnits,
      'isActive': party.isActive,
      'updatedAt': party.updatedAt.toIso8601String(),
    });
  }

  /// Note: only `ProductRepository.create()` enqueues a sync item — every
  /// Sale/Purchase that adjusts `stockQuantity` afterward doesn't, so the
  /// synced `stockQuantity` reflects the product's state at creation, not
  /// live stock. Re-enqueueing on every stock movement is the same
  /// mechanical extension as everywhere else in this phase, just not
  /// applied yet — flagging here so the gap is visible, not silently stale.
  Future<void> _uploadProduct(String businessId, SyncQueueItem item) async {
    final rows = await db.query(Product.tableName, where: 'uuid = ?', whereArgs: [item.entityId], limit: 1);
    if (rows.isEmpty) return;
    final product = Product.fromMap(rows.first);

    await firestore.collection('businesses').doc(businessId).collection('products').doc(product.uuid).set({
      'uuid': product.uuid,
      'businessId': product.businessId,
      'sku': product.sku,
      'name': product.name,
      'costPriceMinorUnits': product.costPriceMinorUnits,
      'salePriceMinorUnits': product.salePriceMinorUnits,
      'taxRatePercent': product.taxRatePercent,
      'stockQuantity': product.stockQuantity,
      'reorderLevel': product.reorderLevel,
      'isActive': product.isActive,
      'updatedAt': product.updatedAt.toIso8601String(),
    });
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

  /// **Scope note:** this only syncs the ledger (JournalEntry + lines),
  /// the same scope as [uploadPending]. It does *not* pull the domain
  /// records that caused those entries (a remote Sale, its
  /// StockMovement, the resulting Product.stockQuantity change) — those
  /// still need their own sync wiring (see PHASES.md Phase 5 "Sync for
  /// entities other than JournalEntry"). Downloading a remote device's
  /// Sale today merges its accounting effect (balances, P&L, ledgers all
  /// read live off journal_lines) but not its inventory effect locally.
  ///
  /// Pulls every JournalEntry for [businessId] from Firestore and merges
  /// it into local SQL:
  /// - Not present locally (another device created it) -> insert it and
  ///   its lines.
  /// - Present with the same status -> nothing to do.
  /// - Present locally as `posted` but remote is `reversed`/`void_` ->
  ///   we haven't independently transitioned it, so it's safe to just
  ///   adopt the remote status.
  /// - Present locally as `reversed`/`void_` while remote is still
  ///   `posted` -> our transition hasn't reached the server yet; the next
  ///   [uploadPending] call will push it. Nothing to do here.
  /// - Present locally as one terminal status while remote independently
  ///   became a *different* terminal status (e.g. local voided it, a
  ///   second device reversed it) -> a genuine conflict. Recorded via
  ///   [ConflictRecordRepository] for manual resolution; local is left
  ///   untouched rather than guessing which side is "right."
  ///
  /// Fetches the whole collection every call rather than tracking a
  /// cursor — fine at today's scale, a rollup-style optimization for
  /// later if a business's journalEntries collection gets large (see
  /// PHASES.md Section 12's rollup-table note, same idea applied here).
  Future<DownloadResult> downloadAndMerge(String businessId) async {
    final snapshot = await firestore.collection('businesses').doc(businessId).collection('journalEntries').get();

    var inserted = 0;
    var statusUpdated = 0;
    var conflicts = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final uuid = data['uuid'] as String;
      final remoteStatus = data['status'] as String;

      final localRows = await db.query(JournalEntry.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);

      if (localRows.isEmpty) {
        await _insertRemoteEntry(data);
        inserted++;
        continue;
      }

      final localStatus = localRows.first['status'] as String;
      if (localStatus == remoteStatus) continue;

      if (localStatus == JournalEntryStatus.posted.name) {
        await db.update(JournalEntry.tableName, {'status': remoteStatus}, where: 'uuid = ?', whereArgs: [uuid]);
        statusUpdated++;
      } else if (remoteStatus != JournalEntryStatus.posted.name) {
        await conflictRecords.record(
          businessId: businessId,
          entityType: 'JournalEntry',
          entityId: uuid,
          conflictingFields: ['status'],
        );
        conflicts++;
      }
      // else: remoteStatus == posted but local already transitioned —
      // our transition just hasn't uploaded yet.
    }

    return DownloadResult(inserted: inserted, statusUpdated: statusUpdated, conflicts: conflicts);
  }

  Future<void> _insertRemoteEntry(Map<String, Object?> data) async {
    final uuid = data['uuid'] as String;

    await db.transaction((txn) async {
      await txn.insert(
        JournalEntry.tableName,
        {
          'uuid': uuid,
          'business_id': data['businessId'],
          'entry_number': data['entryNumber'],
          'date': data['date'],
          'source_type': data['sourceType'],
          'source_id': data['sourceId'],
          'description': data['description'],
          'status': data['status'],
          'reversal_of_uuid': data['reversalOfUuid'],
          'created_by': data['createdBy'],
          'created_at': data['createdAt'],
          'device_id': data['deviceId'],
          'sync_status': SyncStatus.synced.name,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      final lines = (data['lines'] as List?) ?? [];
      for (final rawLine in lines) {
        final line = rawLine as Map<Object?, Object?>;
        await txn.insert(
          JournalLine.tableName,
          {
            'entry_uuid': uuid,
            'account_code': line['accountCode'],
            'debit_minor_units': line['debitMinorUnits'],
            'credit_minor_units': line['creditMinorUnits'],
            'party_uuid': line['partyUuid'],
            'dimension_uuid': line['dimensionUuid'],
          },
        );
      }
    });
  }
}
