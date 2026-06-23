import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../accounting/journal_entry.dart';
import '../accounting/ledger_repository.dart';
import 'salary_record.dart';

const _uuid = Uuid();

/// Pays a [SalaryRecord]'s monthly amount: posts Dr Salary Expense(5100)
/// / Cr Cash(1010), tagged to the employee as the journal line's
/// `partyUuid` so it surfaces in their Party Ledger statement of account
/// — same reuse of the ledger-as-sub-ledger-view pattern as everywhere
/// else (PHASES.md Section 11).
class SalaryRepository {
  SalaryRepository(this.db, this.ledger);

  final Database db;
  final LedgerRepository ledger;

  Future<SalaryRecord> createRecord({
    required String businessId,
    required String partyUuid,
    required int amountMinorUnits,
    DateTime? startDate,
  }) async {
    final record = SalaryRecord(
      uuid: _uuid.v4(),
      businessId: businessId,
      partyUuid: partyUuid,
      amountMinorUnits: amountMinorUnits,
      startDate: startDate ?? DateTime.now(),
    );
    await db.insert(SalaryRecord.tableName, record.toMap());
    return record;
  }

  Future<List<SalaryRecord>> listRecords({required String businessId}) async {
    final rows = await db.query(
      SalaryRecord.tableName,
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
    );
    return rows.map(SalaryRecord.fromMap).toList();
  }

  Future<List<SalaryPayment>> paymentHistory(String salaryRecordUuid) async {
    final rows = await db.query(
      SalaryPayment.tableName,
      where: 'salary_record_uuid = ?',
      whereArgs: [salaryRecordUuid],
      orderBy: 'period ASC',
    );
    return rows.map(SalaryPayment.fromMap).toList();
  }

  /// [period] is "YYYY-MM". Throws if this record already has a payment
  /// for that period.
  Future<SalaryPayment> paySalary({
    required SalaryRecord record,
    required String period,
    required String createdBy,
    required String deviceId,
  }) async {
    final history = await paymentHistory(record.uuid);
    if (history.any((p) => p.period == period)) {
      throw StateError('Salary for $period already paid for this record');
    }

    final payment = SalaryPayment(
      uuid: _uuid.v4(),
      salaryRecordUuid: record.uuid,
      businessId: record.businessId,
      period: period,
      amountMinorUnits: record.amountMinorUnits,
      paidAt: DateTime.now(),
    );

    await db.transaction((txn) async {
      await txn.insert(SalaryPayment.tableName, payment.toMap());

      await ledger.postWithin(
        txn,
        businessId: record.businessId,
        sourceType: 'SalaryPayment',
        sourceId: payment.uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        description: 'Salary $period',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: '5100', // Salary Expense
            debitMinorUnits: record.amountMinorUnits,
            creditMinorUnits: 0,
            partyUuid: record.partyUuid,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: '1010', // Cash on Hand
            debitMinorUnits: 0,
            creditMinorUnits: record.amountMinorUnits,
          ),
        ],
      );
    });

    return payment;
  }
}
