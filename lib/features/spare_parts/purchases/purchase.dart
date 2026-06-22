enum PurchaseStatus { posted, returned, void_ }

class PurchaseLine {
  PurchaseLine({
    required this.purchaseUuid,
    required this.productUuid,
    required this.quantity,
    required this.unitCostMinorUnits,
  });

  final String purchaseUuid;
  final String productUuid;
  final int quantity;
  final int unitCostMinorUnits;

  int get lineTotalMinorUnits => quantity * unitCostMinorUnits;

  static const tableName = 'purchase_lines';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      purchase_uuid TEXT NOT NULL,
      product_uuid TEXT NOT NULL,
      quantity INTEGER NOT NULL,
      unit_cost_minor_units INTEGER NOT NULL
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_purchase_lines_purchase ON $tableName (purchase_uuid)';

  Map<String, Object?> toMap() => {
        'purchase_uuid': purchaseUuid,
        'product_uuid': productUuid,
        'quantity': quantity,
        'unit_cost_minor_units': unitCostMinorUnits,
      };

  factory PurchaseLine.fromMap(Map<String, Object?> map) => PurchaseLine(
        purchaseUuid: map['purchase_uuid'] as String,
        productUuid: map['product_uuid'] as String,
        quantity: map['quantity'] as int,
        unitCostMinorUnits: map['unit_cost_minor_units'] as int,
      );
}

/// Posts Dr Inventory (1040) / Cr Accounts Payable (2010) on creation —
/// see PurchaseRepository.create(). Returns are a separate reversing flow
/// (Phase 2), not an edit of this record.
class Purchase {
  Purchase({
    required this.uuid,
    required this.businessId,
    required this.documentNumber,
    required this.supplierUuid,
    required this.date,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.lines = const [],
  });

  final String uuid;
  final String businessId;
  final String documentNumber;
  final String supplierUuid;
  final DateTime date;
  final PurchaseStatus status;
  final String createdBy;
  final DateTime createdAt;
  final List<PurchaseLine> lines;

  int get totalMinorUnits => lines.fold(0, (sum, l) => sum + l.lineTotalMinorUnits);

  static const tableName = 'purchases';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      document_number TEXT NOT NULL,
      supplier_uuid TEXT NOT NULL,
      date TEXT NOT NULL,
      status TEXT NOT NULL,
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_purchases_business_date ON $tableName (business_id, date)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'document_number': documentNumber,
        'supplier_uuid': supplierUuid,
        'date': date.toIso8601String(),
        'status': status.name,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  factory Purchase.fromMap(Map<String, Object?> map, {List<PurchaseLine> lines = const []}) =>
      Purchase(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        documentNumber: map['document_number'] as String,
        supplierUuid: map['supplier_uuid'] as String,
        date: DateTime.parse(map['date'] as String),
        status: PurchaseStatus.values.byName(map['status'] as String),
        createdBy: map['created_by'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        lines: lines,
      );
}
