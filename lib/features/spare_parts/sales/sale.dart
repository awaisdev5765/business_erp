enum SaleStatus { posted, returned, void_ }

enum PaymentMethod { cash, credit }

class SaleLine {
  SaleLine({
    required this.saleUuid,
    required this.productUuid,
    required this.quantity,
    required this.unitPriceMinorUnits,
    required this.unitCostMinorUnits,
  });

  final String saleUuid;
  final String productUuid;
  final int quantity;
  final int unitPriceMinorUnits;

  /// Snapshot of the product's cost at sale time — needed for the COGS
  /// posting (Dr COGS / Cr Inventory) and for accurate profit reports even
  /// if the product's cost price changes later.
  final int unitCostMinorUnits;

  int get lineTotalMinorUnits => quantity * unitPriceMinorUnits;
  int get lineCostMinorUnits => quantity * unitCostMinorUnits;

  static const tableName = 'sale_lines';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_uuid TEXT NOT NULL,
      product_uuid TEXT NOT NULL,
      quantity INTEGER NOT NULL,
      unit_price_minor_units INTEGER NOT NULL,
      unit_cost_minor_units INTEGER NOT NULL
    )
  ''';

  static const createIndexSql = 'CREATE INDEX idx_sale_lines_sale ON $tableName (sale_uuid)';

  Map<String, Object?> toMap() => {
        'sale_uuid': saleUuid,
        'product_uuid': productUuid,
        'quantity': quantity,
        'unit_price_minor_units': unitPriceMinorUnits,
        'unit_cost_minor_units': unitCostMinorUnits,
      };

  factory SaleLine.fromMap(Map<String, Object?> map) => SaleLine(
        saleUuid: map['sale_uuid'] as String,
        productUuid: map['product_uuid'] as String,
        quantity: map['quantity'] as int,
        unitPriceMinorUnits: map['unit_price_minor_units'] as int,
        unitCostMinorUnits: map['unit_cost_minor_units'] as int,
      );
}

/// The highest-frequency screen in the system (PHASES.md Section 9.1).
/// Posts one balanced JournalEntry with two halves: the revenue side
/// (Dr Cash-or-Receivable / Cr Sales Income) and the cost side
/// (Dr COGS / Cr Inventory) — see SaleRepository.create(). Tax splitting
/// is a Phase 2 addition (Tax Engine).
class Sale {
  Sale({
    required this.uuid,
    required this.businessId,
    required this.documentNumber,
    this.customerUuid,
    required this.paymentMethod,
    required this.date,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.lines = const [],
  });

  final String uuid;
  final String businessId;
  final String documentNumber;

  /// Null for walk-in cash sales with no tracked customer.
  final String? customerUuid;
  final PaymentMethod paymentMethod;
  final DateTime date;
  final SaleStatus status;
  final String createdBy;
  final DateTime createdAt;
  final List<SaleLine> lines;

  int get totalMinorUnits => lines.fold(0, (sum, l) => sum + l.lineTotalMinorUnits);
  int get totalCostMinorUnits => lines.fold(0, (sum, l) => sum + l.lineCostMinorUnits);

  static const tableName = 'sales';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      document_number TEXT NOT NULL,
      customer_uuid TEXT,
      payment_method TEXT NOT NULL,
      date TEXT NOT NULL,
      status TEXT NOT NULL,
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''';

  static const createIndexSql = 'CREATE INDEX idx_sales_business_date ON $tableName (business_id, date)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'document_number': documentNumber,
        'customer_uuid': customerUuid,
        'payment_method': paymentMethod.name,
        'date': date.toIso8601String(),
        'status': status.name,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  factory Sale.fromMap(Map<String, Object?> map, {List<SaleLine> lines = const []}) => Sale(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        documentNumber: map['document_number'] as String,
        customerUuid: map['customer_uuid'] as String?,
        paymentMethod: PaymentMethod.values.byName(map['payment_method'] as String),
        date: DateTime.parse(map['date'] as String),
        status: SaleStatus.values.byName(map['status'] as String),
        createdBy: map['created_by'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        lines: lines,
      );
}
