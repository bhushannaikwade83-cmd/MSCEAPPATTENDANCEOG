import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';

/// Institute operating hours from `institutes` (`lecture_open_time`, `lecture_close_time`,
/// `lecture_slot_duration_minutes`).
class InstituteLectureTimingService {
  SupabaseClient get _db => appDb;

  Future<Map<String, dynamic>?> getInstituteTiming(String instituteId) async {
    try {
      final row = await _db
          .from('institutes')
          .select('lecture_open_time, lecture_close_time, lecture_slot_duration_minutes')
          .eq('id', instituteId)
          .maybeSingle();

      if (row == null) return null;

      final openTime = row['lecture_open_time'];
      final closeTime = row['lecture_close_time'];
      final duration = row['lecture_slot_duration_minutes'] ?? 60;

      if (openTime == null || closeTime == null) {
        return null;
      }

      Map<String, dynamic> asMap(dynamic v) => Map<String, dynamic>.from(v as Map);

      final o = asMap(openTime);
      final c = asMap(closeTime);

      return {
        'openTime': TimeOfDay(
          hour: (o['hour'] as num?)?.toInt() ?? 8,
          minute: (o['minute'] as num?)?.toInt() ?? 0,
        ),
        'closeTime': TimeOfDay(
          hour: (c['hour'] as num?)?.toInt() ?? 22,
          minute: (c['minute'] as num?)?.toInt() ?? 0,
        ),
        'durationMinutes': duration,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting institute timing: $e');
      return null;
    }
  }

  /// Comma-separated slots `HH:MM - HH:MM` for entry/exit / lecture flow.
  Future<String> buildLectureTimingString(String instituteId) async {
    final t = await getInstituteTiming(instituteId);
    if (t == null) return '';

    final open = t['openTime'] as TimeOfDay;
    final close = t['closeTime'] as TimeOfDay;
    var durationMin = (t['durationMinutes'] as num?)?.toInt() ?? 60;
    if (durationMin < 15) durationMin = 60;

    var cur = open.hour * 60 + open.minute;
    final closeMin = close.hour * 60 + close.minute;
    if (cur >= closeMin) return '';

    final parts = <String>[];
    while (cur < closeMin) {
      final start = TimeOfDay(hour: cur ~/ 60, minute: cur % 60);
      final endM = cur + durationMin;
      final end = TimeOfDay(hour: endM ~/ 60, minute: endM % 60);
      String fmt(TimeOfDay x) =>
          '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
      parts.add('${fmt(start)} - ${fmt(end)}');
      cur = endM;
    }
    return parts.join(', ');
  }
}
