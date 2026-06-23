import '../../core/activity/trip_expense_repository.dart';
import 'trip_income_repository.dart';

class AssetProfitability {
  AssetProfitability({required this.revenueMinorUnits, required this.expenseMinorUnits});

  final int revenueMinorUnits;
  final int expenseMinorUnits;

  int get profitMinorUnits => revenueMinorUnits - expenseMinorUnits;
}

/// Vehicle Profitability = total TripIncome minus total TripExpense
/// across *every* trip a vehicle has ever run — the per-asset rollup,
/// as distinct from a single trip's profit. See PHASES.md Section 6.
class VehicleProfitabilityService {
  VehicleProfitabilityService(this.tripIncome, this.tripExpenses);

  final TripIncomeRepository tripIncome;
  final TripExpenseRepository tripExpenses;

  Future<AssetProfitability> forAsset(String assetUuid) async {
    final revenue = await tripIncome.totalForAsset(assetUuid);
    final expense = await tripExpenses.totalForAsset(assetUuid);
    return AssetProfitability(revenueMinorUnits: revenue, expenseMinorUnits: expense);
  }
}
