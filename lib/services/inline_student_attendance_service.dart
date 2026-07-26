import 'dart:async' show unawaited;
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import '../core/supabase_maps.dart';
import '../core/face_matching_thresholds.dart';
import '../core/root_navigator.dart';
import '../core/attendance_auto_close_policy.dart';
import '../core/attendance_presence_rules.dart';
import '../core/student_face_embedding_utils.dart';
import '../core/gps_attendance_constants.dart';
import '../core/production_face_recognition_constants.dart';
import '../core/time_parse.dart';
import 'attendance_hours_calculator_service.dart';
import 'attendance_hours_persistence_service.dart';
import 'institute_lecture_timing_service.dart';
import 'device_fingerprint_service.dart';
import 'error_handler.dart';
import 'face_recognition_service.dart';
import 'firestore_retry_service.dart';
import 'geofence_service.dart';
import 'hierarchical_attendance_service.dart';
import 'institute_notification_service.dart';
import 'institute_status_service.dart';
import 'network_verification_service.dart';
import 'photo_verification_service.dart';
import 'gps_fence_sample.dart';
import 'stale_attendance_reconciliation_service.dart';
import 'storage_service.dart';
import 'suspicious_activity_service.dart';
import '../presentation/widgets/session_monitor.dart';
import '../presentation/widgets/manual_face_confirmation_dialog.dart';

/// Same document id as [AdminAttendanceScreen] (`instituteId_roll_date`).
String _teacherAttendanceId(String instituteId, String srNo, String date) =>
    '${instituteId}_${srNo}_$date';

Future<Map<String, dynamic>?> _getTeacherPayload(
  SupabaseClient db,
  String instituteId,
  String srNo,
  String date,
) async {
  final row = await db
      .from('teacher_attendance')
      .select()
      .eq('id', _teacherAttendanceId(instituteId, srNo, date))
      .maybeSingle();
  if (row == null) return null;
  final p = row['payload'];
  if (p is Map<String, dynamic>) return Map<String, dynamic>.from(p);
  if (p is Map) return p.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

/// Merge fresh attendance_in_out records into the payload
/// This ensures _decideNextMark() sees actual entry/exit data, not stale teacher_attendance
Future<Map<String, dynamic>> _mergeAttendanceInOutRecords(
  SupabaseClient db,
  String instituteId,
  String srNo,
  String date,
  Map<String, dynamic>? basePayload,
) async {
  final payload = basePayload != null
      ? Map<String, dynamic>.from(basePayload)
      : <String, dynamic>{};

  try {
    final instituteCodes = <String>{
      instituteId.trim(),
      (await instituteCodeForId(instituteId)).trim(),
    }..removeWhere((s) => s.isEmpty);

    // Query fresh attendance_in_out records for this student today
    final rows = await db
        .from('attendance_in_out')
        .select('id,type,photo_url,photo_path,created_at,additional')
        .inFilter('institute_code', instituteCodes.toList())
        .eq('sr_no', srNo)
        .eq('attendance_date', date)
        .order('created_at', ascending: false);

    if (rows.isEmpty) {
      return payload;
    }

    // Merge each record using same logic as student_management_screen.dart
    for (final row in rows) {
      final rowMap = Map<String, dynamic>.from(row as Map);
      final type = (rowMap['type']?.toString() ?? '').toLowerCase();
      final photoUrl = (rowMap['photo_url'] ?? '').toString().trim();
      final photoPath = (rowMap['photo_path'] ?? '').toString().trim();
      final createdAt = rowMap['created_at'];
      final add = rowMap['additional'] is Map
          ? Map<String, dynamic>.from((rowMap['additional'] as Map).cast<String, dynamic>())
          : <String, dynamic>{};

      if (type == 'exit') {
        // ✅ Entry record must exist before exit is processed, but don't overwrite if already set
        if (payload['exitPhoto'] == null && photoUrl.isNotEmpty) {
          payload['exitPhoto'] = photoUrl;
        }
        if (payload['exitPhotoPath'] == null && photoPath.isNotEmpty) {
          payload['exitPhotoPath'] = photoPath;
        }
        if (payload['exitTime'] == null) {
          payload['exitTime'] = add['exitTime'] ?? createdAt;
        }
        // ✅ FIXED: Safe string conversion for status
        final status = add['status'];
        if (status != null) {
          payload['status'] = status is String ? status : status.toString();
        }
      } else if (type == 'entry') {
        // Entry record
        if (payload['entryPhoto'] == null && photoUrl.isNotEmpty) {
          payload['entryPhoto'] = photoUrl;
        }
        if (payload['entryPhotoPath'] == null && photoPath.isNotEmpty) {
          payload['entryPhotoPath'] = photoPath;
        }
        if (payload['photoUrl'] == null && photoUrl.isNotEmpty) {
          payload['photoUrl'] = photoUrl;
        }
        if (payload['entryTime'] == null) {
          payload['entryTime'] = add['entryTime'] ?? createdAt;
        }
        if (payload['entrySessionEmbedding'] == null) {
          final parsed = _parseDoubleListFromDynamic(add['entrySessionEmbedding']);
          if (parsed != null) {
            payload['entrySessionEmbedding'] = parsed;
          }
        }
        // ✅ FIXED: Safe string conversion for status
        final status = add['status'];
        if (status != null) {
          payload['status'] = status is String ? status : status.toString();
        }
      }
    }

    return payload;
  } catch (e) {
    if (kDebugMode) debugPrint('⚠️ Failed to merge attendance_in_out: $e');
    return payload;
  }
}


Future<void> _upsertTeacherDoc(
  SupabaseClient db,
  String instituteId,
  String srNo,
  String date,
  Map<String, dynamic> payload,
) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.from('teacher_attendance').upsert(
    {
      'id': _teacherAttendanceId(instituteId, srNo, date),
      'institute_id': instituteId,
      // Roll key (official sr_no), not auth user_id or students.id UUID.
      'student_id': srNo,
      'date': date,
      'status': payload['status']?.toString(),
      'payload': payload,
      'updated_at': now,
    },
    onConflict: 'id',
  );
}

List<double>? _parseDoubleListFromDynamic(dynamic v) {
  if (v is! List || v.isEmpty) return null;
  try {
    return v.map((e) => (e as num).toDouble()).toList();
  } catch (_) {
    return null;
  }
}

String? _nonEmptyString(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<List<double>?> _tryEmbeddingFromEntryPhotoUrl(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) return null;
  try {
    final res = await http.get(Uri.parse(trimmed));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final tmp = File('${dir.path}/entry_ref_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tmp.writeAsBytes(res.bodyBytes, flush: true);
    final emb = await FaceRecognitionService.extractAttendanceSessionEmbedding(tmp.path);
    try {
      await tmp.delete();
    } catch (_) {}
    return emb;
  } catch (e) {
    if (kDebugMode) debugPrint('entry URL embedding fallback: $e');
    return null;
  }
}

Future<void> _syncAttendanceInOut({
  required String instituteId,
  required String srNo,
  required String date,
  required String type,
  required String photoUrl,
  String? photoPath,
  String? photoFileId,
  required String recordedAtUtc,
  String? subject,
  String? sessionEntryUtc,
  String? sessionExitUtc,
  double? hours,
  String? status,
  List<double>? entrySessionEmbedding,
}) async {
  try {
    final key = srNo.trim();
    var row = await appDb
        .from('students')
        .select('id,name,user_id,sr_no')
        .eq('institute_id', instituteId)
        .eq('sr_no', key)
        .maybeSingle();
    row ??= await appDb
        .from('students')
        .select('id,name,user_id,sr_no')
        .eq('institute_id', instituteId)
        .eq('user_id', key)
        .maybeSingle();
    if (row == null) {
      if (kDebugMode) debugPrint('⚠️ attendance_in_out sync: no student row for srNo $srNo');
      return;
    }
    final sid = row['id'] as String;
    final name = row['name'] as String? ?? '';
    final studentSrNo = attendanceSrNoFromStudentRow(row);
    if (studentSrNo == null) {
      if (kDebugMode) {
        debugPrint('⚠️ attendance_in_out sync: student ${row['id']} has no sr_no — skip');
      }
      return;
    }
    final subj = subject?.trim();
    final additionalData = <String, dynamic>{
      'srNo': studentSrNo,
      'source': 'student_management_quick',
      if (subj != null && subj.isNotEmpty) 'subject': subj,
      if (sessionEntryUtc != null && sessionEntryUtc.trim().isNotEmpty)
        'entryTime': sessionEntryUtc.trim(),
      if (sessionExitUtc != null && sessionExitUtc.trim().isNotEmpty)
        'exitTime': sessionExitUtc.trim(),
    };
    if (hours != null) additionalData['hours'] = hours;
    if (status != null && status.isNotEmpty) additionalData['status'] = status;
    if (entrySessionEmbedding != null &&
        entrySessionEmbedding.isNotEmpty &&
        type.toLowerCase() == 'entry') {
      additionalData['entrySessionEmbedding'] = entrySessionEmbedding;
    }

    await HierarchicalAttendanceService().saveAttendance(
      instituteCode: instituteId,
      studentId: sid,
      studentName: name,
      srNo: studentSrNo,
      date: date,
      type: type,
      photoUrl: photoUrl,
      photoPath: photoPath,
      photoFileId: photoFileId,
      recordedAtUtcIso: recordedAtUtc,
      additionalData: additionalData,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('❌ attendance_in_out sync failed: $e');
    rethrow; // Allow errors to bubble up so marking fails gracefully
  }
}

dynamic _encodeSv() => DateTime.now().toUtc().toIso8601String();

DateTime? _asDateTime(dynamic v) => parseAnyTimestamp(v);

TimeOfDay? _parseTimeString(String timeStr) {
  try {
    timeStr = timeStr.trim().toUpperCase();
    final hasAmPm = timeStr.contains('AM') || timeStr.contains('PM');
    final isPM = timeStr.contains('PM');
    timeStr = timeStr.replaceAll('AM', '').replaceAll('PM', '').trim();
    final parts = timeStr.split(':');
    if (parts.length != 2) return null;
    var hour = int.parse(parts[0].trim());
    final minute = int.parse(parts[1].trim());
    if (hasAmPm) {
      if (isPM && hour != 12) {
        hour += 12;
      } else if (!isPM && hour == 12) {
        hour = 0;
      }
    }
    return TimeOfDay(hour: hour, minute: minute);
  } catch (e) {
    if (kDebugMode) debugPrint('Error parsing time string: $e');
    return null;
  }
}

List<Map<String, TimeOfDay>> _parseLectureTiming(String timing) {
  if (timing.isEmpty) return [];
  final List<Map<String, TimeOfDay>> lectures = [];
  try {
    final lectureStrings = timing.split(',');
    for (var lectureStr in lectureStrings) {
      lectureStr = lectureStr.trim();
      final parts = lectureStr.split(RegExp(r'[-–—]'));
      if (parts.length == 2) {
        final startTime = _parseTimeString(parts[0].trim());
        final endTime = _parseTimeString(parts[1].trim());
        if (startTime != null && endTime != null) {
          lectures.add({'start': startTime, 'end': endTime});
        }
      }
    }
  } catch (e) {
    if (kDebugMode) debugPrint('Error parsing lecture timing: $e');
  }
  return lectures;
}

/// Next action for today: entry, exit, lecture face scan, or already complete.
class _QuickMarkDecision {
  final String mode; // entry | exit | lecture_scan | complete
  final int? lectureIndex;

  const _QuickMarkDecision(this.mode, [this.lectureIndex]);
}

_QuickMarkDecision _decideNextMark(
  Map<String, dynamic>? data,
  String timing,
) {
  final lectureTimes = _parseLectureTiming(timing);
  if (data == null) {
    return const _QuickMarkDecision('entry');
  }
  // ✅ FIXED: Check ALL possible entry field names (snake_case and camelCase)
  // Entry is marked if: photo_url, entry_photo_url, entryTime, or entry_time exists
  final additionalData = data['additional'] is Map ? (data['additional'] as Map) : {};
  final hasEntry = data['photo_url'] != null ||
      data['entry_photo_url'] != null ||
      data['entryTime'] != null ||
      data['entry_time'] != null ||
      additionalData['entryTime'] != null ||
      additionalData['entry_time'] != null;
  final lectures = data['lectures'] as Map<String, dynamic>? ?? {};

  if (!hasEntry) {
    return const _QuickMarkDecision('entry');
  }
  // Entry exists, proceed to exit
  // Even if entry time is missing/corrupted, allow exit and calculate based on available data
  {
    if (lectureTimes.isNotEmpty) {
      final currentTime = DateTime.now();
      final currentMinutes = currentTime.hour * 60 + currentTime.minute;
      for (int i = 0; i < lectureTimes.length; i++) {
        final lecture = lectureTimes[i];
        final start = lecture['start'] as TimeOfDay;
        final end = lecture['end'] as TimeOfDay;
        final startMinutes = start.hour * 60 + start.minute;
        final endMinutes = end.hour * 60 + end.minute;
        if (currentMinutes >= startMinutes && currentMinutes <= endMinutes) {
          final lectureKey = 'lecture_${i + 1}';
          final slot = lectures[lectureKey];
          if (slot == null || (slot is Map && slot['faceScanPhoto'] == null)) {
            return _QuickMarkDecision('lecture_scan', i);
          }
        }
      }
    }
    return const _QuickMarkDecision('exit');
  }
  return const _QuickMarkDecision('complete');
}

// ── Per-subject attendance (same shape as AdminAttendanceScreen) ─────────────

const String _kSubjectSessionsKey = 'subjectSessions';

String? _canonicalSubjectFromEnrollment(List<String> enrolled, String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  for (final e in enrolled) {
    if (e.trim() == t) return e;
  }
  return null;
}

Map<String, Map<String, dynamic>> _mapSubjectSessions(Map<String, dynamic>? payload) {
  if (payload == null) return {};
  final raw = payload[_kSubjectSessionsKey];
  if (raw is! Map) return {};
  final out = <String, Map<String, dynamic>>{};
  raw.forEach((k, v) {
    if (v is Map) {
      out[k.toString()] = Map<String, dynamic>.from(v.cast<String, dynamic>());
    }
  });
  return out;
}

Map<String, dynamic> _sessionForSubject(
  Map<String, Map<String, dynamic>> sessions,
  String subject,
) {
  return Map<String, dynamic>.from(sessions[subject] ?? {});
}

bool _sessionHasEntryMap(Map<String, dynamic> s) {
  // ✅ Check actual schema: photo_url OR entryTime (check top-level and additional JSON)
  final additionalEntryTime = s['additional'] is Map ? (s['additional'] as Map)['entryTime'] : null;
  return s['photo_url'] != null ||
      s['entryTime'] != null ||
      additionalEntryTime != null ||
      s['entryPhoto'] != null ||
      s['photoUrl'] != null;
}

bool _sessionCompleteMap(Map<String, dynamic> s) {
  // ✅ Check actual fields in subject session (no type field - merged structure)
  return s['exitPhoto'] != null ||
      s['exitTime'] != null;
}

String? _pendingSubjectFromPayload(Map<String, dynamic>? payload) {
  if (payload == null) return null;
  final m = _mapSubjectSessions(payload);
  for (final e in m.entries) {
    if (_sessionHasEntryMap(e.value) && !_sessionCompleteMap(e.value)) return e.key;
  }
  return null;
}

/// Earlier subjects in enrollment must each have entry + exit before a later subject may start entry.
String? _sequentialPriorIncompleteSubject(
  List<String> enrolledOrder,
  Map<String, Map<String, dynamic>> sessions,
  String subject,
) {
  final idx = enrolledOrder.indexOf(subject);
  if (idx <= 0) return null;
  for (var j = 0; j < idx; j++) {
    final prev = enrolledOrder[j];
    final sess = _sessionForSubject(sessions, prev);
    if (!_sessionCompleteMap(sess)) return prev;
  }
  return null;
}

/// After the calendar day changes, manual exit photo is never allowed (reconcile auto-close only).
Future<bool> _inlineAbortManualExitIfDeadlinePassed({
  required ScaffoldMessengerState messenger,
  required SupabaseClient db,
  required String instituteId,
  required String srNo,
  required String today,
  required List<String> enrolledSubjects,
  required Map<String, dynamic>? payload,
  required bool useSubjects,
  required String? activeSubject,
  required String timing,
}) async {
  final nowUtc = DateTime.now().toUtc();
  DateTime? entryUtc;
  if (useSubjects && activeSubject != null) {
    final sm = _mapSubjectSessions(payload);
    final s = _sessionForSubject(sm, activeSubject);
    entryUtc = parseAnyTimestamp(s['entryTime']) ?? parseAnyTimestamp(s['timestamp']);
  } else if (payload != null) {
    entryUtc =
        parseAnyTimestamp(payload['entryTime']) ?? parseAnyTimestamp(payload['timestamp']);
  }
  if (entryUtc == null) return false;

  if (!isPastAttendanceExitDeadline(entryUtc, nowUtc, enrolledSubjects.length)) return false;

  final repaired = await StaleAttendanceReconciliationService.ensureReconciled(
    db: db,
    instituteId: instituteId,
    srNo: srNo,
    date: today,
    enrolledSubjects: enrolledSubjects,
    existingPayload: payload,
  );

  final red = useSubjects && activeSubject != null
      ? _decideNextMarkSubject(repaired, activeSubject)
      : _decideNextMark(repaired, timing);

  if (red.mode != 'exit') {
    final msg = red.mode == 'complete'
        ? (useSubjects && activeSubject != null
            ? 'Exit window ended at midnight. "$activeSubject" was auto-closed (no exit photo; 1 h credit).'
            : 'Exit window ended at midnight. Session auto-closed (no exit photo; 1 h credit).')
        : 'Attendance was updated — try again.';
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 6),
      ),
    );
    return true;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Exit is no longer available because the day has already rolled over.',
      ),
      backgroundColor: Colors.orange,
      duration: const Duration(seconds: 6),
    ),
  );
  return true;
}

bool _isLegacyAttendanceDoc(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return false;
  final ss = data[_kSubjectSessionsKey];
  if (ss is Map && ss.isNotEmpty) return false;
  // ✅ Check actual schema fields
  final hasTop = (data['photo_url'] != null) ||
      data['entryPhoto'] != null ||
      data['entryTime'] != null ||
      data['photoUrl'] != null ||
      data['exitPhoto'] != null ||
      data['exitTime'] != null;
  return hasTop;
}

/// Legacy [teacher_attendance] rows store one entry/exit at the top level. When the student has
/// multiple subjects, [InlineStudentAttendanceService] and Admin need `subjectSessions`. Move
/// today's top-level marks into the first enrolled subject so staff can continue from Student Management
/// (they do not have the admin dashboard / Mark Attendance tab).
Map<String, dynamic> _migrateLegacyToFirstSubjectSession(
  Map<String, dynamic> legacy,
  String firstSubject,
) {
  final out = Map<String, dynamic>.from(legacy);
  final sess = <String, dynamic>{};
  const moveKeys = <String>[
    'entryPhoto',
    'entryTime',
    'entryPhotoPath',
    'entryPhotoFileId',
    'exitPhoto',
    'exitTime',
    'exitPhotoPath',
    'exitPhotoFileId',
    'photoUrl',
    'timestamp',
  ];
  for (final k in moveKeys) {
    if (out.containsKey(k)) sess[k] = out.remove(k);
  }
  if (out.containsKey('status')) sess['status'] = out.remove('status');
  if (sess.isNotEmpty) {
    sess['subjectName'] = firstSubject;
    out[_kSubjectSessionsKey] = {firstSubject: sess};
  }
  return out;
}

bool _allSubjectsCompleteInPayload(Map<String, dynamic>? payload, List<String> subjects) {
  if (subjects.isEmpty) return false;
  final m = _mapSubjectSessions(payload);
  for (final s in subjects) {
    if (!_sessionCompleteMap(_sessionForSubject(m, s))) return false;
  }
  return true;
}

_QuickMarkDecision _decideNextMarkSubject(
  Map<String, dynamic>? data,
  String subject,
) {
  final sessions = _mapSubjectSessions(data);
  final sess = _sessionForSubject(sessions, subject);
  final hasEntry = _sessionHasEntryMap(sess);
  final hasExit = _sessionCompleteMap(sess);
  if (!hasEntry) return const _QuickMarkDecision('entry');
  if (hasEntry && !hasExit) return const _QuickMarkDecision('exit');
  return const _QuickMarkDecision('complete');
}

Future<String?> _pickAttendanceSubjectSheet(
  BuildContext context,
  List<String> subjects,
  Map<String, dynamic>? existingPayload,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final bottom = MediaQuery.viewPaddingOf(ctx).bottom;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select subject',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Strict flow: finish exit for any in-progress session first, then subjects in list order '
                  '(full entry + exit each). ✓ = fully done.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 8),
              ...subjects.map((sub) {
                final sessions = _mapSubjectSessions(existingPayload);
                final sess = _sessionForSubject(sessions, sub);
                final done = _sessionCompleteMap(sess);
                final started = _sessionHasEntryMap(sess);
                final pending = _pendingSubjectFromPayload(existingPayload);
                final locked = pending != null && pending != sub;
                final seqPrior =
                    _sequentialPriorIncompleteSubject(subjects, sessions, sub);
                final blockedByOrder =
                    seqPrior != null && !started && !done;
                final cannotPick = done || locked || blockedByOrder;
                return ListTile(
                  leading: Icon(
                    done ? Icons.check_circle : Icons.book_outlined,
                    color: done ? Colors.green : Colors.blueGrey,
                  ),
                  title: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    done
                        ? 'Complete today'
                        : (locked
                            ? 'Finish "$pending" exit first'
                            : (blockedByOrder
                                ? 'Finish "$seqPrior" (entry + exit) first'
                                : (started
                                    ? 'Exit photo needed'
                                    : 'Entry photo first'))),
                  ),
                  enabled: !cannotPick,
                  onTap: cannotPick
                      ? null
                      : () => Navigator.pop(ctx, sub),
                );
              }),
            ],
          ),
        ),
      );
    },
  );
}

Future<Uint8List> _compressImage(Uint8List imageBytes, {required int maxSizeKB}) async {
  try {
    final maxSizeBytes = maxSizeKB * 1024;
    var decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) return imageBytes;

    // Apply EXIF orientation to pixels and strip metadata
    // This often fixes "Invalid SOS parameters" by recreating the image from raw pixels
    decodedImage = img.bakeOrientation(decodedImage);

    // Re-create a clean Image object to ensure no lingering problematic metadata
    final cleanImage = img.Image.from(decodedImage);

    // Quality 85 is often safer than 80 for avoiding certain libjpeg artifacts
    int quality = 85;
    Uint8List compressedBytes = Uint8List.fromList(img.encodeJpg(cleanImage, quality: quality));

    // If size is okay, return now (Sequential JPEG is the default for 'image' package)
    if (compressedBytes.length <= maxSizeBytes) {
      return compressedBytes;
    }

    // If still too large, try resizing
    if (compressedBytes.length > maxSizeBytes) {
      final scale = compressedBytes.length > maxSizeBytes * 2 ? 0.5 : 0.7;
      final newWidth = (cleanImage.width * scale).round();
      final newHeight = (cleanImage.height * scale).round();
      final resized = img.copyResize(cleanImage, width: newWidth, height: newHeight);

      while (quality > 30) {
        compressedBytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
        if (compressedBytes.length <= maxSizeBytes) break;
        quality -= 10;
      }
    }

    return compressedBytes;
  } catch (e) {
    if (kDebugMode) debugPrint('❌ Error compressing image: $e');
    return imageBytes;
  }
}

/// [gps_settings] rows are keyed by institute admin. Attendance staff uses that same fence.
Future<String?> _gpsFenceAdminIdForInline(SupabaseClient db, String instituteId) async {
  final uid = db.auth.currentUser?.id;
  if (uid == null) return null;
  try {
    final me = await db.from('profiles').select('role').eq('id', uid).maybeSingle();
    if ((me?['role'] as String?) != 'attendance_user') return uid;

    final fenceAdmin = await GeofenceService().lockedFenceAdminIdForInstitute(instituteId);
    if (fenceAdmin != null && fenceAdmin.isNotEmpty) return fenceAdmin;

    final adminRow = await db
        .from('profiles')
        .select('id')
        .eq('institute_id', instituteId)
        .eq('role', 'admin')
        .limit(1)
        .maybeSingle();
    return (adminRow?['id'] as String?) ?? uid;
  } catch (_) {
    return uid;
  }
}

DateTime? _lastInlineGpsSuccessAtUtc;

bool _canReuseRecentInlineGpsSuccess() {
  final t = _lastInlineGpsSuccessAtUtc;
  if (t == null) return false;
  return DateTime.now().toUtc().difference(t) <= const Duration(seconds: 90);
}

Future<bool> _checkGPSRadius(BuildContext context, String instituteId) async {
  if (kIsWeb) return true;
  final db = appDb;
  final currentUser = db.auth.currentUser;
  if (currentUser == null) return false;
  try {
    final fenceAdminId = await _gpsFenceAdminIdForInline(db, instituteId);
    if (fenceAdminId == null) return false;
    final configRow = await db
        .from('gps_settings')
        .select()
        .eq('institute_id', instituteId)
        .eq('admin_id', fenceAdminId)
        .maybeSingle();

    if (configRow == null) {
      if (context.mounted) {
        scaffoldMessengerOr(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Location not verified. Please go to GPS Settings and verify your location first.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return false;
    }

    final latitude = (configRow['latitude'] as num?)?.toDouble();
    final longitude = (configRow['longitude'] as num?)?.toDouble();
    final isLocked = configRow['is_locked'] == true;
    final double radius = kAttendanceFenceRadiusMeters;

    if (latitude == null || longitude == null || latitude == 0.0 || longitude == 0.0) {
      if (context.mounted) {
        scaffoldMessengerOr(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Location not verified. Please go to GPS Settings and verify your location first.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return false;
    }

    if (!isLocked) {
      if (context.mounted) {
        scaffoldMessengerOr(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Location not locked. Please verify location in GPS Settings first.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return false;
    }

    // Show checking location message while GPS check is in progress
    if (context.mounted) {
      scaffoldMessengerOr(context).showSnackBar(
        const SnackBar(
          content: Text('🔍 Checking location...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 30),
        ),
      );
    }

    if (kDebugMode) debugPrint('🔴 Starting GPS sampling against fence...');
    final sample = await samplePositionAgainstFence(
      fenceLat: latitude,
      fenceLng: longitude,
      radiusMeters: radius,
      maxSamples: kAttendanceGpsFastMaxSamples,
      delayBetweenSamples:
          Duration(milliseconds: kAttendanceGpsFastDelayBetweenMs),
      firstSampleTimeoutSeconds: kAttendanceGpsFastFirstTimeoutSec,
      laterSampleTimeoutSeconds: kAttendanceGpsFastLaterTimeoutSec,
      preSampleStabilizationDelay:
          Duration(milliseconds: kAttendanceGpsFastStabilizationMs),
      tryRecentLastKnownFirst: kAttendanceGpsTryLastKnownFirst,
      lastKnownMaxAge:
          Duration(minutes: kAttendanceGpsLastKnownMaxAgeMinutes),
    );
    if (kDebugMode) {
      debugPrint('✅ GPS sampling complete:');
      debugPrint('   - isWithinFence: ${sample.isWithinFence}');
      debugPrint('   - bestDistanceMeters: ${sample.bestDistanceMeters}');
      debugPrint('   - mockedDetected: ${sample.mockedDetected}');
      debugPrint('   - errorMessage: ${sample.errorMessage}');
    }

    if (sample.mockedDetected) {
      if (context.mounted) {
        scaffoldMessengerOr(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Fake GPS detected. Please turn off Mock Location apps.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 8),
          ),
        );
      }
      return false;
    }

    if (sample.errorMessage != null) {
      if (context.mounted) {
        scaffoldMessengerOr(context).showSnackBar(
          SnackBar(
            content: Text(sample.errorMessage!),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return false;
    }

    if (!sample.isWithinFence) {
      if (context.mounted) {
        scaffoldMessengerOr(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Out of radius: closest ~${sample.bestDistanceMeters.toStringAsFixed(0)} m '
              '(allowed ~${kAttendanceMaxEffectiveFenceMeters.toStringAsFixed(0)} m with GPS tolerance). '
              'If you are at the institute, open GPS Settings and verify location again from your classroom.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
      }
      return false;
    }

    // Cache recent success to prevent immediate re-check loops when marking Exit
    // right after Entry from the same screen/session.
    _lastInlineGpsSuccessAtUtc = DateTime.now().toUtc();

    // Location OK - return true, camera will open in next step
    if (kDebugMode) debugPrint('🟢 GPS check PASSED - returning true to open camera');
    return true;
  } catch (e) {
    if (kDebugMode) debugPrint('❌ Exception in _checkGPSRadius: $e');
    if (context.mounted) {
      scaffoldMessengerOr(context).showSnackBar(
        SnackBar(
          content: Text(
            'Location check failed: ${ErrorHandler.handleError(e, context: 'gps_radius_inline')}',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
    return false;
  }
}

/// Mark attendance from Student Management: opens camera only (entry / exit / lecture scan as needed).
class InlineStudentAttendanceService {
  InlineStudentAttendanceService._();

  /// Pre-warm GPS while auto-scan is open so the first mark skips live sampling.
  static Future<void> warmGpsForInstitute(
    BuildContext context,
    String instituteId,
  ) async {
    if (kIsWeb || _canReuseRecentInlineGpsSuccess()) return;
    if (!context.mounted) return;
    unawaited(_checkGPSRadius(context, instituteId));
  }

  static Future<void> markForRoll(
    BuildContext context, {
    required String instituteId,
    required String srNo,
    String? studentId,  // ✅ NEW: Direct student ID lookup (most secure)
    String? chosenSubject,
    String? explicitStep,
    String? preCapturedPhotoPath,
    bool productionPipelineVerified = false,
    double? productionSimilarity,
  }) async {
    if (kDebugMode) {
      debugPrint('🎯 markForRoll called for sr_no=$srNo, studentId=$studentId');
    }
    final studentSrNo = srNo.trim();
    if (studentSrNo.isEmpty && (studentId == null || studentId.isEmpty)) {
      if (kDebugMode) debugPrint('❌ markForRoll: both srNo and studentId are empty');
      return;
    }
    if (!context.mounted) {
      if (kDebugMode) debugPrint('❌ markForRoll: context not mounted');
      return;
    }

    final db = appDb;
    final messenger = scaffoldMessengerOr(context);
    String? forcedStep;
    final stepNorm = explicitStep?.trim().toLowerCase();
    if (stepNorm != null && stepNorm.isNotEmpty) {
      if (stepNorm != 'entry' && stepNorm != 'exit') {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Invalid attendance step.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      forcedStep = stepNorm;
    }
    if (kDebugMode) debugPrint('✅ markForRoll: initialized, checking institute block message');

    try {
      if (kDebugMode) debugPrint('🎬 Starting simple attendance marking...');
      // Same messenger as Student Management loading bar — dismiss it so later messages show.
      messenger.hideCurrentSnackBar();

      final fastAutoScanMark = productionPipelineVerified &&
          (productionSimilarity ?? 0) >=
              ProductionFaceRecognitionConstants
                  .onDeviceRecognitionConfidenceThreshold &&
          preCapturedPhotoPath != null &&
          preCapturedPhotoPath.trim().isNotEmpty;

      // Step 1: Check GPS location
      if (kDebugMode) debugPrint('📍 Checking GPS location...');
      if (!kIsWeb) {
        final gpsOk = await GeofenceService().hasValidPersonalGpsForCurrentAdmin();
        if (!gpsOk) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Lock attendance zone in GPS Settings first.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
          return;
        }

        if (!_canReuseRecentInlineGpsSuccess()) {
          final locationCheck = await _checkGPSRadius(context, instituteId);
          if (!locationCheck) {
            if (kDebugMode) debugPrint('❌ Location check failed, not opening camera');
            return;
          }
        } else if (kDebugMode) {
          debugPrint('♻️ Reusing recent GPS success (within 90s)');
        }
        if (kDebugMode) debugPrint('✅ Location check passed, proceeding...');
      }

      if (kDebugMode) debugPrint('✅ GPS location check completed, fetching student data...');

      // ✅ PRIORITY: If studentId provided, use direct lookup (most secure)
      var studentRow;
      final providedStudentId = studentId;  // ✅ Use parameter value
      if (providedStudentId != null && providedStudentId.isNotEmpty) {
        studentRow = await db
            .from('students')
            .select()
            .eq('id', providedStudentId.trim())
            .eq('institute_id', instituteId)
            .maybeSingle();
        if (kDebugMode) {
          debugPrint(
            '🔍 Direct lookup by studentId+institute: ${studentRow != null ? "FOUND" : "NOT FOUND"}',
          );
        }
      }

      // Fallback: Look up by user_id or sr_no if direct ID lookup failed
      studentRow ??= await db
          .from('students')
          .select()
          .eq('institute_id', instituteId)
          .eq('user_id', studentSrNo)
          .maybeSingle();
      studentRow ??= await db
          .from('students')
          .select()
          .eq('institute_id', instituteId)
          .eq('sr_no', studentSrNo)
          .maybeSingle();

      if (studentRow == null) {
        if (kDebugMode) debugPrint('❌ Student not found');
        messenger.showSnackBar(
          const SnackBar(content: Text('Student not found.'), backgroundColor: Colors.red),
        );
        return;
      }

      final studentData = Map<String, dynamic>.from(studentRow);
      final rowInstitute = studentData['institute_id']?.toString().trim() ?? '';
      if (rowInstitute.isEmpty || rowInstitute != instituteId.trim()) {
        if (kDebugMode) {
          debugPrint('❌ Institute mismatch: row=$rowInstitute session=$instituteId');
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'This student does not belong to your institute. Pull down to refresh the list.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 6),
          ),
        );
        return;
      }

      final enrollmentStatus =
          (studentData['status']?.toString() ?? 'approved').trim().toLowerCase();
      if (enrollmentStatus != 'approved') {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Attendance is only for approved students (current status: $enrollmentStatus). '
              'Approve this profile in student records first.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 7),
          ),
        );
        return;
      }
      final retrievedStudentId = studentData['id']?.toString() ?? 'UNKNOWN';
      final retrievedStudentName = studentData['name']?.toString() ?? 'UNKNOWN';

      /// Single roll key for `teacher_attendance`, `attendance_in_out`, storage — always official `sr_no`.
      final attendanceRollKey = attendanceSrNoFromStudentRow(studentData);
      if (attendanceRollKey == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'This student has no SR No on file. Add SR No in student records before marking attendance.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 6),
          ),
        );
        return;
      }

      // ✅ DEBUG: Confirm which student was found
      if (kDebugMode) {
        debugPrint(
          '✅ Student FOUND: $retrievedStudentName (ID: $retrievedStudentId, '
          'attendanceRollKey=$attendanceRollKey, uiSrParam=$studentSrNo)',
        );
      }

      // ✅ Handle subjects as List or Map or String
      List<String> enrolledSubjects = <String>[];
      final rawSubjects = studentData['subjects'];

      if (rawSubjects is List) {
        enrolledSubjects = rawSubjects
            .map((s) => s.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (rawSubjects is Map) {
        // If subjects is a Map, extract values
        enrolledSubjects = (rawSubjects as Map).values
            .map((s) => s.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (rawSubjects is String) {
        final trimmed = rawSubjects.trim();
        if (trimmed.isNotEmpty) enrolledSubjects = [trimmed];
      }

      // Fallback to single subject field
      if (enrolledSubjects.isEmpty) {
        final single = studentData['subject']?.toString().trim() ?? '';
        if (single.isNotEmpty) enrolledSubjects = [single];
      }

      final studentStoredSlots =
          studentData['lectureTiming'] as String? ??
          studentData['lecture_timing'] as String?;

      if (!studentHasNonEmptyFaceEmbedding(studentData['face_embedding'])) {
        if (kDebugMode) debugPrint('⚠️ No face embedding on roster — proceeding; staff confirmation after capture');
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No face enrollment on file — after the photo, staff may need to confirm identity.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      if (kDebugMode) debugPrint('✅ Proceeding to load today\'s attendance row (then camera)...');

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (kDebugMode) debugPrint('⏳ Parallel: institute timing + teacher_attendance fetch...');
      final loaded = await Future.wait<Object?>([
        InstituteLectureTimingService().buildLectureTimingString(instituteId),
        _getTeacherPayload(db, instituteId, attendanceRollKey, today),
      ]);
      final instituteSlots = loaded[0]! as String;
      var existingPayload = loaded[1] as Map<String, dynamic>?;
      final timing = (studentStoredSlots != null && studentStoredSlots.trim().isNotEmpty)
          ? studentStoredSlots.trim()
          : instituteSlots;
      if (kDebugMode) debugPrint('⏳ Timing/payload done. Legacy migrate + reconcile...');

      if (existingPayload != null &&
          enrolledSubjects.length > 1 &&
          _isLegacyAttendanceDoc(existingPayload)) {
        final chosen =
            pickEnrollmentSubjectForAutoClose(enrolledSubjects) ?? enrolledSubjects.first;
        final migrated = _migrateLegacyToFirstSubjectSession(
          Map<String, dynamic>.from(existingPayload),
          chosen,
        );
        if (!_isLegacyAttendanceDoc(migrated)) {
          await _upsertTeacherDoc(db, instituteId, attendanceRollKey, today, migrated);
          existingPayload = migrated;
        }
      }

      final payloadBeforeReconcile = existingPayload;
      if (!fastAutoScanMark) {
        try {
          existingPayload =
              await StaleAttendanceReconciliationService.ensureReconciled(
            db: db,
            instituteId: instituteId,
            srNo: attendanceRollKey,
            date: today,
            enrolledSubjects: enrolledSubjects,
            existingPayload: existingPayload,
          ).timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              if (kDebugMode) {
                debugPrint(
                  '⚠️ ensureReconciled timed out (25s) — continuing without server reconcile',
                );
              }
              return payloadBeforeReconcile;
            },
          );
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ ensureReconciled failed: $e');
          existingPayload = payloadBeforeReconcile;
        }
      } else if (kDebugMode) {
        debugPrint('⚡ Auto-scan fast mark — skipping ensureReconciled');
      }

      const bool useSubjects = false;
      final String? activeSubject = null;

      // ✅ MERGE FRESH attendance_in_out records before checking entry/exit state
      // This ensures _decideNextMark() sees actual entry/exit data, not stale teacher_attendance
      if (kDebugMode) debugPrint('⏳ Merging fresh attendance_in_out records...');
      existingPayload = await _mergeAttendanceInOutRecords(
        db,
        instituteId,
        attendanceRollKey,
        today,
        existingPayload,
      );
      if (kDebugMode) {
        debugPrint('✅ Merged. Checking entry/exit state:');
        if (existingPayload != null) {
          debugPrint('   entryTime: ${existingPayload['entryTime'] ?? "null"}');
          debugPrint('   entryPhoto: ${existingPayload['entryPhoto'] != null ? "present" : "null"}');
          debugPrint('   exitTime: ${existingPayload['exitTime'] ?? "null"}');
          debugPrint('   exitPhoto: ${existingPayload['exitPhoto'] != null ? "present" : "null"}');
        }
      }

      final _QuickMarkDecision decision = _decideNextMark(existingPayload, timing);
      if (kDebugMode) {
        debugPrint('⏳ Next mark decision: mode=${decision.mode} lectureIdx=${decision.lectureIndex}');
        if (existingPayload != null) {
          // ✅ FIXED: Check actual fields in merged payload (no type field)
          final hasEntry = existingPayload['photo_url'] != null || existingPayload['entryTime'] != null;
          final hasExit = existingPayload['exitTime'] != null;
          debugPrint('   📊 existingPayload hasEntry: $hasEntry (entryTime: ${existingPayload['entryTime'] != null})');
          debugPrint('   📊 existingPayload hasExit: $hasExit (exitTime: ${existingPayload['exitTime'] != null})');
          debugPrint('   📊 existingPayload.entryTime: ${existingPayload['entryTime'] ?? "null"}');
        } else {
          debugPrint('   ⚠️ existingPayload is NULL');
        }
      }

      if (decision.mode == 'complete') {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Attendance already complete today for $attendanceRollKey (entry & exit on record).\n'
              'If the card looked open, pull down to refresh — thumbnails use attendance_in_out; '
              'marking uses teacher_attendance.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 8),
          ),
        );
        return;
      }

      if (forcedStep != null) {
        if (decision.mode == 'lecture_scan') {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'This student\'s attendance uses lecture-period scans today — complete those steps in the main attendance flow.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
          return;
        }
        // ✅ UPDATED: Exit no longer requires Entry - students can mark exit independently
        // Only requirement: registered face (photo match)
        if (forcedStep != decision.mode) {
          if (forcedStep == 'entry' && decision.mode == 'exit') {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Entry already recorded — tap Exit (yellow).'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          } else if (forcedStep == 'exit' && decision.mode == 'entry') {
            // Allow exit independently - no longer requires entry first
            // Exit can be marked anytime with just photo verification
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Attendance step does not match current state.'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
        }
      }

      // Keep Exit path available; credit/penalty is calculated during save.

      if (kDebugMode) debugPrint('📸 About to open camera for photo...');
      // Dismiss any SnackBars (e.g. long "Checking location…" from Student Management).
      // On some Android devices a visible SnackBar can block or confuse the camera Activity.
      messenger.clearSnackBars();
      if (!fastAutoScanMark) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!context.mounted) return;

      // Skip device fingerprinting to speed up camera opening
      // These background checks can happen asynchronously
      final markingTime = DateTime.now();

      // Fire and forget - don't wait for these
      unawaited(
        Future.microtask(() async {
          try {
            final deviceInfo = await DeviceFingerprintService.getDeviceInfoForLogging();
            final networkInfo = await NetworkVerificationService.getNetworkInfoForLogging();
            await SuspiciousActivityService.checkSuspiciousActivity(
              instituteId: instituteId,
              markedBy: db.auth.currentUser?.id ?? 'unknown',
              markingTime: markingTime,
              deviceFingerprint: deviceInfo['fingerprint'],
            );
          } catch (e) {
            if (kDebugMode) debugPrint('⚠️ Background checks failed: $e');
          }
        })
      );

      XFile? photo;
      if (preCapturedPhotoPath != null && preCapturedPhotoPath.trim().isNotEmpty) {
        photo = XFile(preCapturedPhotoPath.trim());
        if (kDebugMode) {
          debugPrint('📸 Using pre-captured photo from production face pipeline');
        }
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Use Auto Face Attendance to capture and mark entry/exit.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      if (kDebugMode) debugPrint('✅ Photo result: ${photo != null ? 'YES' : 'NO (cancelled)'}');

      if (!context.mounted) return;
      if (photo == null) {
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Camera did not return a photo. If you cancelled, try again. '
                'Emulators often have no camera — use a real device. '
                'Otherwise allow Camera permission in system settings.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
        }
        return;
      }

      // Align verification with actual capture time (not the clock at start of GPS / picker flow).
      final timeAtPhotoCapture = DateTime.now();

      // Extract embedding from FULL RESOLUTION before any compression
      Uint8List bytes = await photo.readAsBytes();

      // Compress and normalize to <100KB for B2B storage (maintains quality for embeddings)
      // Always run this to ensure Skia 122 fix (Sequential JPEG) and proper orientation
      bytes = await _compressImage(bytes, maxSizeKB: 100);

      if (!fastAutoScanMark) {
        final photoVerification = await PhotoVerificationService.verifyPhoto(
          photoPath: photo.path,
          markingTime: timeAtPhotoCapture,
          expectedLocation: null,
        );
        if (!photoVerification['isValid']) {
          final errors = photoVerification['errors'] as List<String>;
          if (context.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text('❌ Photo verification failed:\n${errors.join('\n')}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      }

      // Auto scan already ran ML Kit face detect + embedding match on this photo.
      final skipExtraPhotoChecks = fastAutoScanMark ||
          (productionPipelineVerified &&
              (productionSimilarity ?? 0) >=
                  ProductionFaceRecognitionConstants
                      .onDeviceRecognitionConfidenceThreshold);

      if (!skipExtraPhotoChecks) {
        if (await PhotoVerificationService.detectBlur(bytes)) {
          if (context.mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('⚠️ Photo is blurry. Please retake a clear photo.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        final faceDetection =
            await PhotoVerificationService.detectMultipleFaces(photo.path);
        if (faceDetection['isGroupPhoto'] == true) {
          if (context.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ Multiple faces (${faceDetection['faceCount']}). One student only.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      final photoPath = photo.path;

      if (!fastAutoScanMark) {
        messenger.clearSnackBars();
        messenger.showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '🔐 Face verification (on-device)...',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.blue,
          ),
        );
      }

      // Extract student info from database for manual confirmation dialog
      final studentPhotoUrl = _nonEmptyString(studentData['face_photo_url']) ?? '';

      StudentFaceVerifyResult faceResult;
      if (productionPipelineVerified &&
          (productionSimilarity ?? 0) >=
              ProductionFaceRecognitionConstants
                  .onDeviceRecognitionConfidenceThreshold) {
        faceResult = StudentFaceVerifyResult.match(
          similarityPercent: (productionSimilarity ?? 0) * 100,
        );
      } else {
        faceResult = await FaceRecognitionService.verifyStudent(
          photoPath,
          instituteId,
          retrievedStudentId != 'UNKNOWN' ? retrievedStudentId : attendanceRollKey,
          expectedStudentRowId: retrievedStudentId != 'UNKNOWN' ? retrievedStudentId : null,
        );
      }

      // ✅ Handle manual confirmation for genuine students with appearance changes
      if (faceResult.requiresManualConfirmation && context.mounted) {
        messenger.clearSnackBars();
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ Staff confirmation needed — compare photos and tap Confirm & Mark',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => ManualFaceConfirmationDialog(
            studentName: retrievedStudentName,
            studentSrNo: attendanceRollKey,
            registeredPhotoUrl: studentPhotoUrl,
            currentPhotoPath: photoPath,
            similarityPercent: faceResult.similarityPercent ?? 0,
            closestOtherSimilarityPercent: faceResult.closestOtherSimilarityPercent,
            closestOtherLabel: faceResult.closestOtherLabel,
            noEnrollmentStaffMode: faceResult.enrollmentEmbeddingMissing,
            comparisonContextNote: faceResult.enrollmentEmbeddingMissing
                ? 'Profile has no face embedding on file. Compare roster photo below (if any) '
                    'against the capture. Confirm only if staff are sure no other enrolled '
                    'student owns this identity.'
                : null,
            onConfirm: () => Navigator.pop(dialogContext, true),
            onCancel: () => Navigator.pop(dialogContext, false),
          ),
        );

        if (confirmed != true) {
          // User clicked Cancel - don't mark attendance
          if (context.mounted) {
            messenger.clearSnackBars();
            messenger.showSnackBar(
              const SnackBar(
                content: Text('❌ Attendance cancelled by staff'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        // User clicked Confirm - continue to mark attendance ✅
        if (context.mounted) {
          messenger.clearSnackBars();
        }
      } else if (!faceResult.isMatch) {
        if (context.mounted) {
          messenger.clearSnackBars();
          messenger.showSnackBar(
            SnackBar(
              content: Text(faceResult.message),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 10),
            ),
          );
        }
        return;
      }

      // Exit uses the same [verifyStudent] path as entry (enrollment embedding + cross-student rules).
      // No secondary comparison to today's entry photo.

      final runHeavyAntiSpoof =
          !(faceResult.isMatch &&
              (faceResult.similarityPercent ?? 0) >=
                  FaceMatchingThresholds.ATTENDANCE_VERIFICATION_THRESHOLD * 100);
      if (runHeavyAntiSpoof) {
        try {
          if (await PhotoVerificationService.detectPhotoOfPhoto(photoPath)) {
            if (context.mounted) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    '❌ This looks like a photo of a photo or screen. Take a live picture.',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ photo-of-photo check: $e');
        }
      }

      messenger.clearSnackBars();

      final maxSizeBytes = 100 * 1024; // Match compression target of 100KB
      if (bytes.length > maxSizeBytes) {
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Photo too large after processing. Please retake.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      Map<String, dynamic>? freshPayload;
      if (fastAutoScanMark) {
        freshPayload = existingPayload;
        if (kDebugMode) {
          debugPrint('⚡ Auto-scan fast mark — reusing entry/exit payload (no second DB merge)');
        }
      } else {
        freshPayload = await FirestoreRetryService.executeWithRetry(
          operation: () async =>
              _getTeacherPayload(db, instituteId, attendanceRollKey, today),
          operationName: 'Check existing attendance',
        );

        // ✅ MERGE FRESH attendance_in_out records to see latest entry/exit state
        if (kDebugMode) {
          debugPrint('⏳ Merging fresh attendance_in_out records (photo upload check)...');
        }
        freshPayload = await _mergeAttendanceInOutRecords(
          db,
          instituteId,
          attendanceRollKey,
          today,
          freshPayload,
        );
        if (kDebugMode) debugPrint('✅ Merged freshPayload - checking entry/exit state...');
      }

      // Freeze the attendance timestamp at the actual photo handling moment so
      // later verification/upload work does not shift the saved time.
      final photoCapturedAt = DateTime.now().toUtc();
      final currentTime = photoCapturedAt.toLocal();
      final serverTs = photoCapturedAt.toIso8601String();
      var mode = decision.mode;
      int? currentLectureIndex = decision.lectureIndex;

      if (freshPayload != null) {
        // ✅ FIXED: Check actual fields in merged payload (no type field)
        // ✅ CHECK ALL POSSIBLE ENTRY/EXIT FIELD NAMES (snake_case and camelCase)
        final hasEntry = freshPayload['photo_url'] != null ||
                         freshPayload['entry_photo_url'] != null ||
                         freshPayload['entryTime'] != null ||
                         freshPayload['entry_time'] != null;

        final hasExit = freshPayload['exitTime'] != null ||
                        freshPayload['exit_time'] != null;

        if (kDebugMode) {
          debugPrint('🔄 FRESH PAYLOAD CHECK (after photo upload):');
          debugPrint('   📊 freshPayload hasEntry: $hasEntry');
          debugPrint('     ├─ photo_url: ${freshPayload['photo_url']}');
          debugPrint('     ├─ entry_photo_url: ${freshPayload['entry_photo_url']}');
          debugPrint('     ├─ entryTime: ${freshPayload['entryTime']}');
          debugPrint('     └─ entry_time: ${freshPayload['entry_time']}');
          debugPrint('   📊 freshPayload hasExit: $hasExit');
          debugPrint('     ├─ exitTime: ${freshPayload['exitTime']}');
          debugPrint('     └─ exit_time: ${freshPayload['exit_time']}');
          debugPrint('   📊 All payload keys: ${freshPayload.keys.toList()}');
        }

        if (hasEntry && hasExit) {
          if (context.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text('Attendance already complete today for $attendanceRollKey.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        final d2 = _decideNextMark(freshPayload, timing);
        if (kDebugMode) {
          debugPrint('🔄 MODE RECALCULATION: $decision.mode → ${d2.mode}');
        }
        mode = d2.mode;
        currentLectureIndex = d2.lectureIndex;
        if (mode == 'complete') {
          if (context.mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Already marked complete.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      if (forcedStep != null && forcedStep != mode) {
        if (!context.mounted) return;
        // ✅ REMOVED: No longer blocking exit if entry hasn't been marked
        // Exit can now be marked independently with just registered face
        if (forcedStep == 'entry' && mode == 'exit') {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Entry already recorded — tap Exit (yellow).'),
              backgroundColor: Colors.orange,
            ),
          );
        } else if (mode == 'lecture_scan') {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'A lecture scan is required next — complete that step in the main attendance flow.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Attendance was updated — check status and try again.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Keep Exit path available; credit/penalty is calculated during save.

      final isMarkingEntry = mode == 'entry';
      final isMarkingExit = mode == 'exit';
      final isLectureScan = !useSubjects && mode == 'lecture_scan';

      if (kDebugMode) {
        debugPrint('═══════════════════════════════════════════════════════');
        debugPrint('🎯 ATTENDANCE MODE: $mode');
        debugPrint('   📝 Entry: $isMarkingEntry | Exit: $isMarkingExit | Lecture: $isLectureScan');
        debugPrint('   👤 Student: $retrievedStudentName (ID: $retrievedStudentId)');
        debugPrint('═══════════════════════════════════════════════════════');
      }

      final sy = studentData['year']?.toString().trim();
      final folderYear =
          (sy != null && sy.isNotEmpty) ? sy : DateTime.now().year.toString();
      final lectureTimes = _parseLectureTiming(timing);

      if (isLectureScan &&
          (currentLectureIndex == null ||
              currentLectureIndex < 0 ||
              currentLectureIndex >= lectureTimes.length)) {
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Lecture scan not available (check institute hours in settings).',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      String photoType;
      if (isMarkingEntry) {
        photoType = 'entry';
      } else if (isMarkingExit) {
        photoType = 'exit';
      } else {
        photoType = 'lecture_scan';
      }

      // Entry/exit identity is already enforced above by [FaceRecognitionService.verifyStudent]
      // against `face_embedding` (with liveness). Re-running comparison by downloading the
      // registration JPEG and re-embedding often fails for benign reasons and surfaced as 0%.
      if (kDebugMode && (isMarkingEntry || isMarkingExit)) {
        debugPrint(
          '✅ Entry/exit: using verifyStudent only (no redundant registration-URL re-verify) for $attendanceRollKey',
        );
      }

      // Do not block entry on profile completeness fields.
      // Identity is enforced by face verification above.
      if (kDebugMode && isMarkingEntry) {
        final studentId = studentData['student_id'] ?? studentData['id'];
        final studentName = studentData['name'] ?? studentData['student_name'];
        debugPrint('ℹ️ Entry metadata check (non-blocking): studentId=$studentId, studentName=$studentName');
      }

      final uploadResult = await StorageService.uploadAttendancePhoto(
        instituteId: instituteId,
        folderYear: folderYear,
        srNo: attendanceRollKey,
        subject: 'all',
        date: today,
        photoBytes: bytes,
        photoType: photoType,
      );

      final url = uploadResult['url']!;
      final storagePath = uploadResult['path']!;
      final fileId = uploadResult['fileId'];

      final existingData = Map<String, dynamic>.from(freshPayload);

      final attendanceData = <String, dynamic>{
        'srNo': attendanceRollKey,
        'date': today,
        'markedBy': db.auth.currentUser?.id ?? 'unknown',
        'lectureTiming': timing,
        'instituteId': instituteId,
        'updatedAt': serverTs,
        'subjects': enrolledSubjects,
      };

      if (isMarkingEntry) {
        attendanceData['entryPhoto'] = url;
        attendanceData['entryTime'] = serverTs;
        attendanceData['entryPhotoPath'] = storagePath;
        if (fileId != null && fileId.isNotEmpty) {
          attendanceData['entryPhotoFileId'] = fileId;
        }
        attendanceData['photoUrl'] = url;
        attendanceData['timestamp'] = serverTs;
        attendanceData['status'] = 'pending';
        final lectures = <String, dynamic>{};
        if (lectureTimes.isNotEmpty) {
          for (int i = 0; i < lectureTimes.length; i++) {
            final lecture = lectureTimes[i];
            final start = lecture['start'] as TimeOfDay;
            final end = lecture['end'] as TimeOfDay;
            final lectureKey = 'lecture_${i + 1}';
            lectures[lectureKey] = {
              'startTime': '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
              'endTime': '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
              'marked': false,
              'status': 'pending',
            };
          }
        }
        attendanceData['lectures'] = lectures;
      } else if (isLectureScan && currentLectureIndex != null) {
        final lectureIndex = currentLectureIndex;
        final lectureKey = 'lecture_${lectureIndex + 1}';
        final lecture = lectureTimes[lectureIndex];
        final start = lecture['start'] as TimeOfDay;
        final end = lecture['end'] as TimeOfDay;
        attendanceData['entryPhoto'] = existingData['entryPhoto'] ?? existingData['photoUrl'];
        attendanceData['entryTime'] = existingData['entryTime'] ?? existingData['timestamp'];
        attendanceData['entryPhotoPath'] = existingData['entryPhotoPath'] ?? existingData['storagePath'];
        attendanceData['entryPhotoFileId'] = existingData['entryPhotoFileId'];
        attendanceData['photoUrl'] = existingData['photoUrl'] ?? existingData['entryPhoto'];
        attendanceData['timestamp'] = existingData['timestamp'] ?? existingData['entryTime'];
        final lectures = Map<String, dynamic>.from(existingData['lectures'] as Map? ?? {});
        lectures[lectureKey] = {
          'faceScanPhoto': url,
          'faceScanTime': serverTs,
          'faceScanPath': storagePath,
          if (fileId != null && fileId.isNotEmpty) 'faceScanFileId': fileId,
          'startTime': '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
          'endTime': '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
          'marked': true,
        };
        attendanceData['lectures'] = lectures;
      } else if (isMarkingExit) {
        attendanceData['entryPhoto'] = existingData['entryPhoto'] ?? existingData['photoUrl'];
        attendanceData['entryTime'] = existingData['entryTime'] ?? existingData['timestamp'];
        attendanceData['entryPhotoPath'] = existingData['entryPhotoPath'] ?? existingData['storagePath'];
        attendanceData['entryPhotoFileId'] = existingData['entryPhotoFileId'];
        attendanceData['photoUrl'] = existingData['photoUrl'] ?? existingData['entryPhoto'];
        attendanceData['timestamp'] = existingData['timestamp'] ?? existingData['entryTime'];
        attendanceData['exitPhoto'] = url;
        attendanceData['exitTime'] = serverTs;
        attendanceData['exitPhotoPath'] = storagePath;
        if (fileId != null && fileId.isNotEmpty) {
          attendanceData['exitPhotoFileId'] = fileId;
        }
        final lectures = Map<String, dynamic>.from(existingData['lectures'] as Map? ?? {});
        final entryTime = _asDateTime(existingData['entryTime']) ?? _asDateTime(existingData['timestamp']);
        if (entryTime != null && lectureTimes.isNotEmpty) {
          final exitDateTime = currentTime;
          for (int i = 0; i < lectureTimes.length; i++) {
            final lec = lectureTimes[i];
            final start = lec['start'] as TimeOfDay;
            final end = lec['end'] as TimeOfDay;
            final lectureStart = DateTime(
              exitDateTime.year,
              exitDateTime.month,
              exitDateTime.day,
              start.hour,
              start.minute,
            );
            final lectureEnd = DateTime(
              exitDateTime.year,
              exitDateTime.month,
              exitDateTime.day,
              end.hour,
              end.minute,
            );
            if (lectureStart.isAfter(entryTime.subtract(const Duration(minutes: 30))) &&
                lectureEnd.isBefore(exitDateTime.add(const Duration(minutes: 30)))) {
              final lk = 'lecture_${i + 1}';
              if (!lectures.containsKey(lk)) {
                lectures[lk] = {
                  'startTime': '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
                  'endTime': '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                  'marked': true,
                  'markedAtExit': true,
                };
              } else {
                final existingLecture = Map<String, dynamic>.from(lectures[lk] as Map);
                existingLecture['marked'] = true;
                lectures[lk] = existingLecture;
              }
            }
          }
        }
        attendanceData['lectures'] = lectures;
        attendanceData['status'] = 'present';
        if (entryTime != null) {
          final duration = currentTime.difference(entryTime);
          final rawH = duration.inSeconds / 3600.0;
          attendanceData['hoursRaw'] = double.parse(rawH.toStringAsFixed(6));

          // NEW LOGIC: Window = 2 × subject_count hours
          final windowHours = attendanceWindowHoursForSubjectCount(enrolledSubjects.length);

          // Determine credited hours based on window
          final creditedTotal = rawH <= windowHours
              ? rawH  // Within window: credit actual hours
              : attendanceFixedCreditHoursForSubjectCount(enrolledSubjects.length);  // After window: fixed hours

          // Flag late exit if marked after window
          final isLateExit = rawH > windowHours;
          attendanceData['isLateExit'] = isLateExit;
          if (isLateExit) {
            attendanceData['lateExitTimestamp'] = serverTs;  // Actual exit timestamp
          }

          // Distribute equally among subjects
          final creditedPerSubject = enrolledSubjects.isEmpty
              ? creditedTotal
              : creditedTotal / enrolledSubjects.length;

          attendanceData['hours'] = double.parse(creditedPerSubject.toStringAsFixed(6));
          attendanceData['totalCreditsDay'] = double.parse(creditedTotal.toStringAsFixed(6));

          // Generate appropriate remark
          if (rawH <= windowHours) {
            attendanceData['attendanceReason'] = attendanceCompletedWithinWindowNote(
              creditedHours: double.parse(creditedPerSubject.toStringAsFixed(6)),
              windowHours: windowHours,
            );
          } else {
            attendanceData['attendanceReason'] = autoClosedMissingExitNote(
              double.parse(creditedTotal.toStringAsFixed(1)),
            );
          }
        } else {
          // ✅ FALLBACK: Entry time missing/corrupted but allow exit marking
          // Use full window hours as fallback
          final windowHours = attendanceWindowHoursForSubjectCount(enrolledSubjects.length);
          final creditedPerSubject = enrolledSubjects.isEmpty
              ? windowHours
              : windowHours / enrolledSubjects.length;

          attendanceData['hours'] = double.parse(creditedPerSubject.toStringAsFixed(6));
          attendanceData['totalCreditsDay'] = double.parse(windowHours.toStringAsFixed(6));
          attendanceData['hoursRaw'] = windowHours;
          attendanceData['attendanceReason'] = '⚠️ Entry time missing - exit marked with default window hours (${windowHours.toStringAsFixed(1)}h)';

          if (kDebugMode) {
            debugPrint('⚠️ EXIT marked but entry time missing - using window hours: $windowHours');
          }
        }
      }

      final mergedPayload = Map<String, dynamic>.from(existingData)..addAll(attendanceData);

      await FirestoreRetryService.executeWithRetry(
        operation: () async => _upsertTeacherDoc(db, instituteId, attendanceRollKey, today, mergedPayload),
        operationName: 'Save attendance record',
      );

      final subjectLabel = enrolledSubjects.isEmpty
          ? null
          : enrolledSubjects.map((e) => e.toString()).join(', ');

      if (isMarkingEntry) {
        await _syncAttendanceInOut(
          instituteId: instituteId,
          srNo: attendanceRollKey,
          date: today,
          type: 'entry',
          photoUrl: url,
          photoPath: storagePath,
          photoFileId: fileId,
          recordedAtUtc: serverTs,
          subject: subjectLabel,
          sessionEntryUtc: serverTs,
          status: 'pending',
        );
        await InstituteNotificationService.scheduleAttendanceExitReminder(
          instituteId: instituteId,
          srNo: attendanceRollKey,
          dateKey: today,
          subjectTag: 'all',
          entryAtUtc: DateTime.parse(serverTs.toString()).toUtc(),
          enrolledSubjects: enrolledSubjects,
        );
      } else if (isMarkingExit) {
        final entryUtc =
            mergedPayload['entryTime']?.toString() ?? mergedPayload['timestamp']?.toString();
        final hrs = (mergedPayload['hours'] as num?)?.toDouble();

        // ✅ NEW: Calculate credited hours using policy rules
        final entryTime = _asDateTime(mergedPayload['entryTime']) ?? _asDateTime(mergedPayload['timestamp']);
        final exitTime = _asDateTime(serverTs);
        final calculation = AttendanceHoursCalculatorService.calculateCreditedHours(
          entryTime: entryTime,
          exitTime: exitTime,
          subjectCount: enrolledSubjects.length,
        );

        await _syncAttendanceInOut(
          instituteId: instituteId,
          srNo: attendanceRollKey,
          date: today,
          type: 'exit',
          photoUrl: url,
          photoPath: storagePath,
          photoFileId: fileId,
          recordedAtUtc: serverTs,
          subject: subjectLabel,
          sessionEntryUtc: entryUtc,
          sessionExitUtc: serverTs,
          hours: hrs,
          status: 'present',
        );

        // ✅ NEW: Save calculated hours to database after exit is marked
        try {
          // Get the attendance record ID that was just created
          final recordRow = await appDb
              .from('attendance_in_out')
              .select('id')
              .eq('student_id', retrievedStudentId)
              .eq('attendance_date', today)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();

          if (recordRow != null) {
            final recordId = recordRow['id'] as String;
            await AttendanceHoursPersistenceService.saveHoursToRecord(
              recordId: recordId,
              creditedHours: calculation['creditedHours'] as double,
              calculationNote: calculation['calculationNote'] as String,
            );

            if (kDebugMode) {
              debugPrint('💾 Saved credited hours: ${calculation['creditedHours']}h - ${calculation['calculationNote']}');
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Failed to save hours: $e');
          // Don't fail the entire process if hours saving fails
        }

        await InstituteNotificationService.cancelAttendanceExitReminder(
          instituteId: instituteId,
          srNo: attendanceRollKey,
          dateKey: today,
          subjectTag: 'all',
        );
      }

      String successMessage;
      if (isMarkingEntry) {
        final subjectCount = enrolledSubjects.length;
        final windowHours = attendanceWindowHoursForSubjectCount(subjectCount);
        successMessage = '✅ Entry recorded for $attendanceRollKey\n'
            'Student has $subjectCount subject${subjectCount != 1 ? 's' : ''}, '
            'granted ${windowHours.toStringAsFixed(1)} hour${windowHours != 1 ? 's' : ''} to complete exit.';
      } else if (isMarkingExit) {
        final creditedPerSubject = attendanceData['hours'] as double? ?? 0.0;
        final creditedTotal = attendanceData['totalCreditsDay'] as double? ?? creditedPerSubject;
        final rawH = (attendanceData['hoursRaw'] as num?)?.toDouble() ?? creditedTotal;
        final isLateExit = attendanceData['isLateExit'] as bool? ?? false;

        // Format in H:M:S format
        final creditedTotalLabel = formatCreditedHoursHMS(creditedTotal);
        final seatedLabel = formatSeatedDurationHuman(
          Duration(seconds: (rawH * 3600).round()),
        );

        final lateExitFlag = isLateExit ? ' ⏰ LATE EXIT' : '';

        if (rawH > creditedTotal + 1e-6) {
          successMessage = '✅ Exit marked for $attendanceRollKey$lateExitFlag\n'
              '⏰ Seated: $seatedLabel | Credited: $creditedTotalLabel';
        } else {
          successMessage =
              '✅ Exit marked for $attendanceRollKey$lateExitFlag\n⏰ Credited: $creditedTotalLabel';
        }
      } else if (isLectureScan && currentLectureIndex != null) {
        successMessage = '✅ Lecture ${currentLectureIndex + 1} scan done for $attendanceRollKey';
      } else {
        successMessage = '✅ Saved for $attendanceRollKey';
      }

      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(successMessage)),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Inline mark attendance: $e');
      if (context.mounted) {
        scaffoldMessengerOr(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark attendance: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
