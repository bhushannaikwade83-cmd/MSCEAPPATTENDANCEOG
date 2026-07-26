import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_db.dart';
import 'hierarchical_attendance_service.dart';

class OfflineService {
  static const String _pendingAttendanceKey = 'pending_attendance';
  static const String _pendingPhotosKey = 'pending_photos';

  static Future<void> savePendingAttendance(Map<String, dynamic> attendanceData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingList = prefs.getStringList(_pendingAttendanceKey) ?? [];
      pendingList.add(jsonEncode(attendanceData));
      await prefs.setStringList(_pendingAttendanceKey, pendingList);
      if (kDebugMode) debugPrint('💾 Saved attendance to offline storage');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error saving offline attendance: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getPendingAttendance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingList = prefs.getStringList(_pendingAttendanceKey) ?? [];
      return pendingList.map((json) => jsonDecode(json) as Map<String, dynamic>).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error loading offline attendance: $e');
      return [];
    }
  }

  /// Sync pending rows to `attendance_in_out` via [HierarchicalAttendanceService].
  static Future<void> syncPendingAttendance(String instituteId) async {
    try {
      final pendingList = await getPendingAttendance();
      if (pendingList.isEmpty) return;

      if (kDebugMode) debugPrint('🔄 Syncing ${pendingList.length} pending attendance records...');

      final hierarchical = HierarchicalAttendanceService();
      int successCount = 0;
      int failCount = 0;

      var instituteCode = instituteId;
      final inst = await appDb.from('institutes').select('institute_code').eq('id', instituteId).maybeSingle();
      final ic = inst?['institute_code'] as String?;
      if (ic != null && ic.isNotEmpty) {
        instituteCode = ic;
      }

      for (var attendanceData in pendingList) {
        try {
          attendanceData['instituteId'] = instituteId;

          final date = attendanceData['date']?.toString() ??
              attendanceData['attendance_date']?.toString() ??
              '';
          final type = (attendanceData['type'] ?? 'entry').toString();
          final studentId = attendanceData['studentId']?.toString() ?? attendanceData['student_id']?.toString() ?? '';
          final studentName = attendanceData['studentName']?.toString() ?? attendanceData['student_name']?.toString() ?? '';
          final srNo = attendanceData['srNo']?.toString() ?? attendanceData['sr_no']?.toString() ?? '';
          final photoUrl = attendanceData['photoUrl']?.toString() ?? attendanceData['photo_url']?.toString() ?? '';
          final photoPath = attendanceData['photoPath']?.toString() ?? attendanceData['photo_path']?.toString();

          if (date.isEmpty || studentId.isEmpty) {
            failCount++;
            continue;
          }

          await hierarchical.saveAttendance(
            instituteCode: instituteCode,
            studentId: studentId,
            studentName: studentName,
            srNo: srNo,
            date: date.length >= 10 ? date.substring(0, 10) : date,
            type: type,
            photoUrl: photoUrl,
            photoPath: photoPath,
            additionalData: Map<String, dynamic>.from(attendanceData),
          );

          attendanceData.remove('docId');
          successCount++;
        } catch (e) {
          if (kDebugMode) debugPrint('❌ Error syncing attendance: $e');
          failCount++;
        }
      }

      if (successCount > 0) {
        await _removeSyncedAttendance(successCount);
        if (kDebugMode) debugPrint('✅ Synced $successCount attendance records');
      }

      if (failCount > 0 && kDebugMode) {
        debugPrint('⚠️ Failed to sync $failCount records');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error syncing pending attendance: $e');
    }
  }

  static Future<void> _removeSyncedAttendance(int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingList = prefs.getStringList(_pendingAttendanceKey) ?? [];
      if (pendingList.length > count) {
        pendingList.removeRange(0, count);
        await prefs.setStringList(_pendingAttendanceKey, pendingList);
      } else {
        await prefs.remove(_pendingAttendanceKey);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error removing synced attendance: $e');
    }
  }

  static Future<void> clearPendingAttendance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingAttendanceKey);
      if (kDebugMode) debugPrint('🗑️ Cleared all pending attendance');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error clearing pending attendance: $e');
    }
  }

  static Future<bool> hasPendingAttendance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingList = prefs.getStringList(_pendingAttendanceKey) ?? [];
      return pendingList.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  static Future<int> getPendingCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingList = prefs.getStringList(_pendingAttendanceKey) ?? [];
      return pendingList.length;
    } catch (e) {
      return 0;
    }
  }
}
