enum PaymentDirection { receiveFromCustomer, payToSupplier }

/// How the money actually moved — shown on the party ledger so a
/// payment is more than just a number; "cash" was the only option that
/// ever existed before (the field didn't exist at all).
enum PaymentSettlementMethod { cash, bankTransfer, cheque, card, other }

/// A Payment In settles a customer's receivable (Dr Cash / Cr Receivable);
/// a Payment Out settles a supplier's payable (Dr Payable / Cr Cash). Both
/// directions are tagged with the party's uuid so they net against the
/// same Customer/Supplier Ledger view the Sale/Purchase lines populate.
/// See PHASES.md Section 11.
class Payment {
  Payment({
    required this.uuid,
    required this.businessId,
    required this.documentNumber,
    required this.partyUuid,
    required this.direction,
    required this.amountMinorUnits,
    this.method = PaymentSettlementMethod.cash,
    this.note,
    required this.date,
    required this.createdBy,
    required this.createdAt,
  });

  final String uuid;
  final String businessId;
  final String documentNumber;
  final String partyUuid;
  final PaymentDirection direction;
  final int amountMinorUnits;

  /// How it was paid (cash/bank/cheque/card/other).
  final PaymentSettlementMethod method;

  /// Free-text reference — cheque number, transfer ref, anything that
  /// makes the payment traceable beyond just an amount and a date.
  final String? note;

  final DateTime date;
  final String createdBy;
  final DateTime createdAt;

  static const tableName = 'payments';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      document_number TEXT NOT NULL,
      party_uuid TEXT NOT NULL,
      direction TEXT NOT NULL,
      amount_minor_units INTEGER NOT NULL,
      method TEXT NOT NULL DEFAULT 'cash',
      note TEXT,
      date TEXT NOT NULL,
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_payments_business_date ON $tableName (business_id, date)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'document_number': documentNumber,
        'party_uuid': partyUuid,
        'direction': direction.name,
        'amount_minor_units': amountMinorUnits,
        'method': method.name,
        'note': note,
        'date': date.toIso8601String(),
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  factory Payment.fromMap(Map<String, Object?> map) => Payment(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        documentNumber: map['document_number'] as String,
        partyUuid: map['party_uuid'] as String,
        direction: PaymentDirection.values.byName(map['direction'] as String),
        amountMinorUnits: map['amount_minor_units'] as int,
        method: PaymentSettlementMethod.values.byName(map['method'] as String? ?? 'cash'),
        note: map['note'] as String?,
        date: DateTime.parse(map['date'] as String),
        createdBy: map['created_by'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
