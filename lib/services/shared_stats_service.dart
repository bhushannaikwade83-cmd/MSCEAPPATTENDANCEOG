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

  static void invalidateTotalCache([String? instituteId]) {
    if (instituteId == null) { _totalCache.clear(); _totalCacheAt.clear(); }
    else { _totalCache.remove(instituteId); _totalCacheAt.remove(instituteId); }
  }

  /// ✅ Get today's stats directly from database
  /// Returns: {present, absent, total}
  static Future<Map<String, int>> getTodayStats(String instituteId) async {
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

      // Get today's attendance records from database
      final List<dynamic> rows = [];
      try {
        final tempRows = await appDb
            .from('attendance_in_out')
            .select('student_id,sr_no,type,additional')
            .inFilter('institute_code', instituteCodes.toList())
            .eq('attendance_date', today);
        rows.addAll(tempRows);
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ First query failed: $e, trying alternative...');
      }

      // Fallback: if no results, try without inFilter (check both codes separately)
      if (rows.isEmpty && instituteCodes.isNotEmpty) {
        try {
          for (final ic in instituteCodes) {
            final tempRows = await appDb
                .from('attendance_in_out')
                .select('student_id,sr_no,type,additional')
                .eq('institute_code', ic)
                .eq('attendance_date', today);
            rows.addAll(tempRows);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Fallback query also failed: $e');
        }
      }

      if (kDebugMode) {
        debugPrint('📊 STATS: Found ${rows.length} attendance records for date=$today');
      }

      // Group by student key
      final Map<String, List<Map<String, dynamic>>> byStudentKey = {};
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final sid = row['student_id']?.toString().trim() ?? '';
        final sr = row['sr_no']?.toString().trim() ?? '';
        final key = sid.isNotEmpty ? sid : sr;
        if (key.isEmpty) continue;
        byStudentKey.putIfAbsent(key, () => []).add(row);
      }

      if (kDebugMode) {
        debugPrint('📊 STATS: Grouped ${byStudentKey.length} unique students');
      }

      // Count present students using attendance rules
      final presentRolls = <String>{};
      for (final e in byStudentKey.entries) {
        if (studentDayPresentFromInOutRows(e.value)) {
          presentRolls.add(e.key);
        }
      }

      final present = presentRolls.length;
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
