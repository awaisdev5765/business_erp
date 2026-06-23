enum TripType { fishery, transport }

enum TripStatus { planned, inProgress, completed }

/// A Trip is the same abstract entity for both Fishery (a boat's fishing
/// trip) and Transport (a vehicle's haul) — same fields, different
/// `tripType` and a different set of related records (CatchEntry/FishSale
/// for fishery; trip income for transport, added in Phase 4). See
/// PHASES.md Section 6/12.
///
/// Crew assignment beyond the single `captainUuid` (a multi-person
/// per-trip crew roster) is deferred — Crew exist as Party records (type
/// captain/crew) so they're trackable, but a trip-to-crew junction table
/// is future work once that's actually needed.
class Trip {
  Trip({
    required this.uuid,
    required this.businessId,
    required this.tripType,
    required this.assetUuid,
    this.captainUuid,
    required this.status,
    required this.startDate,
    this.endDate,
    this.notes,
  });

  final String uuid;
  final String businessId;
  final TripType tripType;

  /// OperatingAsset uuid (boat for fishery, vehicle for transport).
  final String assetUuid;
  final String? captainUuid;
  final TripStatus status;
  final DateTime startDate;
  final DateTime? endDate;
  final String? notes;

  static const tableName = 'trips';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      trip_type TEXT NOT NULL,
      asset_uuid TEXT NOT NULL,
      captain_uuid TEXT,
      status TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT,
      notes TEXT
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_trips_business_asset ON $tableName (business_id, asset_uuid)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'trip_type': tripType.name,
        'asset_uuid': assetUuid,
        'captain_uuid': captainUuid,
        'status': status.name,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'notes': notes,
      };

  factory Trip.fromMap(Map<String, Object?> map) => Trip(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        tripType: TripType.values.byName(map['trip_type'] as String),
        assetUuid: map['asset_uuid'] as String,
        captainUuid: map['captain_uuid'] as String?,
        status: TripStatus.values.byName(map['status'] as String),
        startDate: DateTime.parse(map['start_date'] as String),
        endDate: map['end_date'] != null ? DateTime.parse(map['end_date'] as String) : null,
        notes: map['notes'] as String?,
      );

  Trip copyWith({TripStatus? status, DateTime? endDate}) => Trip(
        uuid: uuid,
        businessId: businessId,
        tripType: tripType,
        assetUuid: assetUuid,
        captainUuid: captainUuid,
        status: status ?? this.status,
        startDate: startDate,
        endDate: endDate ?? this.endDate,
        notes: notes,
      );
}
