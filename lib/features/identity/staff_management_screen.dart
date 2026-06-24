import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/identity/user_profile.dart';
import '../../core/system/providers.dart';
import '../../core/tenant/business.dart';
import '../../firebase_options.dart';
import '../../shared/theme/app_theme.dart';

/// Super-Admin-only: create staff logins and grant them access to one or
/// more businesses. Replaces public self-registration (LoginScreen no
/// longer offers "Register") — every account but the Super Admin's own
/// is now provisioned here, per the brief: "staff should login from
/// another email/password which is assigned by super admin."
///
/// Creating a Firebase Auth user from client code normally signs the
/// *caller* out and into the new account — there's no Admin SDK here
/// (free Spark plan, no Cloud Functions) to create users server-side.
/// The standard client-only workaround: spin up a second, throwaway
/// `FirebaseApp` with the same project config, create the user on
/// *that* app's Auth instance (leaving the Super Admin's own session on
/// the default app untouched), then delete the throwaway app.
class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  ConsumerState<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  List<UserProfile>? _staff;
  List<Business>? _businesses;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profileRepo = ref.read(userProfileRepositoryProvider);
    final businessRepo = await ref.read(businessRepositoryProvider.future);
    final staff = await profileRepo.listStaff();
    final businesses = await businessRepo.list();
    if (mounted) {
      setState(() {
        _staff = staff;
        _businesses = businesses;
      });
    }
  }

  Future<void> _createStaffUser(String email, String password, String businessId, String role) async {
    final secondaryApp = await Firebase.initializeApp(
      name: 'staff-provisioning-${DateTime.now().microsecondsSinceEpoch}',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(email: email, password: password);
      final uid = credential.user!.uid;
      await secondaryAuth.signOut();

      final profileRepo = ref.read(userProfileRepositoryProvider);
      // firestore.rules only lets a /users/{uid} doc be *created* by
      // that uid's own auth (so a staff member can't self-grant
      // businessAccess at creation time) — sign back into the secondary
      // app briefly to write that baseline doc as the new user
      // themself, the same shape ensureProfile() writes on a normal
      // first sign-in. grantAccess (a Super Admin `update`) handles the
      // actual access grant right after, back on the default app.
      await secondaryAuth.signInWithEmailAndPassword(email: email, password: password);
      await FirebaseFirestore.instanceFor(app: secondaryApp).collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'isSuperAdmin': false,
        'businessAccess': <String, String>{},
      });
      await secondaryAuth.signOut();

      await profileRepo.grantAccess(uid: uid, businessId: businessId, role: role);
    } finally {
      await secondaryApp.delete();
    }
  }

  Future<void> _showAddStaffDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final businesses = _businesses ?? const <Business>[];
    if (businesses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a business first (Switch Business → +).')),
      );
      return;
    }
    String businessId = businesses.first.uuid;
    String role = kStaffRoles.first;
    String? error;
    var submitting = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Staff'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'Password (set by you)'),
                  obscureText: true,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: businessId,
                  decoration: const InputDecoration(labelText: 'Business'),
                  items: businesses
                      .map((b) => DropdownMenuItem(value: b.uuid, child: Text(b.name)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => businessId = v ?? businessId),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: kStaffRoles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setDialogState(() => role = v ?? role),
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setDialogState(() => submitting = true);
                      try {
                        await _createStaffUser(
                          emailController.text.trim(),
                          passwordController.text,
                          businessId,
                          role,
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } on FirebaseAuthException catch (e) {
                        setDialogState(() {
                          error = e.message ?? e.code;
                          submitting = false;
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (created == true) await _load();
  }

  Future<void> _showEditAccessDialog(UserProfile staff) async {
    final businesses = _businesses ?? const <Business>[];
    String businessId = businesses.firstWhere(
      (b) => !staff.businessAccess.containsKey(b.uuid),
      orElse: () => businesses.first,
    ).uuid;
    String role = kStaffRoles.first;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(staff.email),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Current access', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.sm),
              if (staff.businessAccess.isEmpty) const Text('None yet'),
              ...staff.businessAccess.entries.map((e) {
                final business = businesses.where((b) => b.uuid == e.key).firstOrNull;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(business?.name ?? e.key),
                  subtitle: Text(e.value),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context, 'revoke:${e.key}'),
                  ),
                );
              }),
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
              const Text('Grant access', style: TextStyle(fontWeight: FontWeight.w600)),
              DropdownButtonFormField<String>(
                initialValue: businessId,
                decoration: const InputDecoration(labelText: 'Business'),
                items: businesses.map((b) => DropdownMenuItem(value: b.uuid, child: Text(b.name))).toList(),
                onChanged: (v) => setDialogState(() => businessId = v ?? businessId),
              ),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: kStaffRoles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => setDialogState(() => role = v ?? role),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'grant:$businessId:$role'),
              child: const Text('Grant'),
            ),
          ],
        ),
      ),
    );

    if (action == null) return;
    final profileRepo = ref.read(userProfileRepositoryProvider);
    if (action.startsWith('revoke:')) {
      await profileRepo.revokeAccess(uid: staff.uid, businessId: action.substring('revoke:'.length));
    } else if (action.startsWith('grant:')) {
      final parts = action.substring('grant:'.length).split(':');
      await profileRepo.grantAccess(uid: staff.uid, businessId: parts[0], role: parts[1]);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider);

    return profile.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('$e'))),
      data: (profile) {
        if (profile == null || !profile.isSuperAdmin) {
          return const Scaffold(body: Center(child: Text('Super Admin access required.')));
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Team')),
          floatingActionButton: FloatingActionButton(onPressed: _showAddStaffDialog, child: const Icon(Icons.person_add_outlined)),
          body: _staff == null
              ? const Center(child: CircularProgressIndicator())
              : _staff!.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.groups_2_outlined, size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: AppSpacing.md),
                          const Text('No staff yet. Add one with the + button.'),
                        ],
                      ),
                    )
                  : _buildGroupedByBusiness(context),
        );
      },
    );
  }

  /// Grouped by business — "check staff according to set with business"
  /// — rather than one flat list where you'd have to read each row's
  /// access labels to figure out who's on which business. A staff
  /// member with access to N businesses appears once under each.
  Widget _buildGroupedByBusiness(BuildContext context) {
    final staff = _staff!;
    final businesses = _businesses ?? const <Business>[];
    final unassigned = staff.where((s) => s.businessAccess.isEmpty).toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        for (final business in businesses) ...[
          _buildBusinessGroup(
            context,
            title: business.name,
            staffInGroup: staff.where((s) => s.businessAccess.containsKey(business.uuid)).toList(),
            roleFor: (s) => s.businessAccess[business.uuid]!,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (unassigned.isNotEmpty)
          _buildBusinessGroup(
            context,
            title: 'Unassigned',
            staffInGroup: unassigned,
            roleFor: (_) => null,
          ),
      ],
    );
  }

  Widget _buildBusinessGroup(
    BuildContext context, {
    required String title,
    required List<UserProfile> staffInGroup,
    required String? Function(UserProfile) roleFor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: AppSpacing.sm),
        if (staffInGroup.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('No staff assigned yet', style: TextStyle(color: Colors.grey.shade500)),
          )
        else
          ...staffInGroup.map((staff) {
            final role = roleFor(staff);
            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(staff.email),
                subtitle: role != null ? Text(role) : const Text('No business assigned'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showEditAccessDialog(staff),
              ),
            );
          }),
      ],
    );
  }
}
