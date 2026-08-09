import 'dart:typed_data';

class InstituteInfo {
  const InstituteInfo({
    required this.instituteId,
    required this.instituteName,
  });

  final String instituteId;
  final String instituteName;
}

class StudentAttendanceRow {
  const StudentAttendanceRow({
    required this.srNo,
    required this.name,
    required this.present,
    required this.absent,
    required this.totalHours,
    required this.attendancePercent,
    required this.status,
    this.faceRegisteredAt,
  });

  final String srNo;
  final String name;
  final int present;
  final int absent;
  final String totalHours;
  final double attendancePercent;
  final String status;
  final String? faceRegisteredAt;
}

class InstituteSummary {
  const InstituteSummary({
    required this.totalStudents,
    required this.totalPresent,
    required this.totalAbsent,
    required this.totalHours,
    required this.averageAttendancePercent,
  });

  final int totalStudents;
  final int totalPresent;
  final int totalAbsent;
  final String totalHours;
  final double averageAttendancePercent;
}

class InstituteReportData {
  const InstituteReportData({
    required this.institute,
    required this.students,
    required this.summary,
    this.logoBytes,
    this.reportPeriod,
    this.generatedOn,
  });

  final InstituteInfo institute;
  final List<StudentAttendanceRow> students;
  final InstituteSummary summary;
  final Uint8List? logoBytes;
  final String? reportPeriod;
  final DateTime? generatedOn;
}
