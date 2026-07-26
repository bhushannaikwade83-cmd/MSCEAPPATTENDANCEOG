import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'app_db.dart';

/// Lightweight counts from [institute_dashboard_stats] RPC (migration 073).
class InstituteDashboardStats {
  const InstituteDashboardStats({
    required this.studentCount,
    required this.todayInOutRows,
    required this.todayDistinctStudents,
    required this.attendanceDate,
  });

  final int studentCount;
  final int todayInOutRows;
  final int todayDistinctStudents;
  final String attendanceDate;

  static InstituteDashboardStats empty(String date) => InstituteDashboardStats(
        studentCount: 0,
        todayInOutRows: 0,
        todayDistinctStudents: 0,
        attendanceDate: date,
      );
}

Future<InstituteDashboardStats> fetchInstituteDashboardStats(
  String instituteKey, {
  String? dateYyyyMmDd,
}) async {
  try {
    final params = <String, dynamic>{'p_institute_key': instituteKey.trim()};
    if (dateYyyyMmDd != null && dateYyyyMmDd.trim().isNotEmpty) {
      params['p_date'] = dateYyyyMmDd.trim();
    }
    final raw = await appDb.rpc('institute_dashboard_stats', params: params);
    final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return InstituteDashboardStats(
      studentCount: (m['student_count'] as num?)?.toInt() ?? 0,
      todayInOutRows: (m['today_in_out_rows'] as num?)?.toInt() ?? 0,
      todayDistinctStudents: (m['today_distinct_students'] as num?)?.toInt() ?? 0,
      attendanceDate: m['attendance_date']?.toString() ?? (dateYyyyMmDd ?? ''),
    );
  } catch (e) {
    if (kDebugMode) debugPrint('institute_dashboard_stats RPC: $e');
    rethrow;
  }
}
