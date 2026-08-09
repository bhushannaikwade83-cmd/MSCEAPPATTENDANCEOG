import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models/institute_report_data.dart';
import 'widgets/footer.dart';
import 'widgets/header.dart';
import 'widgets/page_frame.dart';
import 'widgets/pdf_theme.dart';
import 'widgets/institute_info.dart';
import 'widgets/institute_students_table.dart';
import 'widgets/institute_summary.dart';

class ReportFonts {
  const ReportFonts({
    required this.regular,
    required this.bold,
    required this.devanagari,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font devanagari;

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

pw.Widget _buildHeader({
  required pw.Context context,
  required pw.Font regular,
  required pw.Font bold,
  required pw.Font devanagari,
  required InstituteInfo institute,
  required String reportPeriod,
  Uint8List? logoBytes,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: <pw.Widget>[
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Column(
            children: <pw.Widget>[
              pw.Container(
                width: 74,
                height: 62,
                alignment: pw.Alignment.center,
                child: logoBytes == null
                    ? pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfTheme.border, width: 0.8),
                        ),
                        alignment: pw.Alignment.center,
                        child: pw.Text('LOGO',
                            style: pw.TextStyle(fontSize: 7, color: PdfTheme.grey)),
                      )
                    : pw.Image(
                        pw.MemoryImage(logoBytes),
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
          ),
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
      PdfTheme.gap(PdfTheme.space12),
      pw.Center(
        child: pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfTheme.darkBlue,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(20)),
          ),
          padding: pw.EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: pw.Text(
            'INSTITUTE ATTENDANCE REPORT',
            style: PdfTheme.bannerTitle(bold),
          ),
        ),
      ),
      PdfTheme.gap(PdfTheme.space16),
    ],
  );
}

Future<Uint8List> generateInstituteReportPdf({
  required InstituteReportData data,
  ReportFonts? fonts,
}) async {
  final ReportFonts f = fonts ?? await ReportFonts.load();
  final DateTime generatedOn = data.generatedOn ?? DateTime.now();
  final String reportPeriod = data.reportPeriod ?? 'N/A';

  // Load logo if not already in data
  Uint8List? logoBytes = data.logoBytes;
  if (logoBytes == null) {
    try {
      logoBytes = (await rootBundle.load('assets/pdf_images/msce_logo.png')).buffer.asUint8List();
    } catch (_) {
      // Logo not available
    }
  }

  final pw.Document doc = pw.Document(
    title: 'MSCE Institute Attendance Report',
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
      ),
      maxPages: 500,
      header: (pw.Context context) {
        if (context.pageNumber == 1) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              _buildHeader(
                context: context,
                regular: f.regular,
                bold: f.bold,
                devanagari: f.devanagari,
                institute: data.institute,
                reportPeriod: reportPeriod,
                logoBytes: logoBytes,
              ),
              InstituteInfoSection.build(
                regular: f.regular,
                bold: f.bold,
                institute: data.institute,
                reportPeriod: reportPeriod,
                totalStudents: data.students.length,
              ),
              PdfTheme.gap(PdfTheme.space12),
            ],
          );
        } else {
          return _buildHeader(
            context: context,
            regular: f.regular,
            bold: f.bold,
            devanagari: f.devanagari,
            institute: data.institute,
            reportPeriod: reportPeriod,
            logoBytes: logoBytes,
          );
        }
      },
      footer: (pw.Context context) => ReportFooter.build(
        context: context,
        regular: f.regular,
        bold: f.bold,
        devanagari: f.devanagari,
        generatedOn: generatedOn,
      ),
      build: (pw.Context context) => <pw.Widget>[
        InstituteStudentsTable.build(
          regular: f.regular,
          bold: f.bold,
          students: data.students,
        ),
        PdfTheme.gap(PdfTheme.space16),
        InstituteSummarySection.build(
          regular: f.regular,
          bold: f.bold,
          summary: data.summary,
        ),
      ],
    ),
  );

  return doc.save();
}

Future<void> shareInstituteReportPdf(InstituteReportData data) async {
  final Uint8List bytes = await generateInstituteReportPdf(data: data);
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'institute_report_${data.institute.instituteId}.pdf',
  );
}
