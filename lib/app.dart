import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/activity/trip.dart';
import 'core/asset/operating_asset.dart';
import 'core/party/party.dart';
import 'core/party/party_list_screen.dart';
import 'core/system/providers.dart';
import 'features/accounting/audit_trail_screen.dart';
import 'features/accounting/bank_accounts_screen.dart';
import 'features/accounting/cash_book_screen.dart';
import 'features/accounting/profit_and_loss_screen.dart';
import 'features/accounting/trial_balance_screen.dart';
import 'features/activity/assets_screen.dart';
import 'features/activity/crew_screen.dart';
import 'features/activity/trips_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/spare_parts/inventory/product_list_screen.dart';
import 'features/spare_parts/purchases/purchase_entry_screen.dart';
import 'features/spare_parts/sales/sale_entry_screen.dart';
import 'features/sync/sync_status_screen.dart';
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
      home: const _AppShell(),
    );
  }
}

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    (icon: Icons.dashboard_outlined, label: 'Dashboard'),
    (icon: Icons.point_of_sale_outlined, label: 'Sales'),
    (icon: Icons.shopping_cart_outlined, label: 'Purchases'),
    (icon: Icons.inventory_2_outlined, label: 'Products'),
    (icon: Icons.people_outline, label: 'Customers'),
    (icon: Icons.local_shipping_outlined, label: 'Suppliers'),
    (icon: Icons.account_balance_wallet_outlined, label: 'Cash Book'),
    (icon: Icons.balance_outlined, label: 'Trial Balance'),
    (icon: Icons.trending_up_outlined, label: 'P&L'),
    (icon: Icons.history_outlined, label: 'Audit Trail'),
    (icon: Icons.account_balance_outlined, label: 'Bank Accounts'),
    (icon: Icons.directions_boat_outlined, label: 'Boats'),
    (icon: Icons.groups_outlined, label: 'Crew'),
    (icon: Icons.sailing_outlined, label: 'Fishing Trips'),
    (icon: Icons.local_shipping_outlined, label: 'Vehicles'),
    (icon: Icons.badge_outlined, label: 'Drivers'),
    (icon: Icons.description_outlined, label: 'Contracts'),
    (icon: Icons.alt_route_outlined, label: 'Haul Trips'),
    (icon: Icons.sync_outlined, label: 'Sync Status'),
  ];

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const SaleEntryScreen();
      case 2:
        return const PurchaseEntryScreen();
      case 3:
        return const ProductListScreen();
      case 4:
        return const PartyListScreen(type: PartyType.customer);
      case 5:
        return const PartyListScreen(type: PartyType.supplier);
      case 6:
        return const CashBookScreen();
      case 7:
        return const TrialBalanceScreen();
      case 8:
        return const ProfitAndLossScreen();
      case 9:
        return const AuditTrailScreen();
      case 10:
        return const BankAccountsScreen();
      case 11:
        return const AssetsScreen(assetType: OperatingAssetType.boat);
      case 12:
        return CrewScreen(
          title: 'Captains & Crew',
          roles: const [PartyType.captain, PartyType.crew],
          roleLabels: const {PartyType.captain: 'Captain', PartyType.crew: 'Crew'},
        );
      case 13:
        return const TripsScreen(tripType: TripType.fishery);
      case 14:
        return const AssetsScreen(assetType: OperatingAssetType.vehicle);
      case 15:
        return CrewScreen(
          title: 'Drivers',
          roles: const [PartyType.driver],
          roleLabels: const {PartyType.driver: 'Driver'},
          onTapPerson: (context, person) => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DriverPerformanceScreen(driver: person)),
          ),
        );
      case 16:
        return const ContractsScreen();
      case 17:
        return const TripsScreen(tripType: TripType.transport);
      case 18:
        return const SyncStatusScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessId = ref.watch(currentBusinessIdProvider);

    return businessId.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Failed to start: $e'))),
      data: (_) => Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Icon(Icons.business, size: 32),
              ),
              destinations: _destinations
                  .map((d) => NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}
