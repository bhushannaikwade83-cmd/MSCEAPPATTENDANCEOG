import 'package:pdf/widgets.dart' as pw;

import '../models/attendance_data.dart';
import 'pdf_theme.dart';

/// `Label  :  ______value______` rows on the left and the bordered
/// "Student Photo" box on the right, exactly as on the printed form.
class StudentInfoSection {
  StudentInfoSection._();

  static pw.Widget build({
    required pw.Font regular,
    required pw.Font bold,
    required StudentInfo student,
  }) {
    final List<List<String>> fields = <List<String>>[
      <String>['Institute ID', student.instituteId],
      <String>['Institute Name', student.instituteName],
      <String>['Student Name', student.studentName],
      <String>['SR No', student.srNo],
      <String>['Subjects', student.subjects.join(', ')],
      if (student.faceRegisteredAt != null)
        <String>['Face Registered', student.faceRegisteredAt!],
    ];

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              for (final List<String> f in fields) _row(bold, regular, f[0], f[1]),
            ],
          ),
        ),
        PdfTheme.hGap(PdfTheme.space16),
        _photoBox(regular, student),
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
      padding: const pw.EdgeInsets.only(bottom: 9),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: <pw.Widget>[
          pw.SizedBox(
            width: 96,
            child: pw.Text(label, style: PdfTheme.fieldLabel(bold)),
          ),
          pw.Text(':', style: PdfTheme.fieldLabel(bold)),
          PdfTheme.hGap(PdfTheme.space8),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(left: 4, bottom: 1.5),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfTheme.blue, width: 0.7),
                ),
              ),
              child: pw.Text(
                value.isEmpty ? ' ' : value,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: PdfTheme.fieldValue(regular),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _photoBox(pw.Font regular, StudentInfo student) {
    return pw.Container(
      width: 88,
      height: 106,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: PdfTheme.white,
        border: pw.Border.all(color: PdfTheme.blue, width: 0.9),
      ),
      child: student.photoBytes == null
          ? pw.Text(
              'Student\nPhoto',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: regular,
                fontSize: 9,
                color: PdfTheme.black,
              ),
            )
          : pw.Image(pw.MemoryImage(student.photoBytes!), fit: pw.BoxFit.cover),
    );
  }
}
