import 'package:intl/intl.dart';

/// One currency a Super Admin can pick for a business — see
/// Business.baseCurrency (existed in the schema since Phase 2 as a
/// nullable field, documented as "single-currency for MVP," but never
/// actually settable or used in any money display until now).
class CurrencyOption {
  const CurrencyOption(this.code, this.symbol, this.name);
  final String code;
  final String symbol;
  final String name;
}

/// Common currencies across this app's actual deployments — not every
/// ISO 4217 code, just enough to cover likely businesses. "Other" isn't
/// offered: a business needing a code not listed here can be added
/// rather than accepting an unknown currency silently.
const kCurrencyOptions = [
  CurrencyOption('USD', r'$', 'US Dollar'),
  CurrencyOption('GBP', '£', 'British Pound'),
  CurrencyOption('EUR', '€', 'Euro'),
  CurrencyOption('PKR', 'Rs', 'Pakistani Rupee'),
  CurrencyOption('INR', '₹', 'Indian Rupee'),
  CurrencyOption('AED', 'د.إ', 'UAE Dirham'),
  CurrencyOption('SAR', 'ر.س', 'Saudi Riyal'),
  CurrencyOption('BHD', '.د.ب', 'Bahraini Dinar'),
  CurrencyOption('KWD', 'د.ك', 'Kuwaiti Dinar'),
  CurrencyOption('QAR', 'ر.ق', 'Qatari Riyal'),
  CurrencyOption('CAD', r'$', 'Canadian Dollar'),
  CurrencyOption('AUD', r'$', 'Australian Dollar'),
  CurrencyOption('LKR', 'Rs', 'Sri Lankan Rupee'),
  CurrencyOption('BDT', '৳', 'Bangladeshi Taka'),
  CurrencyOption('NGN', '₦', 'Nigerian Naira'),
];

const kDefaultCurrencyCode = 'USD';

String currencySymbolFor(String? code) {
  return kCurrencyOptions.firstWhere((c) => c.code == code, orElse: () => kCurrencyOptions.first).symbol;
}

/// Formats minor units (cents/paisa/fils — this app's universal storage
/// unit, see PHASES.md Section 14) as "{symbol}{grouped amount}", e.g.
/// "$1,234.50" or "Rs 1,234.50". [currencyCode] is the active business's
/// `baseCurrency`; falls back to [kDefaultCurrencyCode] if unset
/// (businesses created before this existed, or any not yet assigned
/// one by the Super Admin).
String formatMoney(int minorUnits, String? currencyCode) {
  final symbol = currencySymbolFor(currencyCode ?? kDefaultCurrencyCode);
  final format = NumberFormat.currency(symbol: symbol, decimalDigits: 2);
  return format.format(minorUnits / 100);
}
