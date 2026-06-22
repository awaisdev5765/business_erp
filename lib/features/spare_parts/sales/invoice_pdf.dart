import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/party/party.dart';
import '../inventory/product.dart';
import 'sale.dart';

/// Renders a Sale as a PDF invoice and hands it to the OS print/share
/// sheet via `printing`. Per PHASES.md Section 17 ("Reporting
/// Architecture") this should eventually run through a shared Cloud
/// Function template so Desktop/Web/Mobile render identically — this
/// client-side version is the Phase 1 placeholder.
class InvoicePdf {
  static Future<void> printInvoice({
    required Sale sale,
    required String businessName,
    Party? customer,
    required Map<String, Product> productsByUuid,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(businessName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('INVOICE ${sale.documentNumber}'),
            pw.Text('Date: ${_formatDate(sale.date)}'),
            pw.Text('Customer: ${customer?.name ?? 'Walk-in'}'),
            pw.Text('Payment: ${sale.paymentMethod.name}'),
            pw.SizedBox(height: 16),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.5),
                3: pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _cell('Product', bold: true),
                    _cell('Qty', bold: true),
                    _cell('Unit Price', bold: true),
                    _cell('Total', bold: true),
                  ],
                ),
                for (final line in sale.lines)
                  pw.TableRow(
                    children: [
                      _cell(productsByUuid[line.productUuid]?.name ?? line.productUuid),
                      _cell('${line.quantity}'),
                      _cell(_money(line.unitPriceMinorUnits)),
                      _cell(_money(line.lineTotalMinorUnits)),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total: ${_money(sale.totalMinorUnits)}',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
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
