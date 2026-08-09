import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Central design system for the MSCE Attendance Report PDF.
/// Colors, spacing, radii and typography match the printed council
/// stationery so every widget stays consistent.
class PdfTheme {
  PdfTheme._();

  /// Devanagari motto printed under the logo and in the footer bar.
  static const String motto = 'विद्या गुरुणां गुरुः ।';

  // ---------------------------------------------------------------------------
  // COLORS
  // ---------------------------------------------------------------------------
  static const PdfColor darkBlue = PdfColor.fromInt(0xFF16255C);
  static const PdfColor blue = PdfColor.fromInt(0xFF1F3C88);
  static const PdfColor lightBlue = PdfColor.fromInt(0xFFEAF1FA);
  static const PdfColor orange = PdfColor.fromInt(0xFFF15A22);
  static const PdfColor white = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor black = PdfColor.fromInt(0xFF111827);
  static const PdfColor grey = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor border = PdfColor.fromInt(0xFFD3DCE8);
  static const PdfColor rowAlt = PdfColor.fromInt(0xFFF6F8FC);

  // Status colors + light tints used inside the Status column
  static const PdfColor present = PdfColor.fromInt(0xFF157F3D);
  static const PdfColor absent = PdfColor.fromInt(0xFFC02626);
  static const PdfColor lateColor = PdfColor.fromInt(0xFFB8790B);
  static const PdfColor presentTint = PdfColor.fromInt(0xFFE7F6EC);
  static const PdfColor absentTint = PdfColor.fromInt(0xFFFDECEC);
  static const PdfColor lateTint = PdfColor.fromInt(0xFFFFF6E0);

  // ---------------------------------------------------------------------------
  // SPACING
  // ---------------------------------------------------------------------------
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;

  /// Keeps content inside the navy double frame drawn by `PageFrame`,
  /// and clears the orange wave + motto bar at the bottom.
  static const pw.EdgeInsets pagePadding =
      pw.EdgeInsets.fromLTRB(30, 30, 30, 74);

  static const pw.EdgeInsets boxPadding = pw.EdgeInsets.all(space12);
  static const pw.EdgeInsets cellPadding =
      pw.EdgeInsets.symmetric(horizontal: space6, vertical: space6);

  // ---------------------------------------------------------------------------
  // RADIUS / BORDERS
  // ---------------------------------------------------------------------------
  static const double radiusSm = 3;
  static const double radiusMd = 6;
  static const double radiusLg = 10;

  static pw.BorderRadius get roundedSm =>
      pw.BorderRadius.all(pw.Radius.circular(radiusSm));
  static pw.BorderRadius get roundedMd =>
      pw.BorderRadius.all(pw.Radius.circular(radiusMd));
  static pw.BorderRadius get roundedLg =>
      pw.BorderRadius.all(pw.Radius.circular(radiusLg));

  // ---------------------------------------------------------------------------
  // TYPOGRAPHY
  // ---------------------------------------------------------------------------
  static pw.TextStyle councilName(pw.Font f) => pw.TextStyle(
        font: f,
        fontSize: 20,
        color: darkBlue,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 0.2,
        lineSpacing: 3,
      );

  static pw.TextStyle bannerTitle(pw.Font f) => pw.TextStyle(
        font: f,
        fontSize: 13,
        color: white,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 0.8,
      );

  static pw.TextStyle fieldLabel(pw.Font f) => pw.TextStyle(
        font: f,
        fontSize: 10,
        color: black,
        fontWeight: pw.FontWeight.bold,
      );

  static pw.TextStyle fieldValue(pw.Font f) => pw.TextStyle(
        font: f,
        fontSize: 9.5,
        color: black,
      );

  static pw.TextStyle tableHeader(pw.Font f) => pw.TextStyle(
        font: f,
        fontSize: 9.5,
        color: white,
        fontWeight: pw.FontWeight.bold,
      );

  static pw.TextStyle tableCell(pw.Font f) => pw.TextStyle(
        font: f,
        fontSize: 8.8,
        color: black,
      );

  static pw.TextStyle metaText(pw.Font f) => pw.TextStyle(
        font: f,
        fontSize: 7.5,
        color: grey,
      );

  static pw.TextStyle sectionTitle(pw.Font f) => pw.TextStyle(
        font: f,
        fontSize: 11,
        color: darkBlue,
        fontWeight: pw.FontWeight.bold,
      );

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------
  static pw.Widget gap(double size) => pw.SizedBox(height: size);

  static pw.Widget hGap(double size) => pw.SizedBox(width: size);

  static PdfColor statusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'present':
      case 'p':
        return present;
      case 'absent':
      case 'a':
        return absent;
      case 'late':
      case 'l':
        return lateColor;
      default:
        return grey;
    }
  }

  static PdfColor statusTint(String status) {
    switch (status.trim().toLowerCase()) {
      case 'present':
      case 'p':
        return presentTint;
      case 'absent':
      case 'a':
        return absentTint;
      case 'late':
      case 'l':
        return lateTint;
      default:
        return white;
    }
  }
}
