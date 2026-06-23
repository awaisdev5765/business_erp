import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Email/password sign-in, with a toggle to register. There's no
/// password-reset flow or invite-based onboarding yet — this app is
/// architected for one owner (see UserProfileRepository.ensureProfile()),
/// so "register" here means "create the owner account," not "add a team
/// member." Multi-user invitation is later Identity work.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegistering = false;
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_isRegistering) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 24),
                TextField(
                  controller: _emailController,
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
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_isRegistering ? 'Create Account' : 'Sign In'),
                ),
                TextButton(
                  onPressed: _submitting ? null : () => setState(() => _isRegistering = !_isRegistering),
                  child: Text(_isRegistering ? 'Already have an account? Sign in' : "Don't have an account? Register"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
