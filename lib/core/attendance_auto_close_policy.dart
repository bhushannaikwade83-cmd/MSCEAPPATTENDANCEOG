import 'time_parse.dart';
import 'app_db.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Subject buckets in teacher_attendance.payload (`subjectSessions`).
const String kSubjectSessionsPayloadKey = 'subjectSessions';

/// Exit window mapping:
/// 1 subject = 2.5h
/// 2 subjects = 4.5h
/// 3 subjects = 6.5h
/// 4 subjects = 8.5h
/// 5+ subjects continue adding 2.0h per extra subject.
double attendanceWindowHoursForSubjectCount(int subjectCount) {
  if (subjectCount <= 1) return 2.5;
  if (subjectCount == 2) return 4.5;
  if (subjectCount == 3) return 6.5;
  if (subjectCount == 4) return 8.5;
  return 8.5 + ((subjectCount - 4) * 2.0);
}

/// Hours credited if exit is marked AFTER window expires (but before midnight)
/// 1 subject = 1.0h, 2 = 2.5h, 3 = 3.5h, 4 = 4.5h (subjectCount + 0.5)
double attendanceFixedCreditHoursForSubjectCount(int subjectCount) {
  if (subjectCount == 1) return 1.0;
  return (subjectCount + 0.5).toDouble();
}

/// Hours credited if NO exit marked by 12 AM (midnight) = 1 hour fixed
/// (regardless of subject count)
double attendanceAllocatedHoursForSubjectCount(int subjectCount) {
  return 1.0; // Fixed 1 hour only, no matter how many subjects
}

/// Legacy constant (kept for compatibility).
const double kAttendanceExitDeadlineHours = 24;

/// Legacy helper constant used by some notification codepaths.
///
/// The actual deadline rule is "until the calendar day changes locally"
/// (see [isPastAttendanceExitDeadline]). This duration is kept only to
/// satisfy older callers that add a fixed duration to an entry timestamp.
const Duration kAttendanceExitDeadlineDuration = Duration(hours: 24);

/// Strict rule: Exit must be taken within a fixed window from Entry
/// BUT we now allow the exit button to stay open until the day changes (midnight).
/// The window is used for credit calculation, not for blocking the UI.
bool isPastAttendanceExitDeadline(DateTime entryUtc, DateTime nowUtc, int subjectCount) {
  // Convert both to local time to check the calendar day
  final entryLocal = entryUtc.toLocal();
  final nowLocal = nowUtc.toLocal();

  // It's only past the deadline if the calendar day has changed
  return nowLocal.year > entryLocal.year ||
      nowLocal.month > entryLocal.month ||
      nowLocal.day > entryLocal.day;
}

/// Remark when exit is missed after window deadline
String autoClosedMissingExitNote(double creditedHours) =>
    'Exit after window — credited ${creditedHours.toStringAsFixed(1)}h.';

/// Remark when no exit is marked by midnight
String noExitByMidnightNote() =>
    'No exit marked — credited 1.0h.';

/// Remark when exit is taken within the allowed window
String attendanceCompletedWithinWindowNote({
  required double creditedHours,
  required double windowHours,
}) =>
    'Exit within ${windowHours.toStringAsFixed(0)}h window — '
    'credited actual ${creditedHours.toStringAsFixed(2)}h.';

/// Prefer subjects whose name mentions 30, then 40, then 50 (word boundary).
int subjectAutoClosePriority(String subjectName) {
  if (RegExp(r'\b30\b').hasMatch(subjectName)) return 0;
  if (RegExp(r'\b40\b').hasMatch(subjectName)) return 1;
  if (RegExp(r'\b50\b').hasMatch(subjectName)) return 2;
  return 3;
}

bool sessionHasEntryMap(Map<String, dynamic> s) {
  return s['entryPhoto'] != null || s['photoUrl'] != null || s['entryTime'] != null;
}

bool sessionHasExitMap(Map<String, dynamic> s) {
  return s['exitPhoto'] != null || s['exitTime'] != null;
}

Map<String, Map<String, dynamic>> mapSubjectSessions(Map<String, dynamic>? payload) {
  if (payload == null) return {};
  final raw = payload[kSubjectSessionsPayloadKey];
  if (raw is! Map) return {};
  final out = <String, Map<String, dynamic>>{};
  raw.forEach((k, v) {
    if (v is Map) {
      out[k.toString()] = Map<String, dynamic>.from(v.cast<String, dynamic>());
    }
  });
  return out;
}

double sumSubjectCreditedHours(Map<String, Map<String, dynamic>> sessions) {
  double t = 0;
  for (final s in sessions.values) {
    final h = s['hours'];
    if (h is num) t += h.toDouble();
  }
  return double.parse(t.toStringAsFixed(6));
}

bool _legacyHasTopLevelAttendance(Map<String, dynamic> p) {
  return p['entryPhoto'] != null ||
      p['entryTime'] != null ||
      p['photoUrl'] != null ||
      p['exitPhoto'] != null ||
      p['exitTime'] != null;
}

bool _isLegacyAttendanceDoc(Map<String, dynamic> data) {
  final ss = data[kSubjectSessionsPayloadKey];
  if (ss is Map && ss.isNotEmpty) return false;
  return _legacyHasTopLevelAttendance(data);
}

/// Pick enrolled subject for legacy single-row auto-close (30 → 40 → 50 → first).
String? pickEnrollmentSubjectForAutoClose(List<String> enrolledSubjects) {
  if (enrolledSubjects.isEmpty) return null;
  for (final token in ['30', '40', '50']) {
    for (final s in enrolledSubjects) {
      if (RegExp(r'\b' + token + r'\b').hasMatch(s)) return s;
    }
  }
  return enrolledSubjects.first;
}

class AutoCloseSyncHint {
  final String subjectLabel;
  final String sessionEntryUtc;
  final String syntheticExitUtc;

  const AutoCloseSyncHint({
    required this.subjectLabel,
    required this.sessionEntryUtc,
    required this.syntheticExitUtc,
  });
}

class AttendanceAutoCloseApplyResult {
  final Map<String, dynamic> payload;
  final bool changed;
  final List<AutoCloseSyncHint> syncHints;

  const AttendanceAutoCloseApplyResult({
    required this.payload,
    required this.changed,
    required this.syncHints,
  });
}

/// Applies the missing-exit deadline rule to [payload] (mutates a deep copy).
AttendanceAutoCloseApplyResult applyMissingExitAutoClose({
  required Map<String, dynamic> payload,
  required List<String> enrolledSubjects,
  required DateTime nowUtc,
}) {
  final out = Map<String, dynamic>.from(payload);
  final sessions = mapSubjectSessions(out);

  if (sessions.isNotEmpty) {
    return _applySubjectSessions(out, sessions, enrolledSubjects, nowUtc);
  }

  if (_isLegacyAttendanceDoc(out)) {
    return _applyLegacyTopLevel(out, enrolledSubjects, nowUtc);
  }

  return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
}

AttendanceAutoCloseApplyResult _applySubjectSessions(
  Map<String, dynamic> out,
  Map<String, Map<String, dynamic>> sessions,
  List<String> enrolledSubjects,
  DateTime nowUtc,
) {
  final mutable = <String, Map<String, dynamic>>{};
  for (final e in sessions.entries) {
    mutable[e.key] = Map<String, dynamic>.from(e.value);
  }

  final stale = <String>[];
  for (final sub in enrolledSubjects) {
    final sess = Map<String, dynamic>.from(mutable[sub] ?? {});
    if (sess['autoClosedMissingExit'] == true) continue;
    if (!sessionHasEntryMap(sess)) continue;
    if (sessionHasExitMap(sess)) continue;
    final entry = parseAnyTimestamp(sess['entryTime']) ?? parseAnyTimestamp(sess['timestamp']);
    if (entry == null) continue;
    if (!isPastAttendanceExitDeadline(entry, nowUtc, enrolledSubjects.length)) continue;
    stale.add(sub);
  }

  if (stale.isEmpty) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  stale.sort((a, b) {
    final c = subjectAutoClosePriority(a).compareTo(subjectAutoClosePriority(b));
    if (c != 0) return c;
    return enrolledSubjects.indexOf(a).compareTo(enrolledSubjects.indexOf(b));
  });

  final hints = <AutoCloseSyncHint>[];
  for (final sub in stale) {
    var sess = Map<String, dynamic>.from(mutable[sub] ?? {});
    final entry = parseAnyTimestamp(sess['entryTime']) ?? parseAnyTimestamp(sess['timestamp']);
    if (entry == null) continue;

    final elapsed = nowUtc.difference(entry);
    final rawH = elapsed.inSeconds / 3600.0;

    final entryIso = entry.toUtc().toIso8601String();
    sess.remove('exitTime');
    sess.remove('exitPhoto');
    sess.remove('exitPhotoPath');
    sess.remove('exitPhotoFileId');
    sess['hoursRaw'] = double.parse(rawH.toStringAsFixed(6));
    final creditedHours = attendanceAllocatedHoursForSubjectCount(enrolledSubjects.length);
    sess['hours'] = creditedHours;
    sess['status'] = 'present';
    sess['autoClosedMissingExit'] = true;
    sess['autoClosedNote'] = autoClosedMissingExitNote(creditedHours);
    mutable[sub] = sess;

    hints.add(
      AutoCloseSyncHint(
        subjectLabel: sub,
        sessionEntryUtc: entryIso,
        syntheticExitUtc: nowUtc.toIso8601String(),
      ),
    );
  }

  out[kSubjectSessionsPayloadKey] = mutable;
  out['totalCreditedHoursDay'] = sumSubjectCreditedHours(mutable);

  var allExit = true;
  for (final sub in enrolledSubjects) {
    if (!sessionHasExitMap(Map<String, dynamic>.from(mutable[sub] ?? {}))) {
      allExit = false;
      break;
    }
  }
  out['status'] = allExit ? 'present' : 'pending';

  return AttendanceAutoCloseApplyResult(payload: out, changed: true, syncHints: hints);
}

AttendanceAutoCloseApplyResult _applyLegacyTopLevel(
  Map<String, dynamic> out,
  List<String> enrolledSubjects,
  DateTime nowUtc,
) {
  if (out['autoClosedMissingExit'] == true) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  final hasEntry =
      out['entryPhoto'] != null || out['photoUrl'] != null || out['entryTime'] != null;
  final hasExit = out['exitPhoto'] != null || out['exitTime'] != null;
  if (!hasEntry || hasExit) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  final entry = parseAnyTimestamp(out['entryTime']) ?? parseAnyTimestamp(out['timestamp']);
  if (entry == null) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  if (!isPastAttendanceExitDeadline(entry, nowUtc, enrolledSubjects.length)) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  final chosen = pickEnrollmentSubjectForAutoClose(enrolledSubjects);
  if (chosen == null) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  final elapsed = nowUtc.difference(entry);
  final rawH = elapsed.inSeconds / 3600.0;
  final entryIso = entry.toUtc().toIso8601String();

  out.remove('exitTime');
  out.remove('exitPhoto');
  out.remove('exitPhotoPath');
  out.remove('exitPhotoFileId');
  out['hoursRaw'] = double.parse(rawH.toStringAsFixed(6));
  final creditedHours = attendanceAllocatedHoursForSubjectCount(enrolledSubjects.length);
  out['hours'] = creditedHours;
  out['status'] = 'present';
  out['autoClosedMissingExit'] = true;
  out['autoClosedNote'] = autoClosedMissingExitNote(creditedHours);

  return AttendanceAutoCloseApplyResult(
    payload: out,
    changed: true,
    syncHints: [
      AutoCloseSyncHint(
        subjectLabel: chosen,
        sessionEntryUtc: entryIso,
        syntheticExitUtc: nowUtc.toIso8601String(),
      ),
    ],
  );
}
