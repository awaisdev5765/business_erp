/// Per-business, per-document-type sequence counters (invoice numbers,
/// PO numbers, payment receipt numbers...). Until Phase 5 wires a Cloud
/// Function for server-side atomic issuance (see PHASES.md Section 14 —
/// "gapless sequential invoice numbering"), this local counter is the
/// sole source of truth for a single-device deployment. Numbers issued
/// here are prefixed "LOCAL-" so they're visibly distinguishable from the
/// future server-confirmed numbers and won't collide with them.
class NumberSequence {
  static const tableName = 'number_sequences';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      business_id TEXT NOT NULL,
      doc_type TEXT NOT NULL,
      last_number INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (business_id, doc_type)
    )
  ''';
}
