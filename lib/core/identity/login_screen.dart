import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'user_profile.dart';

/// Email/password sign-in, plus a one-time "Register as Super Admin"
/// bootstrap button. Every account except the fixed Super Admin
/// (kSuperAdminEmail) is created by the Super Admin via
/// StaffManagementScreen once signed in — so this button only ever
/// creates *that one* fixed account, and disappears for good (for every
/// future visitor, not just this session) the moment it's used: it
/// checks the public `/meta/bootstrap` Firestore flag (the only
/// document signed-out users can read — see firestore.rules) and hides
/// itself if a Super Admin already exists.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  bool? _superAdminExists; // null while still checking
  bool _registeringSuperAdmin = false;
  bool _sendingReset = false;
  String? _info;

  @override
  void initState() {
    super.initState();
    _checkSuperAdminExists();
  }

  Future<void> _checkSuperAdminExists() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('meta').doc('bootstrap').get();
      final exists = doc.data()?['superAdminCreated'] == true;
      if (mounted) {
        setState(() {
          _superAdminExists = exists;
          if (!exists) _emailController.text = kSuperAdminEmail;
        });
      }
    } catch (_) {
      // Offline on first ever launch, or rules not deployed yet — fail
      // open to "show the button" rather than lock out bootstrapping.
      if (mounted) {
        setState(() {
          _superAdminExists = false;
          _emailController.text = kSuperAdminEmail;
        });
      }
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Self-service password recovery — no Super Admin involvement
  /// needed. Firebase Auth's `sendPasswordResetEmail` works out of the
  /// box on the free Spark plan (it's part of the Auth product itself,
  /// not a Cloud Function), so this needed no backend changes.
  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email above first, then tap "Forgot password?"');
      return;
    }
    setState(() {
      _sendingReset = true;
      _error = null;
      _info = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _info = 'Password reset email sent to $email.');
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  Future<void> _registerSuperAdmin() async {
    setState(() {
      _registeringSuperAdmin = true;
      _error = null;
    });
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: kSuperAdminEmail,
        password: _passwordController.text,
      );
      // Matches what UserProfileRepository.ensureProfile would write on
      // a normal first sign-in — written here too so the flag is set
      // before AuthGate's own ensureProfile call races it (harmless
      // either way, ensureProfile is a no-op once a profile exists).
      await FirebaseFirestore.instance.collection('users').doc(credential.user!.uid).set({
        'uid': credential.user!.uid,
        'email': kSuperAdminEmail,
        'isSuperAdmin': true,
        'businessAccess': <String, String>{},
      });
      await FirebaseFirestore.instance.collection('meta').doc('bootstrap').set({'superAdminCreated': true});
      // AuthGate's authStateChanges listener takes over from here — no
      // need to navigate manually.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _registeringSuperAdmin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showBootstrapButton = _superAdminExists == false;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.business, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Business ERP',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  showBootstrapButton
                      ? 'No Super Admin yet — set a password above and register one ($kSuperAdminEmail), or sign in if you already have an account.'
                      : 'Sign in with the email and password your administrator gave you.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailController,
                  enabled: !showBootstrapButton,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 12),
                  Text(_info!, style: const TextStyle(color: Colors.green)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Sign In'),
                ),
                if (!showBootstrapButton) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _sendingReset ? null : _sendPasswordReset,
                    child: _sendingReset
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Forgot password?'),
                  ),
                ],
                if (showBootstrapButton) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _registeringSuperAdmin ? null : _registerSuperAdmin,
                    child: _registeringSuperAdmin
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Register as Super Admin'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
