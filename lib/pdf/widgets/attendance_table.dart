import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/attendance_data.dart';
import 'pdf_theme.dart';

/// Full-grid attendance table: navy header row that repeats on every page,
/// thin blue grid lines and a transparent body so the page watermark shows
/// through, exactly like the printed sheet.
class AttendanceTable {
  AttendanceTable._();

  static const List<String> _headers = <String>[
    'Date',
    'Entry',
    'Exit',
    'Status',
    'Hours',
    'Reason',
  ];

  static pw.Widget build({
    required pw.Font regular,
    required pw.Font bold,
    required List<AttendanceRecord> records,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: _headers,
      data: records
          .map((AttendanceRecord r) => <String>[
                r.date,
                r.entryTime,
                r.exitTime,
                r.status,
                r.hours,
                r.reason,
              ])
          .toList(),
      border: pw.TableBorder.all(color: PdfTheme.blue, width: 0.6),
      headerDecoration: const pw.BoxDecoration(color: PdfTheme.darkBlue),
      headerHeight: 22,
      cellHeight: 20,
      headerStyle: PdfTheme.tableHeader(bold),
      cellStyle: PdfTheme.tableCell(regular),
      headerAlignment: pw.Alignment.center,
      cellAlignment: pw.Alignment.center,
      cellAlignments: const <int, pw.Alignment>{
        5: pw.Alignment.centerLeft,
      },
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1.35),
        1: pw.FlexColumnWidth(1.15),
        2: pw.FlexColumnWidth(1.15),
        3: pw.FlexColumnWidth(1.0),
        4: pw.FlexColumnWidth(0.8),
        5: pw.FlexColumnWidth(1.9),
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      // Status column keeps its colour coding; other cells stay transparent.
      cellDecoration: (int col, dynamic value, int row) {
        if (col != 3) return const pw.BoxDecoration();
        return pw.BoxDecoration(
          color: PdfTheme.statusTint(value.toString()),
        );
      },
      headerCellDecoration: const pw.BoxDecoration(color: PdfTheme.darkBlue),
      oddRowDecoration: const pw.BoxDecoration(),
    );
  }

  /// Empty grid rows so a short report still fills the sheet like the
  /// printed template. Returns `null` when no filler is needed.
  static pw.Widget? filler({
    required pw.Font regular,
    required int rowCount,
  }) {
    if (rowCount <= 0) return null;
    return pw.Table(
      border: pw.TableBorder.all(color: PdfTheme.blue, width: 0.6),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1.35),
        1: pw.FlexColumnWidth(1.15),
        2: pw.FlexColumnWidth(1.15),
        3: pw.FlexColumnWidth(1.0),
        4: pw.FlexColumnWidth(0.8),
        5: pw.FlexColumnWidth(1.9),
      },
      children: List<pw.TableRow>.generate(
        rowCount,
        (_) => pw.TableRow(
          children: List<pw.Widget>.generate(
            6,
            (_) => pw.Container(height: 20),
          ),
        ),
      ),
    );
  }
}

/// Small colour legend under the table.
class AttendanceLegend {
  AttendanceLegend._();

  static pw.Widget build(pw.Font regular) {
    pw.Widget chip(String label, PdfColor tint, PdfColor text) => pw.Row(
          children: <pw.Widget>[
            pw.Container(
              width: 9,
              height: 9,
              decoration: pw.BoxDecoration(
                color: tint,
                border: pw.Border.all(color: text, width: 0.6),
              ),
            ),
            PdfTheme.hGap(4),
            pw.Text(label,
                style: pw.TextStyle(
                    font: regular, fontSize: 7.5, color: PdfTheme.grey)),
            PdfTheme.hGap(PdfTheme.space12),
          ],
        );

    return pw.Row(
      children: <pw.Widget>[
        chip('Present', PdfTheme.presentTint, PdfTheme.present),
        chip('Absent', PdfTheme.absentTint, PdfTheme.absent),
        chip('Late', PdfTheme.lateTint, PdfTheme.lateColor),
      ],
    );
  }
}
