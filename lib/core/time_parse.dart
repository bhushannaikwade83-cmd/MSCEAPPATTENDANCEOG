/// True if [s] already carries an explicit UTC/offset marker (so Dart parses a
/// fixed instant correctly). Used when the `Z` was dropped in JSON/`jsonb` but
/// the numeric components are still UTC wall time.
bool _isoStringHasExplicitTimezone(String s) {
  final t = s.trim();
  if (t.isEmpty) return false;
  final up = t.toUpperCase();
  if (up.endsWith('Z')) return true;
  // +HH:MM or -HH:MM at end (Postgres / RFC3339)
  if (RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(t)) return true;
  // +HHMM / -HHMM (no colon), e.g. +0530
  if (RegExp(r'[+-]\d{4}$').hasMatch(t)) return true;
  return false;
}

bool _looksLikeDateOnly(String s) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s.trim());

/// Parse timestamps from Supabase (ISO string), JSON, or [DateTime].
///
/// Naive ISO datetimes (no `Z` / no `±` offset) with a time component are
/// interpreted as **UTC**, because this app stores
/// [DateTime.toUtc().toIso8601String()] and some paths strip the trailing `Z`.
/// Callers should display with [.toLocal()] / [DateFormat] after parsing.
DateTime? parseAnyTimestamp(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is! String) return null;
  final s = v.trim();
  if (s.isEmpty) return null;

  if (_isoStringHasExplicitTimezone(s)) {
    return DateTime.tryParse(s);
  }

  if (_looksLikeDateOnly(s)) {
    return DateTime.tryParse(s);
  }

  final norm = s.contains('T') ? s : s.replaceFirst(' ', 'T');
  final withZ =
      norm.endsWith('Z') || norm.endsWith('z') ? norm : '${norm}Z';
  final utc = DateTime.tryParse(withZ);
  if (utc != null && utc.isUtc) return utc;

  return DateTime.tryParse(s);
}

/// Credited seated hours for attendance (single session / day record).
///
/// Any entry→exit duration is allowed; **credited** time is capped at [maxHours]
/// (default 2.5h per session for this record). Raw duration may be stored separately as `hoursRaw`.
double attendanceCreditedHours(Duration seated, {double maxHours = 2.5}) {
  if (seated.isNegative || seated.inSeconds <= 0) return 0;
  final raw = seated.inSeconds / 3600.0;
  final capped = raw > maxHours ? maxHours : raw;
  return double.parse(capped.toStringAsFixed(6));
}

/// DEPRECATED: Use functions from attendance_auto_close_policy.dart instead.
/// These legacy definitions are kept only for backward compatibility in some edge cases.
/// New code should import and use attendanceWindowHoursForSubjectCount,
/// attendanceFixedCreditHoursForSubjectCount, and attendanceAllocatedHoursForSubjectCount
/// from attendance_auto_close_policy.dart directly.

/// Seated time for one merged calendar-day attendance row (`entryTime` / `exitTime` / `hours`).
Duration? seatedDurationFromMergedAttendanceDay(Map<String, dynamic> record) {
  final entry = record['entryTime'] as DateTime?;
  final exit = record['exitTime'] as DateTime?;
  if (entry != null && exit != null && exit.isAfter(entry)) {
    return exit.difference(entry);
  }
  final hours = record['hours'];
  if (hours is num && hours > 0) {
    return Duration(seconds: (hours.toDouble() * 3600).round());
  }
  return null;
}

/// Human-readable seated duration (hours, minutes, seconds as appropriate).
String formatSeatedDurationHuman(Duration d) {
  if (d.isNegative) return '—';
  final totalSec = d.inSeconds;
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// Format credited hours (as double) to "Xh Ym Zs" format
/// Example: 1.5 → "1h 30m 0s", 0.75 → "45m 0s"
String formatCreditedHoursHMS(double hours) {
  if (hours < 0) return '—';
  if (hours == 0) return '0h 0m 0s';

  final totalSeconds = (hours * 3600).round();
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;

  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
