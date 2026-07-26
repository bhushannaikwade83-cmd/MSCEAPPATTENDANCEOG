import 'package:intl/intl.dart';

import '../core/app_db.dart';

/// Attendance streaks from `attendance_in_out` + `students`.
class AttendanceStreakService {
  Future<String?> _instituteCode(String instituteId) async {
    final row = await appDb.from('institutes').select('institute_code').eq('id', instituteId).maybeSingle();
    return row?['institute_code'] as String?;
  }

  Future<Map<String, dynamic>> getStudentStreak({
    required String instituteId,
    required String rollNumber,
  }) async {
    try {
      final code = await _instituteCode(instituteId);
      if (code == null || code.isEmpty) {
        return {
          'currentStreak': 0,
          'longestStreak': 0,
          'totalDays': 0,
          'lastAttendanceDate': null,
        };
      }

      final rows = await appDb
          .from('attendance_in_out')
          .select('attendance_date, sr_no')
          .eq('institute_code', code)
          .eq('sr_no', rollNumber)
          .order('attendance_date', ascending: false)
          .limit(200);

      if (rows.isEmpty) {
        return {
          'currentStreak': 0,
          'longestStreak': 0,
          'totalDays': 0,
          'lastAttendanceDate': null,
        };
      }

      final dates = <DateTime>{};
      for (final r in rows) {
        final d = r['attendance_date']?.toString();
        if (d == null || d.isEmpty) continue;
        try {
          dates.add(DateFormat('yyyy-MM-dd').parse(d));
        } catch (_) {}
      }

      final sorted = dates.toList()..sort((a, b) => b.compareTo(a));

      if (sorted.isEmpty) {
        return {
          'currentStreak': 0,
          'longestStreak': 0,
          'totalDays': 0,
          'lastAttendanceDate': null,
        };
      }

      int currentStreak = 0;
      final lastDate = sorted.first;
      final today = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(today);
      final yesterdayStr = DateFormat('yyyy-MM-dd').format(today.subtract(const Duration(days: 1)));
      final lastStr = DateFormat('yyyy-MM-dd').format(lastDate);

      if (lastStr == todayStr || lastStr == yesterdayStr) {
        currentStreak = 1;
        var checkDate = lastDate;
        for (int i = 1; i < sorted.length; i++) {
          final expectedDate = checkDate.subtract(const Duration(days: 1));
          final expectedStr = DateFormat('yyyy-MM-dd').format(expectedDate);
          final found = sorted.any((d) => DateFormat('yyyy-MM-dd').format(d) == expectedStr);
          if (found) {
            currentStreak++;
            checkDate = expectedDate;
          } else {
            break;
          }
        }
      }

      int longestStreak = 1;
      int tempStreak = 1;
      final list = sorted.toList()..sort((a, b) => b.compareTo(a));
      for (int i = 1; i < list.length; i++) {
        final diff = list[i - 1].difference(list[i]).inDays;
        if (diff == 1) {
          tempStreak++;
          longestStreak = tempStreak > longestStreak ? tempStreak : longestStreak;
        } else {
          tempStreak = 1;
        }
      }

      return {
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'totalDays': sorted.length,
        'lastAttendanceDate': lastDate,
      };
    } catch (e) {
      return {
        'currentStreak': 0,
        'longestStreak': 0,
        'totalDays': 0,
        'lastAttendanceDate': null,
        'error': e.toString(),
      };
    }
  }

  Future<List<Map<String, dynamic>>> getStreakLeaderboard({
    required String instituteId,
    int limit = 10,
  }) async {
    try {
      final students = await appDb.from('students').select('user_id, name').eq('institute_id', instituteId);

      final List<Map<String, dynamic>> leaderboard = [];

      for (final studentData in students) {
        final rollNumber = studentData['user_id'] as String? ?? '';

        if (rollNumber.isEmpty) continue;

        final streak = await getStudentStreak(
          instituteId: instituteId,
          rollNumber: rollNumber,
        );

        leaderboard.add({
          'rollNumber': rollNumber,
          'name': studentData['name'] ?? 'Unknown',
          'currentStreak': streak['currentStreak'] ?? 0,
          'longestStreak': streak['longestStreak'] ?? 0,
          'totalDays': streak['totalDays'] ?? 0,
        });
      }

      leaderboard.sort((a, b) => (b['currentStreak'] as int).compareTo(a['currentStreak'] as int));

      return leaderboard.take(limit).toList();
    } catch (e) {
      return [];
    }
  }
}
