import '../../core/activity/trip_expense_repository.dart';
import 'vehicle_profitability_service.dart';
import 'trip_income_repository.dart';

/// Driver Performance = total TripIncome minus total TripExpense across
/// every trip one driver (a Party of type driver/captain, referenced by
/// Trip.captainUuid) has run — same shape as AssetProfitability, just
/// grouped by driver instead of by vehicle. See PHASES.md Section 6.
class DriverPerformanceService {
  DriverPerformanceService(this.tripIncome, this.tripExpenses);

  final TripIncomeRepository tripIncome;
  final TripExpenseRepository tripExpenses;

  Future<AssetProfitability> forDriver(String captainUuid) async {
    final revenue = await tripIncome.totalForDriver(captainUuid);
    final expense = await tripExpenses.totalForDriver(captainUuid);
    return AssetProfitability(revenueMinorUnits: revenue, expenseMinorUnits: expense);
  }
}
