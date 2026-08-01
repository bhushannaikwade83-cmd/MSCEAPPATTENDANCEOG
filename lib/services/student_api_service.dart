import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

class StudentApiService {
  static final _supabase = Supabase.instance.client;

  /// Get all students (paginated)
  static Future<List<Map<String, dynamic>>> getStudents({
    int page = 0,
    int pageSize = 20,
    String? searchQuery,
  }) async {
    try {
      var query = _supabase
          .from('students')
          .select('id,sr_no,fname,lname,mname,inst_id,form_serial_no,ph_name,sub1,sub2,sub3,sub4,sub5,sub6,sub7,sub8,mother_nm,ctcd,identy_no,face_photo_url,face_embedding_front,face_embedding_left,face_embedding_right,face_registered_at,face_registration_status,is_face_real,created_at,updated_at')
          .order('sr_no');

      // Get data - handle search locally if needed
      final from = page * pageSize;
      final to = from + pageSize - 1;

      var response = await query.range(from, to);

      // Apply search filter locally
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final searchLower = searchQuery.toLowerCase();
        response = response.where((student) {
          final fname = (student['fname'] as String?)?.toLowerCase() ?? '';
          final lname = (student['lname'] as String?)?.toLowerCase() ?? '';
          final srNo = (student['sr_no'] as String?)?.toLowerCase() ?? '';

          return fname.contains(searchLower) ||
                 lname.contains(searchLower) ||
                 srNo.contains(searchLower);
        }).toList();
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching students: $e');
      return [];
    }
  }

  /// Get single student by SR_NO
  static Future<Map<String, dynamic>?> getStudentBySrNo(String srNo) async {
    try {
      final response = await _supabase
          .from('students')
          .select()
          .eq('sr_no', srNo)
          .single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      print('Error fetching student: $e');
      return null;
    }
  }

  /// Create new student
  static Future<bool> createStudent({
    required String srNo,
    required String fname,
    required String lname,
    String? mname,
    String? formSerialNo,
    String? instId,
    String? phName,
    String? ctcd,
    String? motherNm,
    String? identyNo,
    String? sub1,
    String? sub2,
    String? sub3,
    String? sub4,
    String? sub5,
    String? sub6,
    String? sub7,
    String? sub8,
  }) async {
    try {
      await _supabase.from('students').insert({
        'sr_no': srNo,
        'fname': fname,
        'lname': lname,
        'mname': mname,
        'form_serial_no': formSerialNo,
        'inst_id': instId,
        'ph_name': phName,
        'ctcd': ctcd,
        'mother_nm': motherNm,
        'identy_no': identyNo,
        'sub1': sub1,
        'sub2': sub2,
        'sub3': sub3,
        'sub4': sub4,
        'sub5': sub5,
        'sub6': sub6,
        'sub7': sub7,
        'sub8': sub8,
        'face_registration_status': 'pending',
        'is_face_real': false,
      });

      return true;
    } catch (e) {
      print('Error creating student: $e');
      return false;
    }
  }

  /// Update student face registration
  static Future<bool> updateStudentFaceRegistration({
    required String srNo,
    required List<double> frontEmbedding,
    required List<double> leftEmbedding,
    required List<double> rightEmbedding,
    required double qualityFront,
    required double qualityLeft,
    required double qualityRight,
    required String facePhotoUrl,
  }) async {
    try {
      // Calculate average embedding
      final List<double> avgEmbedding = List.generate(
        frontEmbedding.length,
        (i) => (frontEmbedding[i] + leftEmbedding[i] + rightEmbedding[i]) / 3,
      );

      await _supabase.from('students').update({
        'face_embedding_front': jsonEncode(frontEmbedding),
        'face_embedding_left': jsonEncode(leftEmbedding),
        'face_embedding_right': jsonEncode(rightEmbedding),
        'face_photo_url': facePhotoUrl,
        'face_registered_at': DateTime.now().toIso8601String(),
        'face_registration_status': 'registered',
        'is_face_real': true,
      }).eq('sr_no', srNo);

      return true;
    } catch (e) {
      print('Error updating face registration: $e');
      return false;
    }
  }

  /// Get all students pending face registration
  static Future<List<Map<String, dynamic>>> getPendingRegistrations() async {
    try {
      final response = await _supabase
          .from('students')
          .select('sr_no,fname,lname,face_registration_status')
          .eq('face_registration_status', 'pending')
          .order('sr_no');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching pending registrations: $e');
      return [];
    }
  }

  /// Get all registered students (ready for auto-attendance)
  static Future<List<Map<String, dynamic>>> getRegisteredStudents() async {
    try {
      final response = await _supabase
          .from('students')
          .select('sr_no,fname,lname,face_embedding_front,face_embedding_left,face_embedding_right,is_face_real')
          .eq('face_registration_status', 'registered')
          .eq('is_face_real', true)
          .order('sr_no');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching registered students: $e');
      return [];
    }
  }

  /// Update attendance for student
  static Future<bool> markAttendance({
    required String srNo,
    required String status,
    required double? similarityScore,
    required String? matchedAngle,
    String? entryPhotoUrl,
    String? exitPhotoUrl,
  }) async {
    try {
      // Update student's last attendance photo
      final updateData = <String, dynamic>{};

      if (entryPhotoUrl != null) {
        updateData['entry_photo_url'] = entryPhotoUrl;
      }
      if (exitPhotoUrl != null) {
        updateData['exit_photo_url'] = exitPhotoUrl;
      }

      if (updateData.isNotEmpty) {
        await _supabase.from('students').update(updateData).eq('sr_no', srNo);
      }

      // Insert attendance record
      await _supabase.from('attendance_records').insert({
        'sr_no': srNo,
        'date': DateTime.now().toIso8601String().split('T')[0],
        'timestamp': DateTime.now().toIso8601String(),
        'status': status,
        'similarity_score': similarityScore,
        'matched_angle': matchedAngle,
      });

      return true;
    } catch (e) {
      print('Error marking attendance: $e');
      return false;
    }
  }

  /// Get today's attendance for student
  static Future<List<Map<String, dynamic>>> getTodayAttendance(String srNo) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      final response = await _supabase
          .from('attendance_records')
          .select()
          .eq('sr_no', srNo)
          .eq('date', today)
          .order('timestamp', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching attendance: $e');
      return [];
    }
  }

  /// Get student statistics
  static Future<Map<String, dynamic>> getStudentStats() async {
    try {
      // Total students
      final totalResponse = await _supabase
          .from('students')
          .select('sr_no');
      final total = totalResponse.isEmpty ? 0 : totalResponse.length;

      // Registered faces
      final registeredResponse = await _supabase
          .from('students')
          .select('sr_no')
          .eq('face_registration_status', 'registered')
          .eq('is_face_real', true);
      final registered = registeredResponse.length;

      // Pending registration
      final pendingResponse = await _supabase
          .from('students')
          .select('sr_no')
          .eq('face_registration_status', 'pending');
      final pending = pendingResponse.length;

      return {
        'total': total,
        'registered': registered,
        'pending': pending,
        'percentage': registered > 0 ? ((registered / total) * 100).toStringAsFixed(1) : '0',
      };
    } catch (e) {
      print('Error fetching stats: $e');
      return {
        'total': 0,
        'registered': 0,
        'pending': 0,
        'percentage': '0',
      };
    }
  }
}
