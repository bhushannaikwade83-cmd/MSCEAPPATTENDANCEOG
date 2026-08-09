import 'package:pdf/widgets.dart' as pw;

import '../models/attendance_data.dart';
import 'pdf_theme.dart';

/// "Summary" block from the printed form: a navy underlined heading followed
/// by `Label : ____value____` rows. Rendered on the last page only.
class ReportSummary {
  ReportSummary._();

  static pw.Widget build({
    required pw.Font regular,
    required pw.Font bold,
    required AttendanceSummary summary,
  }) {
    final List<List<String>> rows = <List<String>>[
      <String>['Total Present Days', '${summary.totalPresent}'],
      <String>['Total Absent Days', '${summary.totalAbsent}'],
      <String>['Total Late Days', '${summary.totalLate}'],
      <String>['Attendance Percentage', summary.percentageLabel],
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 3),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfTheme.darkBlue, width: 1),
            ),
          ),
          child: pw.Text('Summary', style: PdfTheme.sectionTitle(bold)),
        ),
        PdfTheme.gap(PdfTheme.space8),
        for (final List<String> r in rows) _row(bold, regular, r[0], r[1]),
      ],
    );
  }

  static pw.Widget _row(
    pw.Font bold,
    pw.Font regular,
    String label,
    String value,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: <pw.Widget>[
          pw.SizedBox(
            width: 152,
            child: pw.Text(label, style: PdfTheme.fieldLabel(bold)),
          ),
          pw.Text(':', style: PdfTheme.fieldLabel(bold)),
          PdfTheme.hGap(PdfTheme.space8),
          pw.Container(
            width: 90,
            padding: const pw.EdgeInsets.only(left: 4, bottom: 1.5),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfTheme.blue, width: 0.7),
              ),
            ),
            child: pw.Text(value, style: PdfTheme.fieldValue(regular)),
          ),
        ],
      ),
    );
  }
}
