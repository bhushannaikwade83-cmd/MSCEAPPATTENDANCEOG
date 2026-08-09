import 'package:pdf/widgets.dart' as pw;

import '../models/attendance_data.dart';
import 'pdf_theme.dart';

/// Repeating page header, matching the printed template:
/// logo + motto on the left, two-line council name in navy on the right,
/// an orange divider with a centre diamond, then the navy title pill.
class ReportHeader {
  ReportHeader._();

  static pw.Widget build({
    required pw.Font regular,
    required pw.Font bold,
    required pw.Font devanagari,
    required AttendanceReportData data,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            _logo(data, devanagari),
            PdfTheme.hGap(PdfTheme.space12),
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Text(
                  'MAHARASHTRA STATE COUNCIL\nOF EXAMINATION',
                  textAlign: pw.TextAlign.center,
                  style: PdfTheme.councilName(bold),
                ),
              ),
            ),
          ],
        ),
        PdfTheme.gap(PdfTheme.space8),
        _diamondDivider(),
        PdfTheme.gap(PdfTheme.space12),
        pw.Center(child: _titlePill(bold)),
        PdfTheme.gap(PdfTheme.space16),
      ],
    );
  }

  /// Council logo with the Devanagari motto underneath, as printed.
  static pw.Widget _logo(AttendanceReportData data, pw.Font devanagari) {
    return pw.Column(
      children: <pw.Widget>[
        pw.Container(
          width: 74,
          height: 62,
          alignment: pw.Alignment.center,
          child: data.logoBytes == null
              ? pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfTheme.border, width: 0.8),
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text('LOGO',
                      style: pw.TextStyle(fontSize: 7, color: PdfTheme.grey)),
                )
              : pw.Image(
                  pw.MemoryImage(data.logoBytes!),
                  fit: pw.BoxFit.contain,
                ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          PdfTheme.motto,
          style: pw.TextStyle(
            font: devanagari,
            fontSize: 8.5,
            color: PdfTheme.black,
          ),
        ),
      ],
    );
  }

  /// Thin orange rule broken by a small orange diamond in the middle.
  static pw.Widget _diamondDivider() {
    return pw.SizedBox(
      height: 8,
      child: pw.Stack(
        alignment: pw.Alignment.center,
        children: <pw.Widget>[
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 60),
            height: 1.4,
            color: PdfTheme.orange,
          ),
          pw.Container(
            width: 26,
            alignment: pw.Alignment.center,
            color: PdfTheme.white,
            child: pw.Transform.rotate(
              angle: 0.7853981634, // 45 degrees
              child: pw.Container(width: 6, height: 6, color: PdfTheme.orange),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _titlePill(pw.Font bold) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 34, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfTheme.darkBlue,
        borderRadius: PdfTheme.roundedSm,
      ),
      child: pw.Text('ATTENDANCE REPORT', style: PdfTheme.bannerTitle(bold)),
    );
  }
}
