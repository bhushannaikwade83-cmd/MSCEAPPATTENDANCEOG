import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/attendance_data.dart';
import 'pdf_theme.dart';

/// Draws everything that sits *behind* the flowing content, exactly like the
/// printed MSCE stationery:
///
///  * navy double border frame around the whole page
///  * faint council logo watermark in the middle of the page
///  * orange wave + navy motto bar at the bottom
class PageFrame {
  PageFrame._();

  static const double outerInset = 10;
  static const double innerInset = 16;

  /// Height of the navy motto bar at the very bottom of the page.
  static const double footerBarHeight = 30;

  /// Height of the orange wave that sits on top of the navy bar.
  static const double waveHeight = 22;

  static pw.Widget build({
    required pw.Font devanagari,
    required AttendanceReportData data,
  }) {
    return pw.FullPage(
      ignoreMargins: true,
      child: pw.Stack(
        children: <pw.Widget>[
          // ---- navy double frame -------------------------------------------
          pw.Positioned.fill(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(outerInset),
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfTheme.darkBlue, width: 2.4),
                ),
              ),
            ),
          ),
          pw.Positioned.fill(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(innerInset),
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfTheme.darkBlue, width: 0.9),
                ),
              ),
            ),
          ),

          // ---- watermark ----------------------------------------------------
          if (data.logoBytes != null)
            pw.Positioned.fill(
              child: pw.Center(
                child: pw.Opacity(
                  opacity: 0.07,
                  child: pw.Image(
                    pw.MemoryImage(data.logoBytes!),
                    width: 300,
                    height: 300,
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ),
            ),

          // ---- orange wave + navy motto bar ---------------------------------
          pw.Positioned(
            left: innerInset + 0.9,
            right: innerInset + 0.9,
            bottom: innerInset + 0.9,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: <pw.Widget>[
                pw.SizedBox(
                  height: waveHeight,
                  child: pw.CustomPaint(
                    painter: (PdfGraphics canvas, PdfPoint size) {
                      canvas
                        ..setFillColor(PdfTheme.orange)
                        ..moveTo(0, 0)
                        ..curveTo(
                          size.x * 0.35,
                          size.y * 1.25,
                          size.x * 0.65,
                          -size.y * 0.25,
                          size.x,
                          size.y * 0.85,
                        )
                        ..lineTo(size.x, 0)
                        ..lineTo(0, 0)
                        ..fillPath();
                    },
                  ),
                ),
                pw.Container(
                  height: footerBarHeight,
                  color: PdfTheme.darkBlue,
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    PdfTheme.motto,
                    style: pw.TextStyle(
                      font: devanagari,
                      fontSize: 11,
                      color: PdfTheme.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
