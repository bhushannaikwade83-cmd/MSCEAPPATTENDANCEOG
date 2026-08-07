import 'package:supabase_flutter/supabase_flutter.dart';

/// Backend Batching Service - Calls Supabase Edge Function
/// The backend handles all queuing and batching
class BackendBatchService {
  static final BackendBatchService _instance = BackendBatchService._internal();

  factory BackendBatchService() {
    return _instance;
  }

  BackendBatchService._internal();

  final supabase = Supabase.instance.client;

  /// Queue attendance record - WAITS FOR RESPONSE
  Future<Map<String, dynamic>> queueAttendance({
    required String srNo,
    required String instituteId,
    required String recordType,
    required String markedTime,
    String? remark,
    String? photoUrl,
    String? studentName,
    double similarityScore = 0.0,
  }) async {
    try {
      print('📋 [CLIENT] Sending attendance to backend...');
      print('   SR No: $srNo | Type: $recordType');

      // 🔧 Calculate IST date for attendance_date (NOT from UTC markedTime)
      final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final attendanceDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Call Supabase Edge Function
      final response = await supabase.functions.invoke(
        'batch-attendance',
        body: {
          'sr_no': srNo,
          'student_name': studentName ?? '-',
          'institute_id': instituteId,
          'attendance_date': attendanceDate, // IST date (YYYY-MM-DD)
          'record_type': recordType, // 'entry' or 'exit'
          'marked_time': markedTime, // ISO8601 UTC
          'remark': remark ?? '-',
          'photo_url': photoUrl,
          'status': 'present',
          'is_verified': false,
          'similarity_score': similarityScore,
          'embedding': '[]',
        },
      );

      // Parse response
      final result = response.data as Map<String, dynamic>;

      if (result['success'] == true) {
        print('✅ [CLIENT] Attendance marked successfully!');
        print('   Attendance ID: ${result['attendance_id']}');
        print('   Face Confidence: ${result['face_confidence']}%');
        print('   Time: ${result['marked_time']}');

        return {
          'success': true,
          'attendance_id': result['attendance_id'] ?? '',
          'marked_time': result['marked_time'] ?? markedTime,
          'face_confidence': (result['face_confidence'] ?? 0).toDouble(),
          'message': result['message'] ?? 'Marked successfully',
        };
      } else {
        print('❌ [CLIENT] Backend rejected: ${result['reason']}');

        return {
          'success': false,
          'reason': result['reason'] ?? 'Unknown error',
          'error_id': result['error_id'] ?? '',
          'message': 'Failed to mark attendance',
        };
      }
    } catch (e) {
      print('❌ [CLIENT] Network error: $e');

      return {
        'success': false,
        'reason': '$e',
        'error_id': 'NETWORK_ERROR',
        'message': 'Network error - will retry',
      };
    }
  }

  /// Get queue status from backend
  Future<Map<String, dynamic>> getQueueStatus() async {
    try {
      print('📊 [CLIENT] Fetching queue status...');

      final response = await supabase.functions.invoke('batch-attendance');

      final status = response.data as Map<String, dynamic>;
      print('✅ [CLIENT] Queue status: $status');

      return status;
    } catch (e) {
      print('❌ [CLIENT] Status fetch error: $e');
      return {};
    }
  }

  /// Queue multiple records at once
  Future<void> queueMultiple(List<Map<String, dynamic>> records) async {
    try {
      print('📋 [CLIENT] Queueing ${records.length} records via backend...');

      final response = await supabase.functions.invoke(
        'batch-attendance',
        body: records,
      );

      print('✅ [CLIENT] Batch queued successfully!');
      print('   Response: ${response.data}');
    } catch (e) {
      print('❌ [CLIENT] Batch queue error: $e');
      rethrow;
    }
  }
}

/// Singleton instance
final backendBatchService = BackendBatchService();
