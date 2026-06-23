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

  /// Creates the profile on first sign-in. The first user ever to sign
  /// in becomes Super Admin with admin access to [localBusinessId] — this
  /// app is architected as one owner running several businesses (PHASES.md
  /// "Business Structure"), so there's no separate invite/provisioning
  /// flow yet. Idempotent: does nothing if a profile already exists.
  Future<UserProfile> ensureProfile({
    required String uid,
    required String email,
    required String localBusinessId,
  }) async {
    final existing = await find(uid);
    if (existing != null) return existing;

    final isFirstUser = (await _users.limit(1).get()).docs.isEmpty;
    final profile = UserProfile(
      uid: uid,
      email: email,
      isSuperAdmin: isFirstUser,
      businessAccess: {localBusinessId: 'businessAdmin'},
    );
    await _users.doc(uid).set(profile.toMap());
    return profile;
  }

  /// Grants [role] on [businessId] to [uid] — called when a new Business
  /// is created via the Business Switcher, so the creating user's
  /// `/users/{uid}` profile (and therefore `firestore.rules`) actually
  /// permits them to read/write it. Without this, a newly created
  /// business would be invisible to its own creator once synced.
  Future<void> grantAccess({required String uid, required String businessId, required String role}) async {
    final profile = await find(uid);
    if (profile == null) return;
    final updated = profile.copyWithAccess(businessId, role);
    await _users.doc(uid).set(updated.toMap());
  }
}
