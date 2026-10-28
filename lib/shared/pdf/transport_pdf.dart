import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../features/transport/vehicle_khata_line.dart';
import '../../features/transport/weight_entry.dart';

class TransportPdf {
  static Future<void> printGariKhata({
    required String businessName,
    required String vehicleLabel,
    required List<VehicleKhataRow> rows,
    required String Function(int) money,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(businessName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('Gari Khata — $vehicleLabel', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(width: 0.4),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.2),
              1: pw.FlexColumnWidth(2.4),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(1.2),
              4: pw.FlexColumnWidth(1.3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _h('Date'),
                  _h('Tafseel'),
                  _h('Kharcha'),
                  _h('Jama'),
                  _h('Total'),
                ],
              ),
              for (final row in rows)
                pw.TableRow(children: [
                  _c(_d(row.line.date)),
                  _c(row.line.tafseel),
                  _c(row.line.kharchaMinorUnits > 0 ? money(row.line.kharchaMinorUnits) : ''),
                  _c(row.line.jamaMinorUnits > 0 ? money(row.line.jamaMinorUnits) : ''),
                  _c(money(row.runningBalanceMinorUnits)),
                ]),
            ],
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  static Future<void> printMonthBill({
    required String businessName,
    required String companyName,
    required int year,
    required int month,
    required int ratePerTonMinorUnits,
    required double totalWeightKg,
    required int amountMinorUnits,
    required List<WeightEntry> entries,
    required String Function(String vehicleUuid) vehicleLabel,
    required String Function(int) money,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(businessName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('Company Bill — $companyName'),
          pw.Text('Month: ${month.toString().padLeft(2, '0')}/$year'),
          pw.SizedBox(height: 8),
          pw.Text('Rate: ${money(ratePerTonMinorUnits)} / ton'),
          pw.Text('Total weight: ${_kg(totalWeightKg)} kg'),
          pw.Text('Bill: ${money(amountMinorUnits)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(width: 0.4),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.6),
              1: pw.FlexColumnWidth(1.2),
              2: pw.FlexColumnWidth(1.4),
              3: pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [_h('Sr'), _h('Date'), _h('Vehicle'), _h('Weight')],
              ),
              for (var i = 0; i < entries.length; i++)
                pw.TableRow(children: [
                  _c('${i + 1}'),
                  _c(_d(entries[i].date)),
                  _c(vehicleLabel(entries[i].vehicleUuid)),
                  _c('${_kg(entries[i].weightKg)} kg'),
                ]),
            ],
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  static pw.Widget _h(String t) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
      );

  static pw.Widget _c(String t) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(t, style: const pw.TextStyle(fontSize: 9)),
      );

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _kg(double kg) => kg == kg.roundToDouble() ? '${kg.round()}' : kg.toStringAsFixed(1);
}
