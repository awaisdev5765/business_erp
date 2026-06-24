/// The one Super Admin (SaaS owner) account — sees every business
/// (Spare Parts, Fishery, Transport) and is the only account that can
/// create staff logins. Fixed rather than "whoever signs up first",
/// since staff accounts are now admin-provisioned, not self-registered
/// (see StaffManagementScreen) — letting registration order decide who
/// is Super Admin stopped being safe once anyone but the owner could
/// reach the sign-in screen.
const kSuperAdminEmail = 'superadmin@berp.com';

/// Roles a Super Admin can grant a staff member on a specific business.
/// Matches the role names `firestore.rules`' `roleFor()` checks against
/// (e.g. `readOnlyAuditor` never gets write access there).
const kStaffRoles = ['businessAdmin', 'accountant', 'cashier', 'readOnlyAuditor'];

/// Lives in Firestore at /users/{uid} — never in local SQLite, since this
/// is exactly the document `firestore.rules` reads via `get()` to decide
/// every other access check. `businessAccess` maps businessId -> role
/// name. Profiles are created on first sign-in (UserProfileRepository.
/// ensureProfile()) but `businessAccess` itself is only ever populated by
/// the Super Admin via `grantAccess`/`revokeAccess` — this is the
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
