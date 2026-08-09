import 'package:pdf/widgets.dart' as pw;

import 'page_frame.dart';
import 'pdf_theme.dart';

/// The navy motto bar itself is painted by [PageFrame]; this widget only adds
/// the small "Generated on / Page x of y" line that sits just above it.
class ReportFooter {
  ReportFooter._();

  static pw.Widget build({
    required pw.Context context,
    required pw.Font regular,
    required pw.Font bold,
    required pw.Font devanagari,
    required DateTime generatedOn,
  }) {
    final String stamp = _formatDate(generatedOn);
    return pw.Padding(
      // Leaves room for the orange wave + navy motto bar underneath.
      padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text('Generated on $stamp', style: PdfTheme.metaText(regular)),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: PdfTheme.metaText(regular),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}
