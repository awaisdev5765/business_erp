import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'expense.dart';
import 'journal_entry.dart';
import 'ledger_repository.dart';

const _uuid = Uuid();

class ExpenseRepository {
  ExpenseRepository(this.db, this.ledger);

  final Database db;
  final LedgerRepository ledger;

  Future<Expense> create({
    required String businessId,
    required String accountCode,
    required int amountMinorUnits,
    String? description,
    ExpensePaymentMethod method = ExpensePaymentMethod.cash,
    required String createdBy,
    required String deviceId,
    DateTime? date,
  }) async {
    if (amountMinorUnits <= 0) {
      throw ArgumentError('Expense amount must be positive');
    }

    final expense = Expense(
      uuid: _uuid.v4(),
      businessId: businessId,
      accountCode: accountCode,
      amountMinorUnits: amountMinorUnits,
      description: description,
      method: method,
      date: date ?? DateTime.now(),
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );

    await db.transaction((txn) async {
      await txn.insert(Expense.tableName, expense.toMap());

      // Bank transfer/cheque/card payments come out of the bank
      // account (1020) rather than cash on hand — everything else
      // (cash, other) hits Cash on Hand (1010), same convention as
      // Payment/Sale elsewhere in this app.
      final isBank = method == ExpensePaymentMethod.bankTransfer || method == ExpensePaymentMethod.cheque;
      await ledger.postWithin(
        txn,
        businessId: businessId,
        sourceType: 'Expense',
        sourceId: expense.uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        date: expense.date,
        description: description == null ? 'Expense (${method.name})' : 'Expense — $description (${method.name})',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: accountCode,
            debitMinorUnits: amountMinorUnits,
            creditMinorUnits: 0,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: isBank ? '1020' : '1010',
            debitMinorUnits: 0,
            creditMinorUnits: amountMinorUnits,
          ),
        ],
      );
    });

    return expense;
  }

  Future<List<Expense>> list({required String businessId}) async {
    final rows = await db.query(
      Expense.tableName,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'date DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }
}
