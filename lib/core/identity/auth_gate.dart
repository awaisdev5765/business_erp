import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../system/providers.dart';
import 'login_screen.dart';
import 'user_profile.dart';

/// Gates the app on Firebase Auth state: signed out -> [LoginScreen];
/// signed in -> ensure a /users/{uid} profile exists (provisioning the
/// first-ever user as Super Admin, see UserProfileRepository), then show
/// [child]. This replaces the Phase 0-4 "boot straight into one seeded
/// business with a hardcoded user" placeholder now that real auth exists.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  // Bumped to force a fresh _ensureProfile attempt — the web SQLite
  // backend (sqflite_common_ffi_web) is explicitly experimental and its
  // shared worker can fail to come up on the very first attempt after a
  // fresh deploy; retrying re-runs AppDatabase.open() from scratch
  // rather than reusing whatever half-initialized state caused the
  // first failure.
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = authSnapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        return FutureBuilder<UserProfile>(
          key: ValueKey(_attempt),
          future: _ensureProfile(ref, user),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (profileSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Failed to load profile: ${profileSnapshot.error}', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => setState(() => _attempt++),
                          child: const Text('Retry'),
                        ),
                        TextButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return widget.child;
          },
        );
      },
    );
  }

  Future<UserProfile> _ensureProfile(WidgetRef ref, User user) async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = ref.read(userProfileRepositoryProvider);
    final profile = await repo.ensureProfile(
      uid: user.uid,
      email: user.email ?? user.uid,
      localBusinessId: businessId,
    );

    // Best-effort — a denied notification permission or a platform
    // without FCM support shouldn't block sign-in.
    try {
      final fcm = ref.read(fcmServiceProvider);
      await fcm.registerToken(user.uid);
    } catch (_) {}

    return profile;
  }
}
