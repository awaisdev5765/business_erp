import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'account.dart';

const _uuid = Uuid();

/// Standard 5-type seed template. See PHASES.md Section 11.
/// (code, name, type)
const List<(String, String, AccountType)> _seedAccounts = [
  ('1010', 'Cash on Hand', AccountType.asset),
  ('1020', 'Bank Accounts', AccountType.asset),
  ('1030', 'Accounts Receivable', AccountType.asset),
  ('1040', 'Inventory', AccountType.asset),
  ('1050', 'Fixed Assets', AccountType.asset),
  ('2010', 'Accounts Payable', AccountType.liability),
  ('2020', 'Tax Payable', AccountType.liability),
  ('3010', "Owner's Capital", AccountType.equity),
  ('3020', 'Retained Earnings', AccountType.equity),
  ('4010', 'Sales Income', AccountType.income),
  ('4020', 'Trip/Catch Income', AccountType.income),
  ('4030', 'Other Income', AccountType.income),
  ('5010', 'Cost of Goods Sold', AccountType.expense),
  ('5020', 'Fuel Expense', AccountType.expense),
  ('5030', 'Maintenance Expense', AccountType.expense),
  ('5040', 'Ice Expense', AccountType.expense),
  ('5045', 'Food Expense', AccountType.expense),
  ('5050', 'Other Operating Expense', AccountType.expense),
  ('5060', 'Repair Expense', AccountType.expense),
  ('5070', 'Tyre Expense', AccountType.expense),
  ('5080', 'Oil Change Expense', AccountType.expense),
];

Future<void> seedChartOfAccounts(Database db, String businessId) async {
  final existing = await db.query(
    Account.tableName,
    where: 'business_id = ?',
    whereArgs: [businessId],
    limit: 1,
  );
  if (existing.isNotEmpty) return;

  final now = DateTime.now();
  await db.transaction((txn) async {
    for (final seed in _seedAccounts) {
      final account = Account(
        uuid: _uuid.v4(),
        businessId: businessId,
        code: seed.$1,
        name: seed.$2,
        type: seed.$3,
        isSystemAccount: true,
        createdAt: now,
        updatedAt: now,
      );
      await txn.insert(Account.tableName, account.toMap());
    }
  });
}
