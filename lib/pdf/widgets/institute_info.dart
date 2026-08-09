import 'package:pdf/widgets.dart' as pw;
import '../models/institute_report_data.dart';
import 'pdf_theme.dart';

class InstituteInfoSection {
  static pw.Widget build({
    required pw.Font regular,
    required pw.Font bold,
    required InstituteInfo institute,
    required String reportPeriod,
    int totalStudents = 0,
  }) {
    return pw.Container(
      padding: pw.EdgeInsets.all(PdfTheme.space16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfTheme.darkBlue, width: 0.5),
        borderRadius: PdfTheme.roundedMd,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Row 1: Institute ID and Institute Name
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 80,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'INSTITUTE ID',
                      style: pw.TextStyle(
                        font: regular,
                        fontSize: 8.5,
                        color: PdfTheme.grey,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      institute.instituteId,
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 12,
                        color: PdfTheme.darkBlue,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'INSTITUTE NAME',
                      style: pw.TextStyle(
                        font: regular,
                        fontSize: 8.5,
                        color: PdfTheme.grey,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      institute.instituteName.toUpperCase(),
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 12,
                        color: PdfTheme.darkBlue,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          // Row 2: Report Period, Total Students, Report Date
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 80,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'REPORT PERIOD',
                      style: pw.TextStyle(
                        font: regular,
                        fontSize: 8.5,
                        color: PdfTheme.grey,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      reportPeriod,
                      style: pw.TextStyle(
                        font: regular,
                        fontSize: 10.5,
                        color: PdfTheme.black,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.SizedBox(
                width: 70,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'TOTAL STUDENTS',
                      style: pw.TextStyle(
                        font: regular,
                        fontSize: 8.5,
                        color: PdfTheme.grey,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '$totalStudents',
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 12,
                        color: PdfTheme.darkBlue,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'REPORT DATE',
                      style: pw.TextStyle(
                        font: regular,
                        fontSize: 8.5,
                        color: PdfTheme.grey,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      _getTodayDate(),
                      style: pw.TextStyle(
                        font: regular,
                        fontSize: 10.5,
                        color: PdfTheme.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _getTodayDate() {
    final now = DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }
}
