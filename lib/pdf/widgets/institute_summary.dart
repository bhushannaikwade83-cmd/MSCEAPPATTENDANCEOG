import 'package:pdf/widgets.dart' as pw;
import '../models/institute_report_data.dart';
import 'pdf_theme.dart';

class InstituteSummarySection {
  static pw.Widget build({
    required pw.Font regular,
    required pw.Font bold,
    required InstituteSummary summary,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'Summary',
          style: pw.TextStyle(
            font: bold,
            fontSize: 11,
            color: PdfTheme.darkBlue,
            letterSpacing: 0.5,
          ),
        ),
        PdfTheme.gap(PdfTheme.space6),
        pw.Container(
          padding: PdfTheme.boxPadding,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfTheme.border, width: 0.5),
            borderRadius: PdfTheme.roundedMd,
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildSummaryCard(
                    label: 'Total Students',
                    value: '${summary.totalStudents}',
                    regular: regular,
                    bold: bold,
                  ),
                  _buildSummaryCard(
                    label: 'Total Present',
                    value: '${summary.totalPresent}',
                    regular: regular,
                    bold: bold,
                  ),
                  _buildSummaryCard(
                    label: 'Total Absent',
                    value: '${summary.totalAbsent}',
                    regular: regular,
                    bold: bold,
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildSummaryCard(
                    label: 'Total Hours',
                    value: summary.totalHours,
                    regular: regular,
                    bold: bold,
                  ),
                  _buildSummaryCard(
                    label: 'Avg Attendance %',
                    value: '${summary.averageAttendancePercent.toStringAsFixed(1)}%',
                    regular: regular,
                    bold: bold,
                  ),
                  pw.Expanded(child: pw.SizedBox()),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryCard({
    required String label,
    required String value,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: regular,
              fontSize: 8,
              color: PdfTheme.grey,
              letterSpacing: 0.3,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: bold,
              fontSize: 11,
              color: PdfTheme.darkBlue,
            ),
          ),
        ],
      ),
    );
  }
}
