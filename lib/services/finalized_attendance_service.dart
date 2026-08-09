import 'package:intl/intl.dart';
import '../core/app_db.dart';

class FinalizedAttendanceService {
  /// Get attendance data - live for today, finalized for past dates
  static Future<Map<String, dynamic>> getAttendanceForDate({
    required String srNo,
    required DateTime date,
  }) async {
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    if (isToday) {
      // TODAY: Fetch live from attendance table
      return await _fetchLiveAttendance(srNo, date);
    } else {
      // PAST: Fetch from finalized cache
      return await _fetchFinalizedAttendance(srNo, date);
    }
  }

  /// Fetch live attendance from attendance table
  static Future<Map<String, dynamic>> _fetchLiveAttendance(
    String srNo,
    DateTime date,
  ) async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);

      final records = await appDb
          .from('attendance')
          .select()
          .eq('sr_no', srNo)
          .eq('attendance_date', dateStr)
          .order('marked_time');

      print('📍 [LIVE] Fetched ${records.length} records for $srNo on $dateStr');

      // Check for entry/exit
      final entryRec = records.firstWhere(
        (r) => r['record_type'] == 'entry',
        orElse: () => null,
      );
      final exitRec = records.firstWhere(
        (r) => r['record_type'] == 'exit',
        orElse: () => null,
      );

      String status = 'ABSENT';
      String hours = '0h 0m 0s';

      if (entryRec != null) {
        status = 'PRESENT';
        final hrsStr =
            exitRec?['attendance_alloted_hr'] ?? entryRec['attendance_alloted_hr'] ?? '0.0';
        hours = hrsStr;
      }

      return {
        'status': status,
        'hours': hours,
        'isLive': true,
        'recordsCount': records.length,
      };
    } catch (e) {
      print('❌ Error fetching live attendance: $e');
      return {'status': 'ERROR', 'hours': '0h 0m 0s', 'isLive': true};
    }
  }

  /// Fetch finalized attendance from cache table
  static Future<Map<String, dynamic>> _fetchFinalizedAttendance(
    String srNo,
    DateTime date,
  ) async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);

      final record = await appDb
          .from('daily_attendance_finalized')
          .select()
          .eq('sr_no', srNo)
          .eq('attendance_date', dateStr)
          .maybeSingle();

      if (record != null) {
        print('✅ [FINALIZED] Found finalized record for $srNo on $dateStr');
        return {
          'status': record['status'] ?? 'ABSENT',
          'hours': record['credited_hours_formatted'] ?? '0h 0m 0s',
          'isLive': false,
          'markedAt': record['marked_at'],
        };
      } else {
        print('⚠️ [FINALIZED] No finalized record for $srNo on $dateStr');
        return {
          'status': 'ABSENT',
          'hours': '0h 0m 0s',
          'isLive': false,
          'markedAt': null,
        };
      }
    } catch (e) {
      print('❌ Error fetching finalized attendance: $e');
      return {'status': 'ERROR', 'hours': '0h 0m 0s', 'isLive': false};
    }
  }

  /// Get attendance summary for date range
  static Future<Map<String, dynamic>> getAttendanceSummary({
    required String srNo,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(endDate);
      final today = DateTime.now();

      // Fetch all finalized records in range
      final finalizedRecords = await appDb
          .from('daily_attendance_finalized')
          .select()
          .eq('sr_no', srNo)
          .gte('attendance_date', startStr)
          .lte('attendance_date', endStr)
          .order('attendance_date');

      int presentCount = 0;
      int absentCount = 0;
      double totalHours = 0.0;

      for (final rec in finalizedRecords) {
        if (rec['status'] == 'PRESENT') {
          presentCount++;
          totalHours += (rec['credited_hours'] as num).toDouble();
        } else {
          absentCount++;
        }
      }

      // For today, also check live data if it's today
      if (today.year >= startDate.year &&
          today.month >= startDate.month &&
          today.day >= startDate.day &&
          today.year <= endDate.year &&
          today.month <= endDate.month &&
          today.day <= endDate.day) {
        final todayData = await _fetchLiveAttendance(srNo, today);
        // Today data will be added to summary but not yet finalized
      }

      return {
        'present': presentCount,
        'absent': absentCount,
        'total': presentCount + absentCount,
        'hours': totalHours,
        'recordsFrom': 'finalized_cache',
      };
    } catch (e) {
      print('❌ Error fetching attendance summary: $e');
      return {
        'present': 0,
        'absent': 0,
        'total': 0,
        'hours': 0.0,
        'error': e.toString(),
      };
    }
  }

  /// Check if date is today
  static bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// Check if date is in past
  static bool isPast(DateTime date) {
    final now = DateTime.now();
    return date.isBefore(DateTime(now.year, now.month, now.day));
  }
}
