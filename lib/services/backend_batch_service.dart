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

  /// Queue attendance record - RETURNS IMMEDIATELY (saves in background!)
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
      print('📋 [CLIENT] Queueing attendance (ASYNC - return immediately)...');
      print('   SR No: $srNo | Type: $recordType');

      // 🔧 Calculate IST date for attendance_date (NOT from UTC markedTime)
      final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final attendanceDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final tempId = '${DateTime.now().millisecondsSinceEpoch}';

      // ⚡ RETURN IMMEDIATELY TO USER - Save in background!
      print('⚡ [CLIENT] Returning immediately with temp ID: $tempId');

      // ⏳ BACKGROUND: Call Supabase Edge Function (fire-and-forget!)
      _saveAttendanceInBackground(
        srNo: srNo,
        studentName: studentName,
        instituteId: instituteId,
        attendanceDate: attendanceDate,
        recordType: recordType,
        markedTime: markedTime,
        remark: remark,
        photoUrl: photoUrl,
        similarityScore: similarityScore,
      );

      // ⚡ INSTANT RESPONSE TO USER
      return {
        'success': true,
        'attendance_id': tempId,
        'marked_time': markedTime,
        'face_confidence': similarityScore * 100,
        'message': 'Attendance marked successfully',
      };
    } catch (e) {
      print('❌ [CLIENT] Error: $e');
      return {
        'success': false,
        'reason': '$e',
        'error_id': 'ERROR',
        'message': 'Failed to queue attendance',
      };
    }
  }

  /// Background save to backend (doesn't block user!)
  void _saveAttendanceInBackground({
    required String srNo,
    required String? studentName,
    required String instituteId,
    required String attendanceDate,
    required String recordType,
    required String markedTime,
    required String? remark,
    required String? photoUrl,
    required double similarityScore,
  }) {
    // Fire-and-forget: save in background without awaiting
    supabase.functions.invoke(
      'batch-attendance',
      body: {
        'sr_no': srNo,
        'student_name': studentName ?? '-',
        'institute_id': instituteId,
        'attendance_date': attendanceDate,
        'record_type': recordType,
        'marked_time': markedTime,
        'remark': remark ?? '-',
        'photo_url': photoUrl,
        'status': 'present',
        'is_verified': false,
        'similarity_score': similarityScore,
        'embedding': '[]',
      },
    ).then((response) {
      final result = response.data as Map<String, dynamic>;
      if (result['success'] == true) {
        print('✅ [BACKGROUND] Attendance saved: ${result['attendance_id']}');
      } else {
        print('❌ [BACKGROUND] Save failed: ${result['reason']}');
      }
    }).catchError((e) {
      print('❌ [BACKGROUND] Network error: $e');
    });
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
