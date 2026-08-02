import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;
import '../core/app_db.dart';
import '../core/supabase_maps.dart';
import '../core/attendance_presence_rules.dart';

/// ✅ Shared Stats Service - Real-time present/absent stats for all dashboards
class SharedStatsService {
  static final SharedStatsService _instance = SharedStatsService._internal();

  factory SharedStatsService() {
    return _instance;
  }

  SharedStatsService._internal();

  final _statsController = StreamController<Map<String, int>>.broadcast();
  Stream<Map<String, int>> get statsStream => _statsController.stream;

  // Student total count cache (5-min TTL) — avoids re-counting on every stats refresh.
  static final Map<String, int>      _totalCache   = {};
  static final Map<String, DateTime> _totalCacheAt = {};
  static const _kTotalTtl = Duration(minutes: 5);

  // Track last date for midnight reset
  static String _lastDateChecked = '';

  /// ✅ Auto-reset cache at midnight (12:00 AM)
  static void _checkAndResetAtMidnight() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_lastDateChecked != today) {
      if (kDebugMode) {
        debugPrint('🌙 MIDNIGHT RESET: Date changed from $_lastDateChecked to $today');
      }
      _lastDateChecked = today;
      invalidateTotalCache(); // Reset cache for all institutes
    }
  }

  static void invalidateTotalCache([String? instituteId]) {
    if (instituteId == null) { _totalCache.clear(); _totalCacheAt.clear(); }
    else { _totalCache.remove(instituteId); _totalCacheAt.remove(instituteId); }
  }

  /// ✅ Get today's stats directly from database
  /// Returns: {present, absent, total}
  static Future<Map<String, int>> getTodayStats(String instituteId) async {
    // ✅ Auto-reset at midnight
    _checkAndResetAtMidnight();

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      // Student count: cached 5 min (rarely changes).
      int total;
      final cachedAt = _totalCacheAt[instituteId];
      if (cachedAt != null &&
          DateTime.now().difference(cachedAt) < _kTotalTtl &&
          _totalCache.containsKey(instituteId)) {
        total = _totalCache[instituteId]!;
      } else {
        total = (await appDb
                .from('students')
                .select('id')
                .eq('institute_id', instituteId)
                .count(CountOption.exact))
            .count;
        _totalCache[instituteId]   = total;
        _totalCacheAt[instituteId] = DateTime.now();
      }

      if (kDebugMode) {
        debugPrint('📊 STATS: Total students=$total, date=$today, instituteId=$instituteId');
      }

      if (total == 0) {
        return {'present': 0, 'absent': 0, 'total': 0};
      }

      // Get institute code
      final code = await instituteCodeForId(instituteId);
      final instituteCodes = <String>{code, instituteId.trim()}
        ..removeWhere((s) => s.isEmpty);

      if (kDebugMode) {
        debugPrint('📊 STATS: Institute codes to check: $instituteCodes, code=$code');
      }

      // ✅ Get today's attendance records from NEW attendance table
      // Using record_type = 'entry' to mark students as present
      final List<dynamic> rows = [];
      try {
        final tempRows = await appDb
            .from('attendance')
            .select('sr_no,record_type')
            .eq('institute_id', instituteId)
            .eq('attendance_date', today)
            .eq('record_type', 'entry'); // ✅ Only entries count as present
        rows.addAll(tempRows);

        if (kDebugMode) {
          debugPrint('✅ Attendance query successful: ${rows.length} entries found');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('❌ Attendance query failed: $e');
      }

      if (kDebugMode) {
        debugPrint('📊 STATS: Found ${rows.length} entry records for date=$today');
      }

      // ✅ Extract unique sr_no values (students with entry = present)
      final presentStudents = <String>{};
      for (final row in rows) {
        final sr = row['sr_no']?.toString().trim() ?? '';
        if (sr.isNotEmpty) {
          presentStudents.add(sr);
        }
      }

      if (kDebugMode) {
        debugPrint('📊 STATS: Found ${presentStudents.length} unique students with entry records');
      }

      // ✅ Count present and absent
      final present = presentStudents.length;
      final absent = (total - present).clamp(0, total);

      if (kDebugMode) {
        debugPrint(
          '📊 STATS: Total=$total, Present=$present, Absent=$absent (institute=$instituteId, date=$today)',
        );
      }

      return {
        'present': present,
        'absent': absent,
        'total': total,
      };
    } catch (e) {
      debugPrint('❌ Error getting stats: $e');
      if (kDebugMode) {
        debugPrint('❌ STATS ERROR DETAILS: $e');
      }
      return {'present': 0, 'absent': 0, 'total': 0};
    }
  }

  /// Notify all listeners of stats change
  void notifyStatsChanged(Map<String, int> stats) {
    _statsController.add(stats);
  }

  void dispose() {
    _statsController.close();
  }
}
