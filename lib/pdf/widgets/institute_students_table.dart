import 'package:pdf/widgets.dart' as pw;
import '../models/institute_report_data.dart';
import 'pdf_theme.dart';

class InstituteStudentsTable {
  static pw.Widget build({
    required pw.Font regular,
    required pw.Font bold,
    required List<StudentAttendanceRow> students,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Table Header
        pw.Container(
          color: PdfTheme.darkBlue,
          padding: pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.SizedBox(
                width: 35,
                child: pw.Text(
                  'Sr No',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 9,
                    color: PdfTheme.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  'Student Name',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 9,
                    color: PdfTheme.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 65,
                child: pw.Text(
                  'Registered',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 9,
                    color: PdfTheme.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 40,
                child: pw.Text(
                  'Present',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 9,
                    color: PdfTheme.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 40,
                child: pw.Text(
                  'Absent',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 9,
                    color: PdfTheme.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 60,
                child: pw.Text(
                  'Hours',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 8,
                    color: PdfTheme.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 45,
                child: pw.Text(
                  'Attend %',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 8,
                    color: PdfTheme.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Table Rows
        ...students.asMap().entries.map((e) {
          final idx = e.key;
          final student = e.value;
          final isEven = idx % 2 == 0;
          return pw.Container(
            color: isEven ? PdfTheme.rowAlt : PdfTheme.white,
            padding: pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.SizedBox(
                  width: 35,
                  child: pw.Text(
                    student.srNo,
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 9,
                      color: PdfTheme.black,
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    student.name,
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 9,
                      color: PdfTheme.black,
                    ),
                    maxLines: 1,
                  ),
                ),
                pw.SizedBox(
                  width: 65,
                  child: pw.Text(
                    student.faceRegisteredAt ?? '-',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 8.5,
                      color: PdfTheme.darkBlue,
                    ),
                  ),
                ),
                pw.SizedBox(
                  width: 40,
                  child: pw.Text(
                    '${student.present}',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 9,
                      color: PdfTheme.black,
                    ),
                  ),
                ),
                pw.SizedBox(
                  width: 40,
                  child: pw.Text(
                    '${student.absent}',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 9,
                      color: PdfTheme.black,
                    ),
                  ),
                ),
                pw.SizedBox(
                  width: 60,
                  child: pw.Text(
                    student.totalHours,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 8,
                      color: PdfTheme.black,
                    ),
                  ),
                ),
                pw.SizedBox(
                  width: 45,
                  child: pw.Text(
                    '${student.attendancePercent.toStringAsFixed(0)}%',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 8.5,
                      color: PdfTheme.darkBlue,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}
