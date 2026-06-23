/// Lives in Firestore at /users/{uid} — never in local SQLite, since this
/// is exactly the document `firestore.rules` reads via `get()` to decide
/// every other access check. `businessAccess` maps businessId -> role
/// name (matching PHASES.md Section 7's role list). The very first user
/// to sign in becomes Super Admin with access to the locally-seeded
/// business — see UserProfileRepository.ensureProfile(). This is the
/// free-Spark-plan substitute for custom auth claims (see firestore.rules
/// header for why).
class UserProfile {
  UserProfile({
    required this.uid,
    required this.email,
    this.isSuperAdmin = false,
    this.businessAccess = const {},
  });

  final String uid;
  final String email;
  final bool isSuperAdmin;

  /// businessId -> role name (e.g. "businessAdmin", "cashier").
  final Map<String, String> businessAccess;

  Map<String, Object?> toMap() => {
        'uid': uid,
        'email': email,
        'isSuperAdmin': isSuperAdmin,
        'businessAccess': businessAccess,
      };

  factory UserProfile.fromMap(Map<String, Object?> map) => UserProfile(
        uid: map['uid'] as String,
        email: map['email'] as String,
        isSuperAdmin: map['isSuperAdmin'] as bool? ?? false,
        businessAccess: Map<String, String>.from(map['businessAccess'] as Map? ?? {}),
      );

  UserProfile copyWithAccess(String businessId, String role) => UserProfile(
        uid: uid,
        email: email,
        isSuperAdmin: isSuperAdmin,
        businessAccess: {...businessAccess, businessId: role},
      );
}
