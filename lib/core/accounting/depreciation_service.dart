import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'fixed_asset.dart';
import 'fixed_asset_repository.dart';
import 'journal_entry.dart';
import 'ledger_repository.dart';

const _uuid = Uuid();

/// Posts one month of straight-line depreciation for a [FixedAsset]:
/// Dr Depreciation Expense(5090) / Cr Accumulated Depreciation(1060),
/// tagged with the linked OperatingAsset (if any) as the journal line's
/// dimension — same pattern as TripExpense/Boat-Vehicle Ledger. See
/// PHASES.md Section 6/12 and Phase 6.
class DepreciationService {
  DepreciationService(this.db, this.assets, this.ledger);

  final Database db;
  final FixedAssetRepository assets;
  final LedgerRepository ledger;

  /// [period] is "YYYY-MM". Throws if this asset already has an entry
  /// for that period (the table's unique constraint catches it, but we
  /// check first for a clearer error) or if it's already fully
  /// depreciated.
  Future<DepreciationEntry> postMonthlyDepreciation({
    required String fixedAssetUuid,
    required String period,
    required String createdBy,
    required String deviceId,
  }) async {
    final asset = await assets.findByUuid(fixedAssetUuid);
    if (asset == null) {
      throw StateError('FixedAsset $fixedAssetUuid not found');
    }

    final history = await assets.depreciationHistory(fixedAssetUuid);
    if (history.any((e) => e.period == period)) {
      throw StateError('Depreciation for $period already posted for this asset');
    }

    final accumulated = history.fold<int>(0, (sum, e) => sum + e.amountMinorUnits);
    final depreciableBase = asset.acquisitionCostMinorUnits - asset.salvageValueMinorUnits;
    final remaining = depreciableBase - accumulated;
    if (remaining <= 0) {
      throw StateError('Asset is already fully depreciated');
    }

    // This is the *scheduled* last month (the usefulLifeMonths-th entry)
    // when remaining <= monthly isn't enough on its own to detect it —
    // e.g. 100/3 = 33/month leaves 34 due on month 3, which is *more*
    // than one month's amount. Checking the entry count against
    // usefulLifeMonths is what correctly identifies "this is the last
    // scheduled month," so it absorbs the full remainder rather than
    // leaving a few cents for a phantom extra month.
    final isLastScheduledMonth = history.length + 1 >= asset.usefulLifeMonths;
    final amount = isLastScheduledMonth
        ? remaining
        : (remaining < asset.monthlyDepreciationMinorUnits ? remaining : asset.monthlyDepreciationMinorUnits);

    final entry = DepreciationEntry(
      uuid: _uuid.v4(),
      fixedAssetUuid: fixedAssetUuid,
      businessId: asset.businessId,
      period: period,
      amountMinorUnits: amount,
      postedAt: DateTime.now(),
    );

    await db.transaction((txn) async {
      await txn.insert(DepreciationEntry.tableName, entry.toMap());

      await ledger.postWithin(
        txn,
        businessId: asset.businessId,
        sourceType: 'Depreciation',
        sourceId: entry.uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        description: '${asset.name} depreciation $period',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: '5090', // Depreciation Expense
            debitMinorUnits: amount,
            creditMinorUnits: 0,
            dimensionUuid: asset.operatingAssetUuid,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: '1060', // Accumulated Depreciation
            debitMinorUnits: 0,
            creditMinorUnits: amount,
            dimensionUuid: asset.operatingAssetUuid,
          ),
        ],
      );
    });

    return entry;
  }
}
