import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceService {
  static final supabase = Supabase.instance.client;

  /// Fetch entry/exit records for a student
  static Future<Map<String, dynamic>> getStudentAttendance(
    String srNo,
    String instituteId,
  ) async {
    try {
      print('🔍 [ATTENDANCE] Fetching entry/exit for $srNo...');

      final response = await supabase
          .from('attendance')
          .select()
          .eq('sr_no', srNo)
          .eq('institute_id', instituteId)
          .eq('status', 'present')
          .order('attendance_date', ascending: false)
          .limit(1) // Get today's record
          .execute();

      print('✅ [ATTENDANCE] Fetched: ${response.toString()}');

      if (response.data.isEmpty) {
        return {'entry': null, 'exit': null};
      }

      // Parse entry/exit from the records
      final records = response.data as List;
      Map<String, dynamic> attendance = {'entry': null, 'exit': null};

      for (var record in records) {
        if (record['record_type'] == 'entry') {
          attendance['entry'] = {
            'time': record['marked_time'],
            'photo_url': record['photo_url'],
            'similarity': record['similarity_score'],
          };
        } else if (record['record_type'] == 'exit') {
          attendance['exit'] = {
            'time': record['marked_time'],
            'photo_url': record['photo_url'],
            'similarity': record['similarity_score'],
          };
        }
      }

      print('📊 [ATTENDANCE] Entry: ${attendance['entry']}, Exit: ${attendance['exit']}');
      return attendance;
    } catch (e) {
      print('❌ [ATTENDANCE] Error: $e');
      return {'entry': null, 'exit': null};
    }
  }

  /// Get today's attendance summary for institute
  static Future<List<Map<String, dynamic>>> getTodayAttendance(
    String instituteId,
  ) async {
    try {
      final today = DateTime.now().toString().split(' ')[0];

      final response = await supabase
          .from('attendance')
          .select()
          .eq('institute_id', instituteId)
          .eq('attendance_date', today)
          .order('marked_time', ascending: false)
          .execute();

      return List<Map<String, dynamic>>.from(response.data ?? []);
    } catch (e) {
      print('❌ [ATTENDANCE] Error fetching today: $e');
      return [];
    }
  }
}
