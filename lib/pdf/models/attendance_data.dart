import 'dart:typed_data';

/// ---------------------------------------------------------------------------
/// DATA MODELS
/// ---------------------------------------------------------------------------

/// A single day of attendance.
class AttendanceRecord {
  const AttendanceRecord({
    required this.date,
    required this.entryTime,
    required this.exitTime,
    required this.status,
    required this.hours,
    this.reason = '-',
  });

  /// Formatted date string, e.g. `05-08-2026`.
  final String date;

  /// Formatted entry time, e.g. `09:12 AM`. Use `-` when unavailable.
  final String entryTime;

  /// Formatted exit time, e.g. `05:04 PM`. Use `-` when unavailable.
  final String exitTime;

  /// `Present`, `Absent` or `Late`.
  final String status;

  /// Worked hours as text, e.g. `7.8`.
  final String hours;

  /// Free text reason / remark. Wraps automatically in the table.
  final String reason;
}

/// Student + institute identity block shown on every page.
class StudentInfo {
  const StudentInfo({
    required this.instituteId,
    required this.instituteName,
    required this.studentName,
    required this.srNo,
    required this.subjects,
    this.photoBytes,
    this.faceRegisteredAt,
  });

  final String instituteId;
  final String instituteName;
  final String studentName;
  final String srNo;

  /// Subject list, joined with commas when rendered.
  final List<String> subjects;

  /// Raw JPG/PNG bytes of the student photo. Optional.
  final Uint8List? photoBytes;

  /// When the student's face was registered (e.g. "15 Aug 2026").
  final String? faceRegisteredAt;
}

/// Aggregated numbers rendered in the summary box on the last page.
class AttendanceSummary {
  const AttendanceSummary({
    required this.totalPresent,
    required this.totalAbsent,
    required this.totalLate,
  });

  /// Builds a summary straight from the record list.
  factory AttendanceSummary.fromRecords(List<AttendanceRecord> records) {
    int present = 0;
    int absent = 0;
    int late = 0;
    for (final r in records) {
      switch (r.status.trim().toLowerCase()) {
        case 'present':
        case 'p':
          present++;
          break;
        case 'absent':
        case 'a':
          absent++;
          break;
        case 'late':
        case 'l':
          late++;
          break;
      }
    }
    return AttendanceSummary(
      totalPresent: present,
      totalAbsent: absent,
      totalLate: late,
    );
  }

  final int totalPresent;
  final int totalAbsent;
  final int totalLate;

  /// Late days count as attended days.
  int get totalDays => totalPresent + totalAbsent + totalLate;

  double get percentage {
    if (totalDays == 0) return 0;
    return ((totalPresent + totalLate) / totalDays) * 100;
  }

  String get percentageLabel => '${percentage.toStringAsFixed(2)} %';
}

/// Everything the report needs in one immutable payload.
class AttendanceReportData {
  const AttendanceReportData({
    required this.student,
    required this.records,
    this.summary,
    this.logoBytes,
    this.reportPeriod,
    this.generatedOn,
    this.effectivePeriod,
  });

  final StudentInfo student;
  final List<AttendanceRecord> records;

  /// When null, it is computed from [records].
  final AttendanceSummary? summary;

  /// Raw PNG bytes of the Maharashtra State Council logo. Optional.
  final Uint8List? logoBytes;

  /// e.g. `01 Jul 2026 - 31 Jul 2026`.
  final String? reportPeriod;

  /// Effective period (adjusted from registration date). e.g. `15 Aug 2026 - 31 Aug 2026`.
  final String? effectivePeriod;

  /// Defaults to `DateTime.now()`.
  final DateTime? generatedOn;

  AttendanceSummary get effectiveSummary =>
      summary ?? AttendanceSummary.fromRecords(records);
}
