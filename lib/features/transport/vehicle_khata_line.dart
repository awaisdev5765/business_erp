/// One row of Gari Khata — same shape as their Excel tab:
/// Date | Tafseel | Kharcha | Jama Raqam | running Total Raqam.
enum VehicleKhataKind { opening, kharcha, jama }

class VehicleKhataLine {
  VehicleKhataLine({
    required this.uuid,
    required this.businessId,
    required this.vehicleUuid,
    required this.date,
    required this.tafseel,
    required this.kind,
    this.kharchaMinorUnits = 0,
    this.jamaMinorUnits = 0,
    this.sourceType,
    this.sourceId,
  });

  final String uuid;
  final String businessId;
  final String vehicleUuid;
  final DateTime date;
  final String tafseel;
  final VehicleKhataKind kind;
  final int kharchaMinorUnits;
  final int jamaMinorUnits;
  final String? sourceType;
  final String? sourceId;

  static const tableName = 'vehicle_khata_lines';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      vehicle_uuid TEXT NOT NULL,
      date TEXT NOT NULL,
      tafseel TEXT NOT NULL,
      kind TEXT NOT NULL,
      kharcha_minor_units INTEGER NOT NULL DEFAULT 0,
      jama_minor_units INTEGER NOT NULL DEFAULT 0,
      source_type TEXT,
      source_id TEXT
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_vehicle_khata_vehicle_date ON $tableName (vehicle_uuid, date)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'vehicle_uuid': vehicleUuid,
        'date': date.toIso8601String(),
        'tafseel': tafseel,
        'kind': kind.name,
        'kharcha_minor_units': kharchaMinorUnits,
        'jama_minor_units': jamaMinorUnits,
        'source_type': sourceType,
        'source_id': sourceId,
      };

  factory VehicleKhataLine.fromMap(Map<String, Object?> map) => VehicleKhataLine(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        vehicleUuid: map['vehicle_uuid'] as String,
        date: DateTime.parse(map['date'] as String),
        tafseel: map['tafseel'] as String,
        kind: VehicleKhataKind.values.byName(map['kind'] as String),
        kharchaMinorUnits: map['kharcha_minor_units'] as int? ?? 0,
        jamaMinorUnits: map['jama_minor_units'] as int? ?? 0,
        sourceType: map['source_type'] as String?,
        sourceId: map['source_id'] as String?,
      );
}

class VehicleKhataRow {
  VehicleKhataRow({required this.line, required this.runningBalanceMinorUnits});

  final VehicleKhataLine line;
  final int runningBalanceMinorUnits;
}
