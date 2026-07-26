import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import '../core/attendance_auto_close_policy.dart';
import '../core/time_parse.dart';

/// Service to calculate and persist credited hours to database
/// This ensures hours are calculated once and reused, not recalculated for every report
class AttendanceHoursCalculatorService {
  /// Calculate credited hours based on entry/exit times and subject count
  /// Returns: {creditedHours, calculationNote}
  static Map<String, dynamic> calculateCreditedHours({
    required DateTime? entryTime,
    required DateTime? exitTime,
    required int subjectCount,
  }) {
    // Determine if exit was marked
    final hasExit = exitTime != null;

    // Calculate seated duration
    Duration? seatedDuration;
    if (entryTime != null && exitTime != null && exitTime.isAfter(entryTime)) {
      seatedDuration = exitTime.difference(entryTime);
    }

    // Apply policy rules
    if (seatedDuration == null || seatedDuration <= Duration.zero) {
      // No valid duration
      if (!hasExit) {
        // No exit marked by deadline
        final hours = attendanceAllocatedHoursForSubjectCount(subjectCount);
        return {
          'creditedHours': hours,
          'calculationNote': 'No exit marked by midnight - credited ${hours.toStringAsFixed(1)}h (fixed)',
        };
      }
      return {
        'creditedHours': 0.0,
        'calculationNote': 'Invalid duration - no hours credited',
      };
    }

    final windowHours = attendanceWindowHoursForSubjectCount(subjectCount);
    final seatedHours = seatedDuration.inSeconds / 3600.0;
    final seatedMinutes = seatedDuration.inMinutes;

    // If within window: use actual seated time (capped at 2.5h per session)
    if (seatedHours <= windowHours) {
      final creditedHours = attendanceCreditedHours(seatedDuration, maxHours: 2.5);
      return {
        'creditedHours': creditedHours,
        'calculationNote': 'Within ${windowHours.toStringAsFixed(0)}h window - actual ${seatedMinutes}m seated, credited ${creditedHours.toStringAsFixed(2)}h',
      };
    }

    // If exit marked AFTER window: use fixed credited hours
    if (hasExit && seatedHours > windowHours) {
      final creditedHours = attendanceFixedCreditHoursForSubjectCount(subjectCount);
      return {
        'creditedHours': creditedHours,
        'calculationNote': 'After ${windowHours.toStringAsFixed(0)}h window (${seatedMinutes}m seated) - credited fixed ${creditedHours.toStringAsFixed(1)}h',
      };
    }

    return {
      'creditedHours': 0.0,
      'calculationNote': 'No hours to credit',
    };
  }

  /// Calculate and return formatted note with hours
  static String getCalculationNote({
    required double creditedHours,
    required String baseNote,
  }) {
    return '$baseNote (${formatCreditedHoursHMS(creditedHours)})';
  }

  /// Parse entry and exit times from attendance record
  static Map<String, DateTime?> extractTimestamps(Map<String, dynamic> record) {
    final additional = _getAdditionalMap(record['additional']);

    DateTime? entryTime = parseAnyTimestamp(additional['entryTime']) ??
        parseAnyTimestamp(record['created_at']);

    DateTime? exitTime = parseAnyTimestamp(additional['exitTime']);

    return {
      'entryTime': entryTime,
      'exitTime': exitTime,
    };
  }

  /// Get subject count for a student (default 1 if not found)
  static int getSubjectCount(List<Map<String, dynamic>>? subjects) {
    if (subjects == null || subjects.isEmpty) return 1;
    return subjects.length.clamp(1, 4);
  }

  /// Helper: safely convert additional field to Map
  static Map<String, dynamic> _getAdditionalMap(dynamic additional) {
    if (additional is Map<String, dynamic>) {
      return Map<String, dynamic>.from(additional);
    }
    if (additional is Map) {
      return additional.cast<String, dynamic>();
    }
    return {};
  }

  /// Debug: Print calculation details
  static void debugPrintCalculation({
    required String studentId,
    required String date,
    required DateTime? entryTime,
    required DateTime? exitTime,
    required int subjectCount,
    required double creditedHours,
    required String note,
  }) {
    if (kDebugMode) {
      debugPrint(
        '💾 HOURS SAVED: $studentId on $date | subjects=$subjectCount | '
        'entry=${entryTime?.toString()} | exit=${exitTime?.toString()} | '
        'credited=${creditedHours.toStringAsFixed(2)}h | note=$note',
      );
    }
  }
}
