import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/party/party.dart';
import '../../features/spare_parts/inventory/product.dart';
import '../../features/spare_parts/sales/sale.dart';
import '../currency/currency.dart';

/// The two thermal roll widths every POS printer on the market actually
/// uses — there's no "other" option since a receipt sized for neither
/// just won't print correctly on real hardware.
enum ReceiptWidth { mm80, mm58 }

extension on ReceiptWidth {
  PdfPageFormat get pageFormat {
    final widthMm = this == ReceiptWidth.mm80 ? 80.0 : 58.0;
    // Roll paper has no fixed height — a large value plus
    // `pw.MultiPage` lets the renderer cut off at however much content
    // there actually is, the same way a real thermal printer just
    // stops and cuts.
    return PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: 3 * PdfPageFormat.mm,
    );
  }

  /// Slightly smaller everything on 58mm — there's a lot less room.
  double get baseFontSize => this == ReceiptWidth.mm80 ? 9 : 7.5;
}

/// Thermal receipt — narrow-roll layout (80mm/58mm), distinct from
/// InvoicePdf's full A4 invoice. Works identically across web/Android/
/// iOS/Windows since `printing` hands off to each platform's native
/// print/share sheet either way; the only difference here is the page
/// format passed in. Spare Parts' POS-style Sale screen is the primary
/// user of this (PHASES.md's original brief called for thermal receipt
/// support specifically there).
class ThermalReceiptPdf {
  static Future<void> printReceipt({
    required Sale sale,
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    Party? customer,
    required Map<String, Product> productsByUuid,
    String? currencyCode,
    required ReceiptWidth width,
  }) async {
    final doc = pw.Document();
    final fontSize = width.baseFontSize;
    final boldStyle = pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold);
    final normalStyle = pw.TextStyle(fontSize: fontSize);
    final smallStyle = pw.TextStyle(fontSize: fontSize - 1.5, color: PdfColors.grey700);

    doc.addPage(
      pw.Page(
        pageFormat: width.pageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(businessName, style: pw.TextStyle(fontSize: fontSize + 3, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
            if (businessAddress != null) pw.Text(businessAddress, style: smallStyle, textAlign: pw.TextAlign.center),
            if (businessPhone != null) pw.Text(businessPhone, style: smallStyle, textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 6),
            _dashedDivider(),
            pw.SizedBox(height: 4),
            _row('Receipt #', sale.documentNumber, normalStyle, boldStyle),
            _row('Date', _formatDateTime(sale.date), normalStyle, normalStyle),
            _row('Customer', customer?.name ?? 'Walk-in', normalStyle, normalStyle),
            _row('Payment', sale.paymentMethod.name, normalStyle, normalStyle),
            pw.SizedBox(height: 4),
            _dashedDivider(),
            pw.SizedBox(height: 4),
            for (final line in sale.lines) ...[
              pw.Text(productsByUuid[line.productUuid]?.name ?? line.productUuid, style: boldStyle),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('${line.quantity} x ${_money(line.unitPriceMinorUnits, currencyCode)}', style: smallStyle),
                  pw.Text(_money(line.lineTotalMinorUnits, currencyCode), style: normalStyle),
                ],
              ),
              pw.SizedBox(height: 3),
            ],
            _dashedDivider(),
            pw.SizedBox(height: 4),
            if (sale.totalTaxMinorUnits > 0 || sale.discountMinorUnits > 0)
              _row('Subtotal', _money(sale.totalMinorUnits, currencyCode), normalStyle, normalStyle),
            if (sale.totalTaxMinorUnits > 0) _row('Tax', _money(sale.totalTaxMinorUnits, currencyCode), normalStyle, normalStyle),
            if (sale.discountMinorUnits > 0)
              _row('Discount', '-${_money(sale.discountMinorUnits, currencyCode)}', normalStyle, normalStyle),
            pw.SizedBox(height: 2),
            _row('TOTAL', _money(sale.netAmountDueMinorUnits, currencyCode), boldStyle, pw.TextStyle(fontSize: fontSize + 2, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Text('Thank you!', style: normalStyle),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => doc.save(), format: width.pageFormat);
  }

  static pw.Widget _dashedDivider() => pw.Container(height: 0.6, color: PdfColors.grey600, width: double.infinity);

  static pw.Widget _row(String label, String value, pw.TextStyle labelStyle, pw.TextStyle valueStyle) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: labelStyle),
          pw.Text(value, style: valueStyle),
        ],
      );
}

String _money(int minorUnits, String? currencyCode) => formatMoney(minorUnits, currencyCode);

String _formatDateTime(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
