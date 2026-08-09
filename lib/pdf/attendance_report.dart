import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models/attendance_data.dart';
import 'widgets/attendance_table.dart';
import 'widgets/footer.dart';
import 'widgets/header.dart';
import 'widgets/page_frame.dart';
import 'widgets/pdf_theme.dart';
import 'widgets/student_info.dart';
import 'widgets/summary.dart';

/// Fonts used across the document. Kept in one object so widgets never load
/// fonts themselves.
class ReportFonts {
  const ReportFonts({
    required this.regular,
    required this.bold,
    required this.devanagari,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font devanagari;

  /// Loads Google fonts through the `printing` package (network on first use,
  /// cached afterwards). Devanagari is required for the Marathi motto.
  static Future<ReportFonts> load() async {
    final results = await Future.wait<pw.Font>(<Future<pw.Font>>[
      PdfGoogleFonts.notoSansRegular(),
      PdfGoogleFonts.notoSansBold(),
      PdfGoogleFonts.notoSansDevanagariRegular(),
    ]);
    return ReportFonts(
      regular: results[0],
      bold: results[1],
      devanagari: results[2],
    );
  }
}

/// Builds the MSCE Attendance Report and returns printable PDF bytes.
///
/// ```dart
/// final bytes = await generatePdfReport(data: reportData);
/// await Printing.layoutPdf(onLayout: (_) => bytes);
/// ```
Future<Uint8List> generatePdfReport({
  required AttendanceReportData data,
  ReportFonts? fonts,
}) async {
  final ReportFonts f = fonts ?? await ReportFonts.load();
  final DateTime generatedOn = data.generatedOn ?? DateTime.now();

  final pw.Document doc = pw.Document(
    title: 'MSCE Attendance Report',
    author: 'Maharashtra State Council of Examination',
    creator: 'MSCE Attendance App',
    theme: pw.ThemeData.withFont(
      base: f.regular,
      bold: f.bold,
      fontFallback: <pw.Font>[f.devanagari],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        orientation: pw.PageOrientation.portrait,
        margin: PdfTheme.pagePadding,
        theme: pw.ThemeData.withFont(
          base: f.regular,
          bold: f.bold,
          fontFallback: <pw.Font>[f.devanagari],
        ),
        // Navy double frame, watermark and orange wave + motto bar.
        buildBackground: (pw.Context context) => PageFrame.build(
          devanagari: f.devanagari,
          data: data,
        ),
      ),
      maxPages: 500,
      // Header (+ student block on page 1) repeats on every page.
      header: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          ReportHeader.build(
            regular: f.regular,
            bold: f.bold,
            devanagari: f.devanagari,
            data: data,
          ),
          if (context.pageNumber == 1) ...<pw.Widget>[
            StudentInfoSection.build(
              regular: f.regular,
              bold: f.bold,
              student: data.student,
            ),
            PdfTheme.gap(PdfTheme.space12),
          ],
        ],
      ),
      footer: (pw.Context context) => ReportFooter.build(
        context: context,
        regular: f.regular,
        bold: f.bold,
        devanagari: f.devanagari,
        generatedOn: generatedOn,
      ),
      build: (pw.Context context) => <pw.Widget>[
        AttendanceTable.build(
          regular: f.regular,
          bold: f.bold,
          records: data.records,
        ),
        PdfTheme.gap(PdfTheme.space8),
        AttendanceLegend.build(f.regular),
        PdfTheme.gap(PdfTheme.space16),
        // Last flowing widget -> always renders on the final page.
        ReportSummary.build(
          regular: f.regular,
          bold: f.bold,
          summary: data.effectiveSummary,
        ),
      ],
    ),
  );

  return doc.save();
}

/// Opens the platform print / share preview for the generated report.
Future<void> printAttendanceReport(AttendanceReportData data) async {
  final Uint8List bytes = await generatePdfReport(data: data);
  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => bytes,
    name: 'attendance_report_${data.student.srNo}.pdf',
  );
}

/// Shares / saves the generated report as a file.
Future<void> shareAttendanceReport(AttendanceReportData data) async {
  final Uint8List bytes = await generatePdfReport(data: data);
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'attendance_report_${data.student.srNo}.pdf',
  );
}
