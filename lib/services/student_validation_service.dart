import 'dart:io';

import '../core/app_db.dart';
import 'face_recognition_service.dart';

/// Validation service for student data to prevent duplicates
class StudentValidationService {
  /// Check if a student with the same full name already exists
  /// ⚠️ STRICT: No exceptions - even editing is not allowed
  static Future<String?> validateDuplicateName({
    required String studentName,
    required String instituteId,
  }) async {
    try {
      final name = studentName.trim();
      if (name.isEmpty) {
        return 'Student name cannot be empty';
      }

      // Query students with same name
      List<dynamic> results = await appDb
          .from('students')
          .select('id, name')
          .eq('institute_id', instituteId)
          .ilike('name', name); // Case-insensitive search

      // If ANY student exists with this name, block it
      if (results.isNotEmpty) {
        return '❌ Student with name "$studentName" already exists. '
            'Each student must have a unique name. Cannot edit to duplicate name.';
      }

      return null; // No duplicate found
    } catch (e) {
      return '⚠️ Error checking duplicate name: $e';
    }
  }

  /// Check if photo is already registered to another student
  /// ⚠️ STRICT: No exceptions - even editing is not allowed
  static Future<String?> validateDuplicatePhoto({
    required String photoPath,
    required String instituteId,
  }) async {
    try {
      final work = await FaceRecognitionService.ensureNormalizedJpegForFacePipeline(photoPath);
      try {
        final features = await FaceRecognitionService.extractFaceFeatures(work);
        if (features == null) {
          return await FaceRecognitionService.getDiagnosticReasonForInvalidFace(work) ??
              'Could not read a clear face. Try better lighting, one person in the frame, and a steady shot.';
        }

        // Extract neural embedding - no exclusion, strict check
        final embedding = await FaceRecognitionService
            .duplicateRegistrationBlockedMessage(
          work,
          features,
          instituteId,
          excludeStudentId: null, // NO EXCLUSION - STRICT
        );

        if (embedding != null) {
          return embedding; // Face already registered to someone else
        }

        return null; // Photo is unique
      } finally {
        if (work != photoPath) {
          try {
            await File(work).delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      return '⚠️ Error checking photo: $e';
    }
  }

  /// Check if student already marked attendance today
  static Future<String?> validateDuplicateAttendanceToday({
    required String studentId,
    required String instituteCode,
    required DateTime attendanceDate,
  }) async {
    try {
      final dateStr = attendanceDate.toString().split(' ')[0]; // YYYY-MM-DD

      // Check if student has any attendance records for today
      List<dynamic> records = await appDb
          .from('attendance_in_out')
          .select('id')
          .eq('student_id', studentId)
          .eq('institute_code', instituteCode)
          .eq('attendance_date', dateStr);

      if (records.isNotEmpty) {
        return '⚠️ This student already has attendance marked for today. '
            'View existing record or use Edit to update.';
      }

      return null; // No attendance marked yet
    } catch (e) {
      return '⚠️ Error checking attendance: $e';
    }
  }

  /// Check if student has valid registration before marking attendance
  static Future<String?> validateStudentReadyForAttendance({
    required String studentId,
    required String instituteId,
  }) async {
    try {
      // Check if student exists
      final student = await appDb
          .from('students')
          .select('id, name, face_embedding')
          .eq('id', studentId)
          .eq('institute_id', instituteId)
          .maybeSingle();

      if (student == null) {
        return '❌ Student not found in database';
      }

      // Check if student has face registered
      final faceEmbedding = student['face_embedding'];
      if (faceEmbedding == null) {
        return '❌ Student face not registered. Register face first before marking attendance.';
      }

      // Check if face data is valid
      final faceData = faceEmbedding is Map ? faceEmbedding : null;
      if (faceData == null || faceData['embedding'] == null) {
        return '❌ Student face data is invalid. Re-register the face.';
      }

      return null; // Student is ready
    } catch (e) {
      return '⚠️ Error validating student: $e';
    }
  }

  /// Comprehensive validation for student registration (name uniqueness only).
  static Future<String?> validateNewStudentRegistration({
    required String studentName,
    required String instituteId,
  }) async {
    return validateDuplicateName(
      studentName: studentName,
      instituteId: instituteId,
    );
  }

  /// Comprehensive validation for attendance marking
  static Future<String?> validateAttendanceMarking({
    required String studentId,
    required String instituteCode,
    required String instituteId,
    required DateTime attendanceDate,
    /// Admin per-subject flow may record multiple entry/exit pairs per calendar day.
    bool skipDuplicateTodayCheck = false,
  }) async {
    // Check if student is ready
    final readyError = await validateStudentReadyForAttendance(
      studentId: studentId,
      instituteId: instituteId,
    );
    if (readyError != null) return readyError;

    if (!skipDuplicateTodayCheck) {
      final dupError = await validateDuplicateAttendanceToday(
        studentId: studentId,
        instituteCode: instituteCode,
        attendanceDate: attendanceDate,
      );
      if (dupError != null) return dupError;
    }

    return null; // All validations passed
  }
}
