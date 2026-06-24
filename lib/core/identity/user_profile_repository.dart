import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_profile.dart';

class UserProfileRepository {
  UserProfileRepository(this.firestore);

  final FirebaseFirestore firestore;

  CollectionReference<Map<String, Object?>> get _users => firestore.collection('users');

  Future<UserProfile?> find(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromMap(doc.data()!);
  }

  /// Creates the profile on first sign-in. Super Admin status is fixed
  /// to [kSuperAdminEmail], not "first to sign up" — staff accounts are
  /// now created by the Super Admin (see StaffManagementScreen), so
  /// `businessAccess` starts empty for everyone and is only ever
  /// populated by `grantAccess`. Idempotent: does nothing if a profile
  /// already exists.
  Future<UserProfile> ensureProfile({
    required String uid,
    required String email,
  }) async {
    final existing = await find(uid);
    if (existing != null) return existing;

    final isSuperAdmin = email.toLowerCase() == kSuperAdminEmail;
    final profile = UserProfile(
      uid: uid,
      email: email,
      isSuperAdmin: isSuperAdmin,
      businessAccess: const {},
    );
    await _users.doc(uid).set(profile.toMap());
    return profile;
  }

  /// Grants [role] on [businessId] to [uid] — called by the Super Admin
  /// via StaffManagementScreen, or when a new Business is created via the
  /// Business Switcher (so the creating user's `/users/{uid}` profile,
  /// and therefore `firestore.rules`, actually permits them to read/write
  /// it; otherwise a newly created business would be invisible to its own
  /// creator once synced).
  Future<void> grantAccess({required String uid, required String businessId, required String role}) async {
    final profile = await find(uid);
    if (profile == null) return;
    final updated = profile.copyWithAccess(businessId, role);
    await _users.doc(uid).set(updated.toMap());
  }

  /// Removes [businessId] from [uid]'s access — the Super Admin revoking
  /// a staff member's access to one business (their access to any other
  /// business, if granted, is untouched).
  Future<void> revokeAccess({required String uid, required String businessId}) async {
    final profile = await find(uid);
    if (profile == null) return;
    final access = {...profile.businessAccess}..remove(businessId);
    final updated = UserProfile(uid: uid, email: profile.email, isSuperAdmin: profile.isSuperAdmin, businessAccess: access);
    await _users.doc(uid).set(updated.toMap());
  }

  /// Every staff profile except the Super Admin's own — for
  /// StaffManagementScreen's roster.
  Future<List<UserProfile>> listStaff() async {
    final docs = (await _users.get()).docs;
    return docs.map((d) => UserProfile.fromMap(d.data())).where((p) => !p.isSuperAdmin).toList();
  }
}
