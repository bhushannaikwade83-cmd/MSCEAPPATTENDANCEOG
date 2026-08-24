import 'package:http/http.dart' as http;
import 'dart:convert';

/// AttendanceMariaDBService - Replaces Supabase attendance calls
/// All attendance operations now go to MariaDB API
class AttendanceMariaDBService {
  static const String API_BASE_URL = 'https://digitrixmedia.com/msceattendanceapp/api/attendance';

  // ==========================================
  // INSERT ATTENDANCE (Entry/Exit)
  // ==========================================
  static Future<Map<String, dynamic>> insertAttendance({
    required String studentId,
    required String instituteId,
    required String srNo,
    required String studentName,
    required String attendanceDate,
    required String recordType, // 'entry' or 'exit'
    required String markedTime,
    String? photoUrl,
    List<double>? embedding,
    double? similarityScore,
    String? status,
    bool? isVerified,
    String? remark,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/insert'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'student_id': studentId,
          'institute_id': instituteId,
          'sr_no': srNo,
          'student_name': studentName,
          'attendance_date': attendanceDate,
          'record_type': recordType,
          'marked_time': markedTime,
          'photo_url': photoUrl ?? '',
          'embedding': embedding ?? [],
          'similarity_score': similarityScore ?? 0.0,
          'status': status ?? 'present',
          'is_verified': isVerified ?? false,
          'remark': remark ?? '',
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to insert attendance: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error inserting attendance: $e');
    }
  }

  // ==========================================
  // GET ATTENDANCE BY ID
  // ==========================================
  static Future<Map<String, dynamic>> getAttendance(String id) async {
    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/get'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Attendance not found');
      }
    } catch (e) {
      throw Exception('Error fetching attendance: $e');
    }
  }

  // ==========================================
  // GET ATTENDANCE BY DATE & INSTITUTE
  // ==========================================
  static Future<List<Map<String, dynamic>>> getAttendanceByDate({
    required String attendanceDate,
    required String instituteId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/get-by-date'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'attendance_date': attendanceDate,
          'institute_id': instituteId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      } else {
        throw Exception('Failed to fetch attendance by date');
      }
    } catch (e) {
      throw Exception('Error fetching attendance by date: $e');
    }
  }

  // ==========================================
  // GET ATTENDANCE BY STUDENT
  // ==========================================
  static Future<List<Map<String, dynamic>>> getAttendanceByStudent({
    required String studentId,
    int? limit,
    int? offset,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/get-by-student'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'student_id': studentId,
          'limit': limit ?? 100,
          'offset': offset ?? 0,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      } else {
        throw Exception('Failed to fetch student attendance');
      }
    } catch (e) {
      throw Exception('Error fetching student attendance: $e');
    }
  }

  // ==========================================
  // GET ATTENDANCE BY INSTITUTE (Daily Roster)
  // ==========================================
  static Future<List<Map<String, dynamic>>> getAttendanceByInstitute({
    required String instituteId,
    required String attendanceDate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/get-by-institute'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'institute_id': instituteId,
          'attendance_date': attendanceDate,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      } else {
        throw Exception('Failed to fetch institute attendance');
      }
    } catch (e) {
      throw Exception('Error fetching institute attendance: $e');
    }
  }

  // ==========================================
  // UPDATE ATTENDANCE
  // ==========================================
  static Future<Map<String, dynamic>> updateAttendance({
    required String id,
    String? status,
    bool? isVerified,
    String? photoUrl,
    double? similarityScore,
    String? remark,
    String? attendanceAllotedHr,
  }) async {
    try {
      final body = {'id': id};
      if (status != null) body['status'] = status;
      if (isVerified != null) body['is_verified'] = isVerified;
      if (photoUrl != null) body['photo_url'] = photoUrl;
      if (similarityScore != null) body['similarity_score'] = similarityScore;
      if (remark != null) body['remark'] = remark;
      if (attendanceAllotedHr != null) body['attendance_alloted_hr'] = attendanceAllotedHr;

      final response = await http.put(
        Uri.parse('$API_BASE_URL/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update attendance');
      }
    } catch (e) {
      throw Exception('Error updating attendance: $e');
    }
  }

  // ==========================================
  // DELETE ATTENDANCE
  // ==========================================
  static Future<Map<String, dynamic>> deleteAttendance(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$API_BASE_URL/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to delete attendance');
      }
    } catch (e) {
      throw Exception('Error deleting attendance: $e');
    }
  }

  // ==========================================
  // GET ATTENDANCE REPORT (Date Range)
  // ==========================================
  static Future<List<Map<String, dynamic>>> getAttendanceReport({
    required String instituteId,
    required String fromDate,
    required String toDate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'institute_id': instituteId,
          'from_date': fromDate,
          'to_date': toDate,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['report'] ?? []);
      } else {
        throw Exception('Failed to fetch attendance report');
      }
    } catch (e) {
      throw Exception('Error fetching attendance report: $e');
    }
  }
}
