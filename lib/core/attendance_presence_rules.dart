import 'time_parse.dart';
import 'attendance_auto_close_policy.dart';

Map<String, dynamic> _additional(dynamic a) {
  if (a is Map<String, dynamic>) return Map<String, dynamic>.from(a);
  if (a is Map) return a.map((k, v) => MapEntry(k.toString(), v));
  return {};
}

/// True when this `attendance_in_out` row signals the student **entered** (any subject).
bool attendanceInOutRowHasEntry(Map<String, dynamic> row) {
  final type = (row['type']?.toString() ?? '').toLowerCase().trim();
  if (type == 'entry') return true;
  final add = _additional(row['additional']);
  return parseAnyTimestamp(add['entryTime']) != null;
}

/// Exit / hours / auto-close row that counts toward presence for the day.
bool attendanceInOutRowHasPresentCredit(Map<String, dynamic> row) {
  final type = (row['type']?.toString() ?? '').toLowerCase().trim();
  final add = _additional(row['additional']);
  final st = add['status']?.toString().toLowerCase();
  if (st == 'present') return true;
  if (add['autoClosedMissingExit'] == true) return true;
  final h = add['hours'];
  if (h is num && h > 0) return true;
  if (type == 'exit' &&
      (parseAnyTimestamp(add['exitTime']) != null || parseAnyTimestamp(add['entryTime']) != null)) {
    return st != 'absent';
  }
  return false;
}

/// Present if **any** attendance row that day shows entry or credited time (any subject).
bool studentDayPresentFromInOutRows(Iterable<Map<String, dynamic>> rowsForStudentOnDate) {
  for (final row in rowsForStudentOnDate) {
    if (attendanceInOutRowHasEntry(row)) return true;
    if (attendanceInOutRowHasPresentCredit(row)) return true;
  }
  return false;
}

/// Any subject session or legacy top-level has an entry photo/time (teacher_attendance.payload).
bool teacherPayloadHasAnySubjectEntry(Map<String, dynamic> payload) {
  final sessions = mapSubjectSessions(payload);
  if (sessions.isNotEmpty) {
    for (final s in sessions.values) {
      if (sessionHasEntryMap(s)) return true;
    }
    return false;
  }
  return payload['entryPhoto'] != null ||
      payload['photoUrl'] != null ||
      payload['entryTime'] != null;
}

/// Entry recorded but exit still required (top-level or any `subjectSessions` bucket).
bool teacherPayloadHasPendingExit(Map<String, dynamic> payload) {
  final sessions = mapSubjectSessions(payload);
  if (sessions.isNotEmpty) {
    for (final s in sessions.values) {
      if (sessionHasEntryMap(s) && !sessionHasExitMap(s)) return true;
    }
    return false;
  }
  if (!teacherPayloadHasAnySubjectEntry(payload)) return false;
  return !sessionHasExitMap(payload);
}

/// Next step is entry (not exit) for today's card — respects subject order when provided.
bool teacherPayloadNeedsEntry(
  Map<String, dynamic>? payload, {
  List<String> enrolledSubjects = const [],
}) {
  if (payload == null || payload.isEmpty) return true;
  if (teacherPayloadHasPendingExit(payload)) return false;

  final sessions = mapSubjectSessions(payload);
  if (enrolledSubjects.isEmpty) {
    if (sessions.isNotEmpty) {
      for (final s in sessions.values) {
        if (!sessionHasEntryMap(s)) return true;
        if (!sessionHasExitMap(s)) return false;
      }
      return false;
    }
    return !teacherPayloadHasAnySubjectEntry(payload);
  }

  if (sessions.isEmpty) {
    return !teacherPayloadHasAnySubjectEntry(payload);
  }

  for (final sub in enrolledSubjects) {
    final sess = sessions[sub.trim()] ?? sessions[sub] ?? <String, dynamic>{};
    if (!sessionHasEntryMap(sess)) return true;
    if (!sessionHasExitMap(sess)) return false;
  }
  return false;
}

/// Active session for thumbnails (pending exit first, else last entry).
Map<String, dynamic>? teacherPayloadActiveSessionSlice(Map<String, dynamic>? payload) {
  if (payload == null || payload.isEmpty) return null;
  final sessions = mapSubjectSessions(payload);
  if (sessions.isEmpty) return payload;

  for (final s in sessions.values) {
    if (sessionHasEntryMap(s) && !sessionHasExitMap(s)) {
      return Map<String, dynamic>.from(s);
    }
  }
  Map<String, dynamic>? lastWithEntry;
  for (final s in sessions.values) {
    if (sessionHasEntryMap(s)) lastWithEntry = Map<String, dynamic>.from(s);
  }
  return lastWithEntry;
}

/// Official SR number for `attendance_in_out.sr_no`, `teacher_attendance` doc id, and roll fields.
/// Never returns `user_id` — only the `sr_no` column on the student row.
String? attendanceSrNoFromStudentRow(Map<String, dynamic> row) {
  final sr = (row['sr_no'] ?? row['srNo'])?.toString().trim() ?? '';
  return sr.isEmpty ? null : sr;
}
