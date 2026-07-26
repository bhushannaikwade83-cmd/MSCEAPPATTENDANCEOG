import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import '../core/supabase_maps.dart';
import 'subject_service.dart' show invalidateSubjectCache;
import 'shared_stats_service.dart' show SharedStatsService;
import 'face_recognition_service.dart' show FaceRecognitionService;

class InstituteSyncEvent {
  final String instituteId;
  final String type;

  const InstituteSyncEvent({
    required this.instituteId,
    required this.type,
  });
}

/// ✅ OPTIMIZED: All 7 table listeners merged into ONE channel per institute.
/// Before: 7 WebSocket connections/institute → exhausted DB connections.
/// After:  1 WebSocket connection/institute  → 86% connection reduction.
///
/// Cache invalidation is wired here so cached data refreshes exactly when
/// data changes — not on a timer.
class InstituteRealtimeSyncService {
  InstituteRealtimeSyncService._();

  static final InstituteRealtimeSyncService instance =
      InstituteRealtimeSyncService._();

  final StreamController<InstituteSyncEvent> _controller =
      StreamController<InstituteSyncEvent>.broadcast();
  final Map<String, int>             _refCounts          = {};
  final Map<String, RealtimeChannel> _channelByInstitute = {};

  Stream<InstituteSyncEvent> watch(String instituteId) =>
      _controller.stream.where((e) => e.instituteId == instituteId);

  Future<void> retain(String instituteId) async {
    final id = instituteId.trim();
    if (id.isEmpty) return;

    final nextCount = (_refCounts[id] ?? 0) + 1;
    _refCounts[id] = nextCount;
    if (nextCount > 1) return; // already subscribed

    final instituteCode = await instituteCodeForId(id);

    void emit(String eventType) {
      if (kDebugMode) debugPrint('🔄 Realtime sync: $eventType for $id');
      _invalidateCachesFor(id, eventType);
      _controller.add(InstituteSyncEvent(instituteId: id, type: eventType));
    }

    // ONE channel — multiple postgres-change listeners multiplexed over it.
    // Supabase multiplexes all listeners on the same channel name over a
    // single WebSocket, reducing connections from 7 → 1 per institute.
    var channel = appDb.channel('sync-$id');

    void addListener(
        String table, String column, String value, String eventType) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: column,
          value: value,
        ),
        callback: (_) => emit(eventType),
      );
    }

    addListener('students',           'institute_id',  id,           'students');
    addListener('institute_subjects', 'institute_id',  id,           'subjects');
    addListener('gps_settings',       'institute_id',  id,           'gps');
    addListener('institute_geofence', 'institute_id',  id,           'gps');
    addListener('institutes',         'id',            id,           'institute');
    addListener('teacher_attendance', 'institute_id',  id,           'attendance');
    if (instituteCode.isNotEmpty) {
      addListener('attendance_in_out', 'institute_code', instituteCode, 'attendance');
    }

    _channelByInstitute[id] = channel..subscribe();
  }

  Future<void> release(String instituteId) async {
    final id = instituteId.trim();
    if (id.isEmpty) return;

    final current = _refCounts[id];
    if (current == null) return;
    if (current > 1) {
      _refCounts[id] = current - 1;
      return;
    }

    _refCounts.remove(id);
    final ch = _channelByInstitute.remove(id);
    if (ch != null) await appDb.removeChannel(ch);
  }

  /// Invalidate relevant in-memory caches on realtime event.
  /// Data is refreshed on actual change — not on a polling timer.
  static void _invalidateCachesFor(String instituteId, String eventType) {
    switch (eventType) {
      case 'students':
        FaceRecognitionService.invalidateEnrolledCache();
        SharedStatsService.invalidateTotalCache(instituteId);
      case 'subjects':
        invalidateSubjectCache(instituteId);
      case 'institute':
        invalidateInstituteCache(instituteId);
      case 'attendance':
        SharedStatsService.invalidateTotalCache(instituteId);
    }
  }
}
