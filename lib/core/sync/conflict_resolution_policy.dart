enum ConflictOutcome { autoResolvedLocal, autoResolvedRemote, needsManualResolution }

class ConflictDecision {
  ConflictDecision({
    required this.outcome,
    this.resolvedFields = const {},
    this.conflictingSensitiveFields = const [],
  });

  final ConflictOutcome outcome;

  /// The winning field values, populated only when [outcome] is one of
  /// the auto-resolved cases.
  final Map<String, Object?> resolvedFields;

  /// Which fields differ AND are sensitive, populated only when
  /// [outcome] is [ConflictOutcome.needsManualResolution].
  final List<String> conflictingSensitiveFields;
}

/// Decides how to merge two versions of the same master-data record
/// (e.g. a Party edited offline on two devices) once both reach the
/// server. Per PHASES.md Section 15:
///
/// - If nothing differs, there's no conflict at all.
/// - If only non-sensitive fields differ (name, phone, address...),
///   last-write-wins by timestamp — safe to auto-merge.
/// - If any *sensitive* field differs (credit limit, tax rate — fields
///   that affect financial defaults), it's flagged for a human to
///   resolve manually, never auto-merged, even if one side is "newer."
///
/// This is a pure function of two field snapshots + timestamps — no
/// database or network involved, which is exactly what makes it testable
/// without a live Firebase project (see PHASES.md Phase 5 status note).
/// The actual multi-device conflict *detection* (noticing two edits
/// happened) is Cloud Function/Firestore work for when a project exists;
/// this is the *decision* logic that piece will call into.
class ConflictResolutionPolicy {
  ConflictResolutionPolicy({required this.sensitiveFields});

  final Set<String> sensitiveFields;

  ConflictDecision resolve({
    required Map<String, Object?> localFields,
    required DateTime localUpdatedAt,
    required Map<String, Object?> remoteFields,
    required DateTime remoteUpdatedAt,
  }) {
    final allKeys = {...localFields.keys, ...remoteFields.keys};
    final differingFields = allKeys.where((k) => localFields[k] != remoteFields[k]).toSet();

    if (differingFields.isEmpty) {
      return ConflictDecision(outcome: ConflictOutcome.autoResolvedLocal, resolvedFields: localFields);
    }

    final sensitiveDiffs = differingFields.where(sensitiveFields.contains).toList();
    if (sensitiveDiffs.isNotEmpty) {
      return ConflictDecision(
        outcome: ConflictOutcome.needsManualResolution,
        conflictingSensitiveFields: sensitiveDiffs,
      );
    }

    final localIsNewer = localUpdatedAt.isAfter(remoteUpdatedAt);
    return ConflictDecision(
      outcome: localIsNewer ? ConflictOutcome.autoResolvedLocal : ConflictOutcome.autoResolvedRemote,
      resolvedFields: localIsNewer ? localFields : remoteFields,
    );
  }
}
