/// Running debit/credit totals per `(business_id, account_code)`,
/// maintained incrementally inside `LedgerRepository.postWithin()`
/// instead of recomputed by scanning `journal_lines` on every read. See
/// PHASES.md Phase 8 and Section 12 ("rollup tables for 100k+ row
/// performance").
class AccountBalanceRollup {
  static const tableName = 'account_balance_rollups';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      business_id TEXT NOT NULL,
      account_code TEXT NOT NULL,
      debit_total INTEGER NOT NULL DEFAULT 0,
      credit_total INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (business_id, account_code)
    )
  ''';
}

/// Running debit/credit totals per `party_uuid` — the same idea as
/// [AccountBalanceRollup], keyed by party instead of account, backing
/// `PartyRepository.outstandingBalanceMinorUnits()`.
class PartyBalanceRollup {
  static const tableName = 'party_balance_rollups';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      party_uuid TEXT PRIMARY KEY,
      debit_total INTEGER NOT NULL DEFAULT 0,
      credit_total INTEGER NOT NULL DEFAULT 0
    )
  ''';
}
