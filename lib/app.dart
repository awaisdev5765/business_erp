import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/activity/trip.dart';
import 'core/asset/operating_asset.dart';
import 'core/identity/auth_gate.dart';
import 'core/party/party.dart';
import 'core/party/party_list_screen.dart';
import 'core/system/providers.dart';
import 'core/tenant/business.dart';
import 'features/accounting/approvals_screen.dart';
import 'features/accounting/audit_trail_screen.dart';
import 'features/accounting/bank_accounts_screen.dart';
import 'features/accounting/cash_book_screen.dart';
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
import 'features/sync/sync_status_screen.dart';
import 'features/tenant/business_switcher_screen.dart';
import 'features/tenant/cross_business_dashboard_screen.dart';
import 'features/transport/contracts_screen.dart';
import 'features/transport/driver_performance_screen.dart';

class BusinessErpApp extends StatelessWidget {
  const BusinessErpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Business ERP',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
      ),
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
    this.visibleFor,
  });

  final IconData icon;
  final String label;
  final Widget Function() builder;
  final Set<BusinessType>? visibleFor;

  bool appliesTo(BusinessType type) => visibleFor == null || visibleFor!.contains(type);
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
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
    _syncTimer = Timer.periodic(const Duration(minutes: 3), (_) => _backgroundSync());

    // Foreground messages don't show a system notification automatically
    // (only background/terminated does) — show an in-app SnackBar
    // instead. See FcmService's doc comment: nothing in this app sends
    // these yet without Cloud Functions; this just displays one if
    // something does (a manual Console-composed message, for instance).
    _fcmSubscription = FirebaseMessaging.onMessage.listen((message) {
      final text = message.notification?.title ?? message.notification?.body;
      if (text != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
    _Destination(icon: Icons.dashboard_outlined, label: 'Dashboard', builder: () => const DashboardScreen()),
    _Destination(
      icon: Icons.point_of_sale_outlined,
      label: 'Sales',
      visibleFor: const {BusinessType.sparePartsShop},
      builder: () => const SaleEntryScreen(),
    ),
    _Destination(
      icon: Icons.shopping_cart_outlined,
      label: 'Purchases',
      visibleFor: const {BusinessType.sparePartsShop},
      builder: () => const PurchaseEntryScreen(),
    ),
    _Destination(
      icon: Icons.inventory_2_outlined,
      label: 'Products',
      visibleFor: const {BusinessType.sparePartsShop},
      builder: () => const ProductListScreen(),
    ),
    _Destination(
      icon: Icons.people_outline,
      label: 'Customers',
      builder: () => const PartyListScreen(type: PartyType.customer),
    ),
    _Destination(
      icon: Icons.local_shipping_outlined,
      label: 'Suppliers',
      builder: () => const PartyListScreen(type: PartyType.supplier),
    ),
    _Destination(icon: Icons.account_balance_wallet_outlined, label: 'Cash Book', builder: () => const CashBookScreen()),
    _Destination(icon: Icons.balance_outlined, label: 'Trial Balance', builder: () => const TrialBalanceScreen()),
    _Destination(icon: Icons.trending_up_outlined, label: 'P&L', builder: () => const ProfitAndLossScreen()),
    _Destination(icon: Icons.history_outlined, label: 'Audit Trail', builder: () => const AuditTrailScreen()),
    _Destination(icon: Icons.account_balance_outlined, label: 'Bank Accounts', builder: () => const BankAccountsScreen()),
    _Destination(
      icon: Icons.directions_boat_outlined,
      label: 'Boats',
      visibleFor: const {BusinessType.fishery},
      builder: () => const AssetsScreen(assetType: OperatingAssetType.boat),
    ),
    _Destination(
      icon: Icons.groups_outlined,
      label: 'Crew',
      visibleFor: const {BusinessType.fishery},
      builder: () => CrewScreen(
        title: 'Captains & Crew',
        roles: const [PartyType.captain, PartyType.crew],
        roleLabels: const {PartyType.captain: 'Captain', PartyType.crew: 'Crew'},
      ),
    ),
    _Destination(
      icon: Icons.sailing_outlined,
      label: 'Fishing Trips',
      visibleFor: const {BusinessType.fishery},
      builder: () => const TripsScreen(tripType: TripType.fishery),
    ),
    _Destination(
      icon: Icons.local_shipping_outlined,
      label: 'Vehicles',
      visibleFor: const {BusinessType.transport},
      builder: () => const AssetsScreen(assetType: OperatingAssetType.vehicle),
    ),
    _Destination(
      icon: Icons.badge_outlined,
      label: 'Drivers',
      visibleFor: const {BusinessType.transport},
      builder: () => CrewScreen(
        title: 'Drivers',
        roles: const [PartyType.driver],
        roleLabels: const {PartyType.driver: 'Driver'},
        onTapPerson: (context, person) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DriverPerformanceScreen(driver: person)),
        ),
      ),
    ),
    _Destination(
      icon: Icons.description_outlined,
      label: 'Contracts',
      visibleFor: const {BusinessType.transport},
      builder: () => const ContractsScreen(),
    ),
    _Destination(
      icon: Icons.alt_route_outlined,
      label: 'Haul Trips',
      visibleFor: const {BusinessType.transport},
      builder: () => const TripsScreen(tripType: TripType.transport),
    ),
    _Destination(icon: Icons.sync_outlined, label: 'Sync Status', builder: () => const SyncStatusScreen()),
    _Destination(icon: Icons.precision_manufacturing_outlined, label: 'Fixed Assets', builder: () => const FixedAssetsScreen()),
    _Destination(icon: Icons.fact_check_outlined, label: 'Approvals', builder: () => const ApprovalsScreen()),
    _Destination(icon: Icons.dashboard_customize_outlined, label: 'All Businesses', builder: () => const CrossBusinessDashboardScreen()),
    _Destination(icon: Icons.payments_outlined, label: 'Payroll', builder: () => const PayrollScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(currentBusinessProvider);

    return business.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Failed to start: $e'))),
      data: (business) {
        final destinations = _allDestinations.where((d) => d.appliesTo(business.type)).toList();
        // The previously-selected index can point past the end (or at a
        // now-hidden screen) right after switching to a business of a
        // different type — fall back to Dashboard rather than crash.
        final selectedIndex = _selectedIndex < destinations.length ? _selectedIndex : 0;

        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: (i) => setState(() => _selectedIndex = i),
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      const Icon(Icons.business, size: 32),
                      const SizedBox(height: 8),
                      IconButton(
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        tooltip: 'Switch Business',
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const BusinessSwitcherScreen()),
                          );
                          // The new business's type may not have this
                          // many destinations — reset to Dashboard rather
                          // than risk a stale index.
                          if (mounted) setState(() => _selectedIndex = 0);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, size: 18),
                        tooltip: 'Sign out',
                        onPressed: () => FirebaseAuth.instance.signOut(),
                      ),
                    ],
                  ),
                ),
                destinations: destinations
                    .map((d) => NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)))
                    .toList(),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: destinations[selectedIndex].builder()),
            ],
          ),
        );
      },
    );
  }
}
