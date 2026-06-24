import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/activity/trip.dart';
import 'core/asset/operating_asset.dart';
import 'core/identity/auth_gate.dart';
import 'core/identity/user_profile.dart';
import 'core/notifications/notification_item.dart';
import 'core/party/party.dart';
import 'core/party/party_list_screen.dart';
import 'core/system/providers.dart';
import 'core/tenant/business.dart';
import 'features/accounting/approvals_screen.dart';
import 'features/accounting/audit_trail_screen.dart';
import 'features/accounting/bank_accounts_screen.dart';
import 'features/accounting/cash_book_screen.dart';
import 'features/accounting/expenses_screen.dart';
import 'features/accounting/fixed_assets_screen.dart';
import 'features/accounting/profit_and_loss_screen.dart';
import 'features/accounting/trial_balance_screen.dart';
import 'features/activity/assets_screen.dart';
import 'features/activity/crew_screen.dart';
import 'features/activity/trips_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/payroll/payroll_screen.dart';
import 'features/spare_parts/inventory/product_list_screen.dart';
import 'features/spare_parts/purchases/purchase_entry_screen.dart';
import 'features/spare_parts/sales/sale_entry_screen.dart';
import 'features/identity/staff_management_screen.dart';
import 'features/sync/sync_status_screen.dart';
import 'features/tenant/business_switcher_screen.dart';
import 'features/tenant/cross_business_dashboard_screen.dart';
import 'features/transport/contracts_screen.dart';
import 'features/transport/driver_performance_screen.dart';
import 'package:business_erp/shared/theme/app_theme.dart';
import 'shared/widgets/app_sidebar.dart';

class BusinessErpApp extends StatelessWidget {
  const BusinessErpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Business ERP',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const AuthGate(child: AppShell()),
    );
  }
}

/// One nav destination. [visibleFor] is `null` for screens relevant to
/// every business type (Dashboard, accounting reports, Payroll, Sync
/// Status...); otherwise it's the set of [BusinessType]s the screen
/// applies to (Spare Parts screens, Fishery screens, Transport screens).
/// See PHASES.md Phase 9 — this replaces the long-carried "Known gap"
/// where every business type's screens showed side by side regardless of
/// which business was actually active.
class _Destination {
  const _Destination({
    required this.icon,
    required this.label,
    required this.builder,
    required this.section,
    this.visibleFor,
  });

  final IconData icon;
  final String label;
  final Widget Function() builder;

  /// Sidebar group header — see `AppSidebar`/`AppSidebarGroup`.
  final String? section;
  final Set<BusinessType>? visibleFor;

  bool appliesTo(BusinessType type) =>
      visibleFor == null || visibleFor!.contains(type);
}

/// Which sidebar sections a staff role can see — "staff should only see
/// some of what the Super Admin can see," per the brief. Super Admin
/// (or a `businessAdmin` grant) always sees everything; `null` `section`
/// (Dashboard) is always visible to everyone. This only filters the
/// *nav* — it doesn't (yet) enforce role at the data-write level inside
/// each screen, since the local SQLite database has no row-level role
/// checks; that's a real, accepted gap, same category as the
/// `firestore.rules` header's documented client-validation-only ones.
const _operationalSections = {'Spare Parts', 'Fishery', 'Transport'};
const _financialSections = {'Parties', 'Accounting'};

bool _sectionVisibleForRole(String? section, String? role, bool isSuperAdmin) {
  if (isSuperAdmin || section == null) return true;
  switch (role) {
    case 'businessAdmin':
      return true;
    case 'cashier':
      return _operationalSections.contains(section) || section == 'Parties';
    case 'accountant':
    case 'readOnlyAuditor':
      return _financialSections.contains(section) || section == 'Admin';
    default:
      // No role on record for this business (shouldn't normally happen
      // — grantAccess always sets one) — fail toward the narrower,
      // operational-only view rather than silently showing everything.
      return _operationalSections.contains(section) || section == 'Parties';
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  Timer? _syncTimer;
  StreamSubscription<RemoteMessage>? _fcmSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backgroundSync();
    // Periodic background sync while the app is open — see
    // FirestoreSyncService.syncAll. 3 minutes balances "reasonably
    // fresh" against not hammering Firestore reads on the free plan.
    _syncTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) => _backgroundSync(),
    );

    // Foreground messages don't show a system notification automatically
    // (only background/terminated does) — show an in-app SnackBar
    // instead. See FcmService's doc comment: nothing in this app sends
    // these yet without Cloud Functions; this just displays one if
    // something does (a manual Console-composed message, for instance).
    _fcmSubscription = FirebaseMessaging.onMessage.listen((message) {
      final text = message.notification?.title ?? message.notification?.body;
      if (text != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _fcmSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _backgroundSync();
    }
  }

  Future<void> _backgroundSync() async {
    try {
      final businessId = await ref.read(currentBusinessIdProvider.future);
      final service = await ref.read(firestoreSyncServiceProvider.future);
      await service.syncAll(businessId);
    } catch (_) {
      // Silent — offline or a transient Firestore error is normal and
      // expected here; the Sync Status screen surfaces real failures
      // (queue items move to `failed` with the error attached), this
      // background tick just shouldn't crash the app over it.
    }
  }

  static final _allDestinations = <_Destination>[
    _Destination(
      icon: Icons.dashboard_outlined,
      label: 'Dashboard',
      section: null,
      builder: () => const DashboardScreen(),
    ),

    // --- Operations (exactly one of these three groups shows at a time) ---
    _Destination(
      icon: Icons.point_of_sale_outlined,
      label: 'Sales',
      section: 'Spare Parts',
      visibleFor: const {BusinessType.sparePartsShop},
      builder: () => const SaleEntryScreen(),
    ),
    _Destination(
      icon: Icons.shopping_cart_outlined,
      label: 'Purchases',
      section: 'Spare Parts',
      visibleFor: const {BusinessType.sparePartsShop},
      builder: () => const PurchaseEntryScreen(),
    ),
    _Destination(
      icon: Icons.inventory_2_outlined,
      label: 'Products',
      section: 'Spare Parts',
      visibleFor: const {BusinessType.sparePartsShop},
      builder: () => const ProductListScreen(),
    ),
    _Destination(
      icon: Icons.directions_boat_outlined,
      label: 'Boats',
      section: 'Fishery',
      visibleFor: const {BusinessType.fishery},
      builder: () => const AssetsScreen(assetType: OperatingAssetType.boat),
    ),
    _Destination(
      icon: Icons.groups_outlined,
      label: 'Crew',
      section: 'Fishery',
      visibleFor: const {BusinessType.fishery},
      builder: () => CrewScreen(
        title: 'Captains & Crew',
        roles: const [PartyType.captain, PartyType.crew],
        roleLabels: const {
          PartyType.captain: 'Captain',
          PartyType.crew: 'Crew',
        },
      ),
    ),
    _Destination(
      icon: Icons.sailing_outlined,
      label: 'Fishing Trips',
      section: 'Fishery',
      visibleFor: const {BusinessType.fishery},
      builder: () => const TripsScreen(tripType: TripType.fishery),
    ),
    _Destination(
      icon: Icons.local_shipping_outlined,
      label: 'Vehicles',
      section: 'Transport',
      visibleFor: const {BusinessType.transport},
      builder: () => const AssetsScreen(assetType: OperatingAssetType.vehicle),
    ),
    _Destination(
      icon: Icons.badge_outlined,
      label: 'Drivers',
      section: 'Transport',
      visibleFor: const {BusinessType.transport},
      builder: () => CrewScreen(
        title: 'Drivers',
        roles: const [PartyType.driver],
        roleLabels: const {PartyType.driver: 'Driver'},
        onTapPerson: (context, person) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DriverPerformanceScreen(driver: person),
          ),
        ),
      ),
    ),
    _Destination(
      icon: Icons.description_outlined,
      label: 'Contracts',
      section: 'Transport',
      visibleFor: const {BusinessType.transport},
      builder: () => const ContractsScreen(),
    ),
    _Destination(
      icon: Icons.alt_route_outlined,
      label: 'Haul Trips',
      section: 'Transport',
      visibleFor: const {BusinessType.transport},
      builder: () => const TripsScreen(tripType: TripType.transport),
    ),

    // --- Parties ---
    _Destination(
      icon: Icons.people_outline,
      label: 'Customers',
      section: 'Parties',
      builder: () => const PartyListScreen(type: PartyType.customer),
    ),
    _Destination(
      icon: Icons.local_shipping_outlined,
      label: 'Suppliers',
      section: 'Parties',
      builder: () => const PartyListScreen(type: PartyType.supplier),
    ),

    // --- Accounting ---
    _Destination(
      icon: Icons.account_balance_wallet_outlined,
      label: 'Cash Book',
      section: 'Accounting',
      builder: () => const CashBookScreen(),
    ),
    _Destination(
      icon: Icons.balance_outlined,
      label: 'Trial Balance',
      section: 'Accounting',
      builder: () => const TrialBalanceScreen(),
    ),
    _Destination(
      icon: Icons.trending_up_outlined,
      label: 'P&L',
      section: 'Accounting',
      builder: () => const ProfitAndLossScreen(),
    ),
    _Destination(
      icon: Icons.history_outlined,
      label: 'Audit Trail',
      section: 'Accounting',
      builder: () => const AuditTrailScreen(),
    ),
    _Destination(
      icon: Icons.account_balance_outlined,
      label: 'Bank Accounts',
      section: 'Accounting',
      builder: () => const BankAccountsScreen(),
    ),
    _Destination(
      icon: Icons.precision_manufacturing_outlined,
      label: 'Fixed Assets',
      section: 'Accounting',
      builder: () => const FixedAssetsScreen(),
    ),
    _Destination(
      icon: Icons.fact_check_outlined,
      label: 'Approvals',
      section: 'Accounting',
      builder: () => const ApprovalsScreen(),
    ),
    _Destination(
      icon: Icons.payments_outlined,
      label: 'Payroll',
      section: 'Accounting',
      builder: () => const PayrollScreen(),
    ),
    _Destination(
      icon: Icons.receipt_long_outlined,
      label: 'Expenses',
      section: 'Accounting',
      builder: () => const ExpensesScreen(),
    ),

    // --- Admin ---
    _Destination(
      icon: Icons.sync_outlined,
      label: 'Sync Status',
      section: 'Admin',
      builder: () => const SyncStatusScreen(),
    ),
    _Destination(
      icon: Icons.dashboard_customize_outlined,
      label: 'All Businesses',
      section: 'Admin',
      builder: () => const CrossBusinessDashboardScreen(),
    ),
    _Destination(
      icon: Icons.groups_2_outlined,
      label: 'Team',
      section: 'Admin',
      builder: () => const StaffManagementScreen(),
    ),
  ];

  Future<void> _showBusinessMenu(BuildContext menuContext) async {
    final value = await showMenu<String>(
      context: menuContext,
      position: const RelativeRect.fromLTRB(16, 0, 16, 16),
      items: const [
        PopupMenuItem(value: 'switch', child: Text('Switch Business')),
        PopupMenuItem(value: 'signout', child: Text('Sign out')),
      ],
    );
    if (!mounted) return;
    if (value == 'switch') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const BusinessSwitcherScreen()));
      if (mounted) setState(() => _selectedIndex = 0);
    } else if (value == 'signout') {
      await FirebaseAuth.instance.signOut();
    }
  }

  /// Two distinct safeguards before this irreversible action runs: a
  /// typed confirmation phrase (catches a misclick) and the Super
  /// Admin's own password re-entered (catches an unattended device) —
  /// see DataWipeService for what actually gets deleted and the one
  /// thing it *can't* delete (staff Firebase Auth logins themselves,
  /// no Admin SDK client-side; their access is stripped instead).
  Future<void> _showWipeDataDialog() async {
    final confirmController = TextEditingController();
    const confirmPhrase = 'DELETE ALL DATA';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Wipe All Data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes every business, ledger, product, party, and staff '
                "access grant — on this device and in Firestore. There's no undo. Staff "
                "logins themselves aren't deleted (that needs the Firebase Console), but "
                'they lose all access.',
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Type "$confirmPhrase" to continue:', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: confirmController,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.destructive),
              onPressed: confirmController.text == confirmPhrase ? () => Navigator.pop(context, true) : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    await _showPasswordReauthAndWipe();
  }

  Future<void> _showPasswordReauthAndWipe() async {
    final passwordController = TextEditingController();
    String? error;
    var submitting = false;

    final reauthed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirm Your Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: passwordController,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) {},
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(error!, style: const TextStyle(color: AppColors.destructive)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.destructive),
              onPressed: submitting
                  ? null
                  : () async {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user?.email == null) return;
                      setDialogState(() => submitting = true);
                      try {
                        await user!.reauthenticateWithCredential(
                          EmailAuthProvider.credential(email: user.email!, password: passwordController.text),
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
                  : const Text('Wipe Everything'),
            ),
          ],
        ),
      ),
    );

    if (reauthed != true || !mounted) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wiping all data...')));
    }
    try {
      final wipeService = await ref.read(dataWipeServiceProvider.future);
      await wipeService.wipeEverything();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Wipe failed: $e')));
      }
      return;
    }
    // Local data (and this user's own grants) are gone — sign out so
    // AuthGate/LoginScreen reloads from scratch rather than leaving the
    // shell rendered against a database that no longer matches it.
    await FirebaseAuth.instance.signOut();
  }

  static const _typeLabels = {
    BusinessType.sparePartsShop: 'Spare Parts Shop',
    BusinessType.fishery: 'Fishery',
    BusinessType.transport: 'Transport',
  };

  static const _typeIcons = {
    BusinessType.sparePartsShop: Icons.settings_suggest_outlined,
    BusinessType.fishery: Icons.sailing_outlined,
    BusinessType.transport: Icons.local_shipping_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(currentBusinessProvider);
    final profile = ref.watch(currentUserProfileProvider);
    final accessible = ref.watch(accessibleBusinessesProvider);

    if (profile.isLoading || accessible.isLoading || business.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final userProfile = profile.value;
    final isSuperAdmin = userProfile?.isSuperAdmin ?? false;

    if (business.hasError) {
      if (business.error is NoBusinessExistsException) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.business_outlined, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    isSuperAdmin
                        ? 'No business created yet.'
                        : 'No business has been set up yet.\nContact your administrator.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (isSuperAdmin)
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BusinessSwitcherScreen()),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Create Business'),
                    )
                  else
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
      return Scaffold(
        body: Center(child: Text('Failed to start: ${business.error}')),
      );
    }

    final activeBusiness = business.value!;
    final accessibleBusinesses = accessible.value ?? const [];

    if (!isSuperAdmin &&
        !accessibleBusinesses.any((b) => b.uuid == activeBusiness.uuid)) {
      if (accessibleBusinesses.isEmpty) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text(
                    'No business assigned yet.\nContact your administrator.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
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
      // Has access elsewhere, just not to whatever auto-selected here —
      // switch to the first business they're actually granted, on the
      // next frame (mutating provider state mid-build is unsafe).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedBusinessIdProvider.notifier).state =
            accessibleBusinesses.first.uuid;
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _buildShell(context, activeBusiness, userProfile, isSuperAdmin);
  }

  Widget _buildShell(BuildContext context, Business business, UserProfile? userProfile, bool isSuperAdmin) {
    final role = userProfile?.businessAccess[business.uuid];
    final destinations = _allDestinations
        .where((d) => d.appliesTo(business.type))
        .where((d) => _sectionVisibleForRole(d.section, role, isSuperAdmin))
        .toList();
    // The previously-selected index can point past the end (or at a
    // now-hidden screen) right after switching to a business of a
    // different type — fall back to Dashboard rather than crash.
    final selectedIndex = _selectedIndex < destinations.length
        ? _selectedIndex
        : 0;

    final groups = <AppSidebarGroup>[];
    String? currentSection;
    List<AppSidebarItem> currentItems = [];
    void flush() {
      if (currentItems.isNotEmpty) {
        groups.add(AppSidebarGroup(title: currentSection, items: currentItems));
      }
    }

    for (var i = 0; i < destinations.length; i++) {
      final d = destinations[i];
      if (d.section != currentSection) {
        flush();
        currentSection = d.section;
        currentItems = [];
      }
      currentItems.add(
        AppSidebarItem(
          icon: d.icon,
          label: d.label,
          selected: i == selectedIndex,
          onTap: () => setState(() => _selectedIndex = i),
        ),
      );
    }
    flush();

    return Scaffold(
      body: Row(
        children: [
          AppSidebar(
            header: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.business,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const Expanded(
                    child: Text(
                      'Business ERP',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  _NotificationBell(
                    onNavigate: (label) {
                      final index = destinations.indexWhere((d) => d.label == label);
                      if (index != -1) setState(() => _selectedIndex = index);
                    },
                  ),
                ],
              ),
            ),
            groups: groups,
            dangerZone: isSuperAdmin
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    child: TextButton.icon(
                      onPressed: _showWipeDataDialog,
                      icon: const Icon(Icons.delete_forever_outlined, size: 18, color: AppColors.destructive),
                      label: const Text('Wipe All Data', style: TextStyle(color: AppColors.destructive)),
                      style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                    ),
                  )
                : null,
            footer: InkWell(
              onTap: () => _showBusinessMenu(context),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      _typeIcons[business.type],
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            business.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _typeLabels[business.type] ?? '',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.unfold_more,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: destinations[selectedIndex].builder()),
        ],
      ),
    );
  }
}

/// Bell icon + unread-style badge in the sidebar header — the in-app
/// alternative to push notifications (FCM tokens are registered but
/// nothing ever sends through them without Cloud Functions). Tapping it
/// opens a dialog of everything `notificationCenterProvider` computed
/// (low stock, pending approvals, sync failures, conflicts); tapping an
/// item jumps to the relevant nav section via [onNavigate].
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell({required this.onNavigate});

  final void Function(String label) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationCenterProvider).value ?? const [];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, size: 20),
          tooltip: 'Notifications',
          onPressed: () => _showNotifications(context, notifications),
        ),
        if (notifications.isNotEmpty)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: AppColors.destructive, borderRadius: BorderRadius.circular(8)),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                '${notifications.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showNotifications(BuildContext context, List<NotificationItem> notifications) async {
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notifications'),
        content: SizedBox(
          width: 360,
          child: notifications.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text("You're all caught up."),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: notifications
                      .map((n) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(n.icon, color: n.color),
                            title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(n.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.pop(context, n.navIndexHint),
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
    if (label != null) onNavigate(label);
  }
}
