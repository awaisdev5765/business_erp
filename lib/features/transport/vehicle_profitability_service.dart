import 'trip_income_repository.dart';
import 'vehicle_khata_repository.dart';

class AssetProfitability {
  AssetProfitability({required this.revenueMinorUnits, required this.expenseMinorUnits});

  final int revenueMinorUnits;
  final int expenseMinorUnits;

  int get profitMinorUnits => revenueMinorUnits - expenseMinorUnits;
}

/// Gari khata profit = jama − kharcha (opening baqaya excluded).
/// Old TripIncome is still counted so pre-khata data does not vanish.
class VehicleProfitabilityService {
  VehicleProfitabilityService(this.tripIncome, this.khata);

  final TripIncomeRepository tripIncome;
  final VehicleKhataRepository khata;

  Future<AssetProfitability> forAsset(String assetUuid) async {
    final oldRevenue = await tripIncome.totalForAsset(assetUuid);
    final jama = await khata.totalJama(assetUuid);
    final kharcha = await khata.totalKharcha(assetUuid);
    return AssetProfitability(
      revenueMinorUnits: oldRevenue + jama,
      expenseMinorUnits: kharcha,
    );
  }
}
