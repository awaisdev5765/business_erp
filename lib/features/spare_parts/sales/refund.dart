/// A refund line — the quantity (and its snapshot price/cost/tax, copied
/// from the SaleLine it refunds) returned in one Refund. Tied to a
/// specific [saleLineId] rather than just a product, so RefundRepository
/// can sum "how much of *this* sale line has been refunded so far" even
/// if a sale has the same product on two different lines.
class RefundLine {
  RefundLine({
    required this.refundUuid,
    required this.saleLineId,
    required this.productUuid,
    required this.quantity,
    required this.unitPriceMinorUnits,
    required this.unitCostMinorUnits,
    this.taxRatePercent = 0,
  });

  final String refundUuid;
  final int saleLineId;
  final String productUuid;
  final int quantity;
  final int unitPriceMinorUnits;
  final int unitCostMinorUnits;
  final double taxRatePercent;

  int get lineTotalMinorUnits => quantity * unitPriceMinorUnits;
  int get lineCostMinorUnits => quantity * unitCostMinorUnits;
  int get lineTaxMinorUnits => (lineTotalMinorUnits * taxRatePercent / 100).round();

  static const tableName = 'refund_lines';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      refund_uuid TEXT NOT NULL,
      sale_line_id INTEGER NOT NULL,
      product_uuid TEXT NOT NULL,
      quantity INTEGER NOT NULL,
      unit_price_minor_units INTEGER NOT NULL,
      unit_cost_minor_units INTEGER NOT NULL,
      tax_rate_percent REAL NOT NULL DEFAULT 0
    )
  ''';

  static const createIndexSql = 'CREATE INDEX idx_refund_lines_refund ON $tableName (refund_uuid)';
  static const createSaleLineIndexSql =
      'CREATE INDEX idx_refund_lines_sale_line ON $tableName (sale_line_id)';

  Map<String, Object?> toMap() => {
        'refund_uuid': refundUuid,
        'sale_line_id': saleLineId,
        'product_uuid': productUuid,
        'quantity': quantity,
        'unit_price_minor_units': unitPriceMinorUnits,
        'unit_cost_minor_units': unitCostMinorUnits,
        'tax_rate_percent': taxRatePercent,
      };

  factory RefundLine.fromMap(Map<String, Object?> map) => RefundLine(
        refundUuid: map['refund_uuid'] as String,
        saleLineId: map['sale_line_id'] as int,
        productUuid: map['product_uuid'] as String,
        quantity: map['quantity'] as int,
        unitPriceMinorUnits: map['unit_price_minor_units'] as int,
        unitCostMinorUnits: map['unit_cost_minor_units'] as int,
        taxRatePercent: (map['tax_rate_percent'] as num?)?.toDouble() ?? 0,
      );
}

/// A refund against one Sale — either partial (some quantities on some
/// lines) or full (every remaining quantity on every line), both built
/// from the same RefundRepository.refund() call. See sale_repository.dart's
/// returnSale() for the older whole-sale-only path this generalizes for
/// new refunds; that path is left in place for the sales it already
/// covers rather than migrated, since both end in the same SaleStatus.
class Refund {
  Refund({
    required this.uuid,
    required this.businessId,
    required this.saleUuid,
    required this.documentNumber,
    required this.date,
    this.reason,
    required this.createdBy,
    required this.createdAt,
    this.lines = const [],
    this.discountMinorUnits = 0,
  });

  final String uuid;
  final String businessId;
  final String saleUuid;
  final String documentNumber;
  final DateTime date;
  final String? reason;
  final String createdBy;
  final DateTime createdAt;
  final List<RefundLine> lines;

  /// This refund's share of the original sale's flat discount — see
  /// RefundRepository.refund()'s proration comment for how it's derived.
  final int discountMinorUnits;

  int get totalMinorUnits => lines.fold(0, (sum, l) => sum + l.lineTotalMinorUnits);
  int get totalCostMinorUnits => lines.fold(0, (sum, l) => sum + l.lineCostMinorUnits);
  int get totalTaxMinorUnits => lines.fold(0, (sum, l) => sum + l.lineTaxMinorUnits);
  int get grandTotalMinorUnits => totalMinorUnits + totalTaxMinorUnits;
  int get netAmountMinorUnits => grandTotalMinorUnits - discountMinorUnits;

  static const tableName = 'refunds';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      sale_uuid TEXT NOT NULL,
      document_number TEXT NOT NULL,
      date TEXT NOT NULL,
      reason TEXT,
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL,
      discount_minor_units INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static const createIndexSql = 'CREATE INDEX idx_refunds_sale ON $tableName (sale_uuid)';
  static const createBusinessDateIndexSql =
      'CREATE INDEX idx_refunds_business_date ON $tableName (business_id, date)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'sale_uuid': saleUuid,
        'document_number': documentNumber,
        'date': date.toIso8601String(),
        'reason': reason,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'discount_minor_units': discountMinorUnits,
      };

  factory Refund.fromMap(Map<String, Object?> map, {List<RefundLine> lines = const []}) => Refund(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        saleUuid: map['sale_uuid'] as String,
        documentNumber: map['document_number'] as String,
        date: DateTime.parse(map['date'] as String),
        reason: map['reason'] as String?,
        createdBy: map['created_by'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        lines: lines,
        discountMinorUnits: map['discount_minor_units'] as int? ?? 0,
      );
}
