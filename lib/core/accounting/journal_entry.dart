enum JournalEntryStatus { posted, reversed, void_ }

enum SyncStatus { pending, syncing, synced, conflict, failed }

/// One line of a [JournalEntry], stored in its own table (journal_lines)
/// keyed by entry_uuid. Money is stored in integer minor units (cents) —
/// never as REAL/double — to avoid rounding drift across 100k+ rows.
class JournalLine {
  JournalLine({
    required this.entryUuid,
    required this.accountCode,
    required this.debitMinorUnits,
    required this.creditMinorUnits,
    this.partyUuid,
    this.dimensionUuid,
  });

  final String entryUuid;
  final String accountCode;
  final int debitMinorUnits;
  final int creditMinorUnits;

  /// Customer/Supplier/Driver/Captain uuid — lets sub-ledgers (Customer
  /// Ledger, Boat Ledger, etc.) be a filtered SQL view over this one table
  /// instead of separate physical tables. See PHASES.md Section 11.
  final String? partyUuid;

  /// Vehicle/Boat/Warehouse uuid — secondary dimension for reporting.
  final String? dimensionUuid;

  static const tableName = 'journal_lines';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_uuid TEXT NOT NULL,
      account_code TEXT NOT NULL,
      debit_minor_units INTEGER NOT NULL DEFAULT 0,
      credit_minor_units INTEGER NOT NULL DEFAULT 0,
      party_uuid TEXT,
      dimension_uuid TEXT,
      FOREIGN KEY (entry_uuid) REFERENCES ${_journalEntryTable}(uuid)
    )
  ''';

  static const _journalEntryTable = 'journal_entries';

  static const createIndexSql =
      'CREATE INDEX idx_journal_lines_account ON $tableName (account_code)';

  static const createEntryIndexSql =
      'CREATE INDEX idx_journal_lines_entry ON $tableName (entry_uuid)';

  Map<String, Object?> toMap() => {
        'entry_uuid': entryUuid,
        'account_code': accountCode,
        'debit_minor_units': debitMinorUnits,
        'credit_minor_units': creditMinorUnits,
        'party_uuid': partyUuid,
        'dimension_uuid': dimensionUuid,
      };

  factory JournalLine.fromMap(Map<String, Object?> map) => JournalLine(
        entryUuid: map['entry_uuid'] as String,
        accountCode: map['account_code'] as String,
        debitMinorUnits: map['debit_minor_units'] as int,
        creditMinorUnits: map['credit_minor_units'] as int,
        partyUuid: map['party_uuid'] as String?,
        dimensionUuid: map['dimension_uuid'] as String?,
      );
}

/// The only mutation primitive in the system. Every module action (Sale,
/// Purchase, Payment, Trip Expense...) ultimately creates one of these.
/// Never edited after posting — corrections are reversing entries that
/// reference [reversalOfUuid]. This is what makes "no hard deletes" and
/// multi-device sync conflict resolution tractable at the same time.
class JournalEntry {
  JournalEntry({
    required this.uuid,
    required this.businessId,
    this.entryNumber = 0,
    required this.date,
    required this.sourceType,
    required this.sourceId,
    this.description,
    required this.status,
    this.reversalOfUuid,
    required this.createdBy,
    required this.createdAt,
    required this.deviceId,
    this.syncStatus = SyncStatus.pending,
    this.lines = const [],
  });

  final String uuid;
  final String businessId;

  /// Provisional until first successful sync assigns the real sequential
  /// number via Cloud Function (gapless invoice numbering). 0 = unsynced.
  final int entryNumber;

  final DateTime date;

  /// e.g. "Sale", "Purchase", "Payment", "TripExpense", "StockAdjustment".
  final String sourceType;
  final String sourceId;
  final String? description;
  final JournalEntryStatus status;
  final String? reversalOfUuid;
  final String createdBy;
  final DateTime createdAt;
  final String deviceId;
  final SyncStatus syncStatus;
  final List<JournalLine> lines;

  static const tableName = 'journal_entries';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      entry_number INTEGER NOT NULL DEFAULT 0,
      date TEXT NOT NULL,
      source_type TEXT NOT NULL,
      source_id TEXT NOT NULL,
      description TEXT,
      status TEXT NOT NULL,
      reversal_of_uuid TEXT,
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL,
      device_id TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'pending'
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_journal_entries_business_date ON $tableName (business_id, date)';

  static const createStatusIndexSql =
      'CREATE INDEX idx_journal_entries_status ON $tableName (business_id, status)';

  /// Defense-in-depth balance check — mirrors the server-side Cloud
  /// Function validation. A journal entry must never post unbalanced.
  bool get isBalanced =>
      lines.fold<int>(0, (sum, l) => sum + l.debitMinorUnits) ==
      lines.fold<int>(0, (sum, l) => sum + l.creditMinorUnits);

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'entry_number': entryNumber,
        'date': date.toIso8601String(),
        'source_type': sourceType,
        'source_id': sourceId,
        'description': description,
        'status': status.name,
        'reversal_of_uuid': reversalOfUuid,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'device_id': deviceId,
        'sync_status': syncStatus.name,
      };

  factory JournalEntry.fromMap(
    Map<String, Object?> map, {
    List<JournalLine> lines = const [],
  }) =>
      JournalEntry(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        entryNumber: map['entry_number'] as int,
        date: DateTime.parse(map['date'] as String),
        sourceType: map['source_type'] as String,
        sourceId: map['source_id'] as String,
        description: map['description'] as String?,
        status: JournalEntryStatus.values.byName(map['status'] as String),
        reversalOfUuid: map['reversal_of_uuid'] as String?,
        createdBy: map['created_by'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        deviceId: map['device_id'] as String,
        syncStatus: SyncStatus.values.byName(map['sync_status'] as String),
        lines: lines,
      );
}
