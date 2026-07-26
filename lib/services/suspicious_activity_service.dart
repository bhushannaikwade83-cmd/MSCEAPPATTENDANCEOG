import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';

import '../core/app_db.dart';
import '../core/time_parse.dart';

/// Detects suspicious attendance marking patterns (Supabase).
class SuspiciousActivityService {
  static Future<String?> _instituteCodeFromId(String instituteId) async {
    final row = await appDb.from('institutes').select('institute_code').eq('id', instituteId).maybeSingle();
    return row?['institute_code'] as String?;
  }

  static Future<Map<String, dynamic>> checkSuspiciousActivity({
    required String instituteId,
    required String markedBy,
    required DateTime markingTime,
    required String? deviceFingerprint,
  }) async {
    final warnings = <String>[];
    final isSuspicious = <String, bool>{};

    try {
      final hour = markingTime.hour;
      if (hour < 7 || hour > 20) {
        warnings.add('Unusual marking time: ${DateFormat('HH:mm').format(markingTime)}');
        isSuspicious['unusualTime'] = true;
      } else {
        isSuspicious['unusualTime'] = false;
      }

      final code = await _instituteCodeFromId(instituteId);
      final today = DateFormat('yyyy-MM-dd').format(markingTime);

      List<Map<String, dynamic>> todayMarks = [];
      if (code != null && code.isNotEmpty) {
        final rows = await appDb
            .from('attendance_in_out')
            .select()
            .eq('institute_code', code)
            .eq('attendance_date', today)
            .limit(100);
        todayMarks = List<Map<String, dynamic>>.from(rows);
      }

      final fiveMinutesAgo = markingTime.subtract(const Duration(minutes: 5));
      var recentMarks = 0;
      for (final doc in todayMarks) {
        final add = doc['additional'];
        Map<String, dynamic>? addMap;
        if (add is Map<String, dynamic>) {
          addMap = add;
        } else if (add is Map) {
          addMap = add.map((k, v) => MapEntry(k.toString(), v));
        }
        if ((addMap?['markedBy'] ?? addMap?['marked_by'])?.toString() != markedBy) {
          continue;
        }
        final ts = parseAnyTimestamp(doc['created_at'] ?? doc['timestamp']);
        if (ts != null && ts.isAfter(fiveMinutesAgo)) {
          recentMarks++;
        }
      }

      if (recentMarks > 10) {
        warnings.add('Multiple marks in short time: $recentMarks marks in last 5 minutes');
        isSuspicious['rapidMarking'] = true;
      } else {
        isSuspicious['rapidMarking'] = false;
      }

      if (todayMarks.length > 50) {
        warnings.add('High number of marks today: ${todayMarks.length}');
        isSuspicious['highVolume'] = true;
      } else {
        isSuspicious['highVolume'] = false;
      }

      if (deviceFingerprint != null) {
        try {
          final deviceRow = await appDb
              .from('user_devices')
              .select()
              .eq('institute_id', instituteId)
              .eq('device_id', markedBy)
              .maybeSingle()
              .timeout(const Duration(seconds: 2));

          if (deviceRow != null) {
            final payload = deviceRow['payload'];
            Map<String, dynamic>? p;
            if (payload is Map<String, dynamic>) {
              p = payload;
            } else if (payload is Map) {
              p = payload.map((k, v) => MapEntry(k.toString(), v));
            }
            final lastFingerprint = p?['lastFingerprint'] ?? p?['last_fingerprint'];
            if (lastFingerprint != null && lastFingerprint != deviceFingerprint) {
              warnings.add('Device change detected');
              isSuspicious['deviceChange'] = true;
            } else {
              isSuspicious['deviceChange'] = false;
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Device check skipped: $e');
          isSuspicious['deviceChange'] = false;
        }
      }

      final hasSuspiciousActivity = isSuspicious.values.any((v) => v == true);

      if (kDebugMode) {
        debugPrint('🔍 Suspicious Activity Check: suspicious=$hasSuspiciousActivity');
        warnings.forEach((w) => debugPrint('   - $w'));
      }

      return {
        'isSuspicious': hasSuspiciousActivity,
        'warnings': warnings,
        'checks': isSuspicious,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking suspicious activity: $e');
      return {
        'isSuspicious': false,
        'warnings': <String>[],
        'error': e.toString(),
      };
    }
  }

  static Future<void> logSuspiciousActivity({
    required String instituteId,
    required String userId,
    required Map<String, dynamic> activityData,
  }) async {
    try {
      await appDb.from('suspicious_activity').insert({
        'institute_id': instituteId,
        'payload': {
          'userId': userId,
          'activityData': activityData,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'reviewed': false,
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (kDebugMode) {
        debugPrint('📝 Suspicious activity logged');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error logging suspicious activity: $e');
    }
  }
}
