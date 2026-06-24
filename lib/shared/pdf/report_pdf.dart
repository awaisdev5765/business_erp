import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// PDF export for Trial Balance and P&L — same client-side
/// `printing`/`pdf` approach as InvoicePdf (PHASES.md Section 17's
/// "should eventually run through a shared template" placeholder
/// applies here too). Previously these two reports had no export at
/// all, unlike Sales invoices.
class ReportPdf {
  static Future<void> printTrialBalance({
    required String businessName,
    required List<({String code, String name, String type, int debit, int credit})> rows,
    required int totalDebit,
    required int totalCredit,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(businessName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('Trial Balance — as of ${_formatDate(DateTime.now())}'),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1.5),
              2: pw.FlexColumnWidth(1.5),
              3: pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _cell('Account', bold: true),
                  _cell('Type', bold: true),
                  _cell('Debit', bold: true),
                  _cell('Credit', bold: true),
                ],
              ),
              for (final r in rows)
                pw.TableRow(children: [
                  _cell('${r.code}  ${r.name}'),
                  _cell(r.type.toUpperCase()),
                  _cell(r.debit == 0 ? '—' : _money(r.debit)),
                  _cell(r.credit == 0 ? '—' : _money(r.credit)),
                ]),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Total Debit: ${_money(totalDebit)}    '),
              pw.Text('Total Credit: ${_money(totalCredit)}'),
            ],
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }

  static Future<void> printProfitAndLoss({
    required String businessName,
    required List<(String, int)> incomeRows,
    required int totalIncome,
    required List<(String, int)> expenseRows,
    required int totalExpense,
    DateTime? from,
    DateTime? to,
  }) async {
    final netProfit = totalIncome - totalExpense;
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(businessName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('Profit & Loss'),
          pw.Text(
            from == null && to == null
                ? 'All time'
                : 'From ${from != null ? _formatDate(from) : 'the beginning'} to ${to != null ? _formatDate(to) : 'now'}',
          ),
          pw.SizedBox(height: 16),
          pw.Text('Income', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          for (final r in incomeRows)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [pw.Text(r.$1), pw.Text(_money(r.$2))],
            ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Income', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(_money(totalIncome), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text('Expenses', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          for (final r in expenseRows)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [pw.Text(r.$1), pw.Text(_money(r.$2))],
            ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Expenses', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(_money(totalExpense), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(netProfit >= 0 ? 'Net Profit' : 'Net Loss', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text(_money(netProfit.abs()), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text, style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
      );
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
