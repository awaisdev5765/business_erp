/// Per-business, per-document-type, per-year sequence counters (invoice
/// numbers, PO numbers, payment receipt numbers...) — keying on [year] is
/// what makes document numbers reset to 1 every January, the standard
/// accounting-numbering convention (e.g. "SALE-2026-000001"). Until Phase
/// 5 wires a Cloud Function for server-side atomic issuance (see
/// PHASES.md Section 14 — "gapless sequential invoice numbering"), this
/// local counter is the sole source of truth for a single-device
/// deployment.
class NumberSequence {
  static const tableName = 'number_sequences';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      business_id TEXT NOT NULL,
      doc_type TEXT NOT NULL,
      year INTEGER NOT NULL,
      last_number INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (business_id, doc_type, year)
    )
  ''';
}
