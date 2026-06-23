import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/sync/conflict_record.dart';
import 'package:business_erp/core/sync/conflict_record_repository.dart';
import 'package:business_erp/core/sync/conflict_resolution_policy.dart';
import 'package:business_erp/core/system/database.dart';

void main() {
  group('ConflictResolutionPolicy (pure logic, no database)', () {
    final policy = ConflictResolutionPolicy(sensitiveFields: {'creditLimitMinorUnits', 'taxRatePercent'});

    test('identical records produce no conflict', () {
      final decision = policy.resolve(
        localFields: {'name': 'Acme', 'phone': '555-1234'},
        localUpdatedAt: DateTime(2026, 1, 1),
        remoteFields: {'name': 'Acme', 'phone': '555-1234'},
        remoteUpdatedAt: DateTime(2026, 1, 2),
      );
      expect(decision.outcome, ConflictOutcome.autoResolvedLocal);
    });

    test('non-sensitive field differences auto-resolve to the newer side (remote newer)', () {
      final decision = policy.resolve(
        localFields: {'name': 'Acme', 'phone': '555-1234'},
        localUpdatedAt: DateTime(2026, 1, 1),
        remoteFields: {'name': 'Acme', 'phone': '555-9999'},
        remoteUpdatedAt: DateTime(2026, 1, 5),
      );
      expect(decision.outcome, ConflictOutcome.autoResolvedRemote);
      expect(decision.resolvedFields['phone'], '555-9999');
    });

    test('non-sensitive field differences auto-resolve to the newer side (local newer)', () {
      final decision = policy.resolve(
        localFields: {'name': 'Acme', 'phone': '555-9999'},
        localUpdatedAt: DateTime(2026, 1, 10),
        remoteFields: {'name': 'Acme', 'phone': '555-1234'},
        remoteUpdatedAt: DateTime(2026, 1, 5),
      );
      expect(decision.outcome, ConflictOutcome.autoResolvedLocal);
      expect(decision.resolvedFields['phone'], '555-9999');
    });

    test('a sensitive field difference always needs manual resolution, even if one side is clearly newer', () {
      final decision = policy.resolve(
        localFields: {'name': 'Acme', 'creditLimitMinorUnits': 500000},
        localUpdatedAt: DateTime(2026, 1, 1),
        remoteFields: {'name': 'Acme', 'creditLimitMinorUnits': 250000},
        remoteUpdatedAt: DateTime(2026, 1, 30), // remote is much newer...
      );
      // ...but it's still flagged, not auto-applied, because the field is sensitive.
      expect(decision.outcome, ConflictOutcome.needsManualResolution);
      expect(decision.conflictingSensitiveFields, contains('creditLimitMinorUnits'));
    });

    test('mixed conflict (one sensitive + one non-sensitive field differ) still requires manual resolution', () {
      final decision = policy.resolve(
        localFields: {'phone': '555-1234', 'taxRatePercent': 10.0},
        localUpdatedAt: DateTime(2026, 1, 1),
        remoteFields: {'phone': '555-9999', 'taxRatePercent': 15.0},
        remoteUpdatedAt: DateTime(2026, 1, 2),
      );
      expect(decision.outcome, ConflictOutcome.needsManualResolution);
      expect(decision.conflictingSensitiveFields, ['taxRatePercent']);
    });
  });

  group('ConflictRecordRepository (persistence)', () {
    late Database db;
    late Directory tempDir;
    late ConflictRecordRepository repo;
    const businessId = 'business-1';

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sqlite_test_');
      db = await databaseFactory.openDatabase(
        '${tempDir.path}/test.db',
        options: OpenDatabaseOptions(version: 1, onCreate: (db, version) => createSchema(db)),
      );
      repo = ConflictRecordRepository(db);
    });

    tearDown(() async {
      await db.close();
      await tempDir.delete(recursive: true);
    });

    test('a recorded conflict appears in unresolved() until resolved', () async {
      final record = await repo.record(
        businessId: businessId,
        entityType: 'Party',
        entityId: 'party-1',
        conflictingFields: ['creditLimitMinorUnits'],
      );

      final unresolved = await repo.unresolved(businessId: businessId);
      expect(unresolved.length, 1);
      expect(unresolved.first.id, record.id);

      await repo.resolve(record.id, ConflictRecordStatus.resolvedLocal);
      final afterResolve = await repo.unresolved(businessId: businessId);
      expect(afterResolve, isEmpty);
    });

    test('resolve() rejects resolving back to unresolved', () async {
      final record = await repo.record(
        businessId: businessId,
        entityType: 'Party',
        entityId: 'party-1',
        conflictingFields: ['taxRatePercent'],
      );

      expect(
        () => repo.resolve(record.id, ConflictRecordStatus.unresolved),
        throwsArgumentError,
      );
    });
  });
}
