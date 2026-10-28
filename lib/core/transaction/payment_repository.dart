import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../accounting/journal_entry.dart';
import '../accounting/ledger_repository.dart';
import '../sync/sync_queue_item.dart';
import '../sync/sync_queue_repository.dart';
import '../system/number_sequence_service.dart';
import 'payment.dart';

const _uuid = Uuid();

class PaymentRepository {
  PaymentRepository(this.db, this.ledger, this.numbering, [this.syncQueue]);

  final Database db;
  final LedgerRepository ledger;
  final NumberSequenceService numbering;
  final SyncQueueRepository? syncQueue;

  Future<Payment> record({
    required String businessId,
    required String partyUuid,
    required PaymentDirection direction,
    required int amountMinorUnits,
    required String createdBy,
    required String deviceId,
    PaymentSettlementMethod method = PaymentSettlementMethod.cash,
    String? note,
    DateTime? date,
  }) async {
    if (amountMinorUnits <= 0) {
      throw ArgumentError('Payment amount must be positive');
    }

    final docType =
        direction == PaymentDirection.receiveFromCustomer ? DocType.paymentIn : DocType.paymentOut;
    final documentNumber = await numbering.next(businessId: businessId, docType: docType);
    final uuid = _uuid.v4();
    final paymentDate = date ?? DateTime.now();

    final payment = Payment(
      uuid: uuid,
      businessId: businessId,
      documentNumber: documentNumber,
      partyUuid: partyUuid,
      direction: direction,
      amountMinorUnits: amountMinorUnits,
      method: method,
      note: note,
      date: paymentDate,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );

    await db.transaction((txn) async {
      await txn.insert(Payment.tableName, payment.toMap());
      if (syncQueue != null) {
        await syncQueue!.enqueue(
          txn,
          businessId: businessId,
          entityType: 'Payment',
          entityId: uuid,
          operation: SyncOperation.create,
        );
      }

      final isReceipt = direction == PaymentDirection.receiveFromCustomer;
      await ledger.postWithin(
        txn,
        businessId: businessId,
        sourceType: 'Payment',
        sourceId: uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        date: paymentDate,
        description: 'Payment $documentNumber (${method.name}${note != null ? ' — $note' : ''})',
        rawLines: [
          JournalLine(
            entryUuid: '',
            // Receipt: cash comes in. Payout: cash goes out — credit cash.
            accountCode: '1010',
            debitMinorUnits: isReceipt ? amountMinorUnits : 0,
            creditMinorUnits: isReceipt ? 0 : amountMinorUnits,
          ),
          JournalLine(
            entryUuid: '',
            // Receipt: reduces what the customer owes (credit receivable).
            // Payout: reduces what we owe the supplier (debit payable).
            accountCode: isReceipt ? '1030' : '2010',
            debitMinorUnits: isReceipt ? 0 : amountMinorUnits,
            creditMinorUnits: isReceipt ? amountMinorUnits : 0,
            partyUuid: partyUuid,
          ),
        ],
      );
    });

    return payment;
  }

  Future<List<Payment>> list({required String businessId}) async {
    final rows = await db.query(
      Payment.tableName,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'date DESC',
    );
    return rows.map(Payment.fromMap).toList();
  }
}
