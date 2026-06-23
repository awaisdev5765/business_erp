import '../../core/activity/trip_expense_repository.dart';
import 'fish_sale_repository.dart';

class TripProfit {
  TripProfit({required this.revenueMinorUnits, required this.expenseMinorUnits});

  final int revenueMinorUnits;
  final int expenseMinorUnits;

  int get profitMinorUnits => revenueMinorUnits - expenseMinorUnits;
}

/// Trip Profit = catch sale revenue minus trip expenses (fuel/ice/food/
/// maintenance). No COGS — the catch has no purchase cost, only the
/// operating expenses already posted via TripExpense. See PHASES.md
/// Section 6 and FishSale's doc comment.
class TripProfitService {
  TripProfitService(this.fishSales, this.tripExpenses);

  final FishSaleRepository fishSales;
  final TripExpenseRepository tripExpenses;

  Future<TripProfit> forTrip(String tripUuid) async {
    final revenue = await fishSales.totalForTrip(tripUuid);
    final expense = await tripExpenses.totalForTrip(tripUuid);
    return TripProfit(revenueMinorUnits: revenue, expenseMinorUnits: expense);
  }
}
