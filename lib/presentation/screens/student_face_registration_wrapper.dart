import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_db.dart';
import '../../core/student_face_embedding_utils.dart';
import '../../core/utils/professional_messaging.dart';
import '../../services/b2b_storage_service.dart';
import '../../services/face_recognition_service.dart';
import '../../services/student_face_match_index.dart';
import '../../services/photo_compression_service.dart';
import '../../services/location_monitor_service.dart' show LocationVerificationService;
import '../../services/pin_session_manager.dart';
import '../../services/distance_check_service.dart';
import '../../services/anti_spoof_api_service.dart';
import 'attendance_camera_screen.dart';

/// Postgres `uuid` column compatible (RFC 4122 variant 4).
String _randomUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

/// Face enrollment: **3 photos** (front, left, right) with MobileFaceNet templates.
/// One-photo flow kept only for [changePhotoOnce].
class StudentFaceRegistrationWrapper extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String srNo;
  final String instituteId;
  final VoidCallback onRegistrationSuccess;

  /// When true, replaces the saved registration photo once (archives the previous photo).
  final bool changePhotoOnce;

  const StudentFaceRegistrationWrapper({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.srNo,
    required this.instituteId,
    required this.onRegistrationSuccess,
    this.changePhotoOnce = false,
  });

  @override
  State<StudentFaceRegistrationWrapper> createState() =>
      _StudentFaceRegistrationWrapperState();
}

class _StudentFaceRegistrationWrapperState
    extends State<StudentFaceRegistrationWrapper> {
  bool _isCheckingRegistration = true;
  bool _isSaving = false;
  bool _hasExistingRegistration = false;
  bool _allowReregister = false;

  @override
  void initState() {
    super.initState();
    _checkExistingRegistration();
  }

  Future<void> _checkExistingRegistration() async {
    try {
      final student = await appDb
          .from('students')
          .select(
            'face_embedding_front, face_photo_url, face_registration_status',
          )
          .eq('id', widget.studentId)
          .eq('institute_id', widget.instituteId)
          .maybeSingle();

      // Check if student has existing face registration
      final hasEmbedding = student != null &&
          (student['face_registration_status'] == 'registered' ||
           student['face_embedding_front'] != null);
      final alreadyChanged = false; // New system doesn't track this

      if (!mounted) return;
      if (widget.changePhotoOnce && alreadyChanged) {
        setState(() => _isCheckingRegistration = false);
        ProfessionalMessaging.showError(
          context,
          title: 'Already changed',
          message:
              'This student\'s registration photo was already updated once. Contact admin if another change is needed.',
        );
        Navigator.pop(context);
        return;
      }

      setState(() {
        _hasExistingRegistration = hasEmbedding;
        _isCheckingRegistration = false;
        if (widget.changePhotoOnce && hasEmbedding) {
          _allowReregister = true;
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error checking existing face registration: $e');
      }
      if (!mounted) return;
      setState(() => _isCheckingRegistration = false);
    }
  }

  Future<void> _captureAndSave() async {
    if (widget.changePhotoOnce) {
      await _captureOnePhotoAndSave();
    } else {
      await _captureThreeAnglePhotosAndSave();
    }
  }

  Future<void> _captureThreeAnglePhotosAndSave() async {
    if (_isSaving) return;

    final hasPinSession = await PinSessionManager.hasActivePinSession();
    if (hasPinSession) {
      final locationVerification = await LocationVerificationService.verifyLocationNow(
        instituteId: widget.instituteId,
      );
      if (!locationVerification.isWithinRadius) {
        if (mounted) {
          ProfessionalMessaging.showError(
            context,
            title: 'Outside Location',
            message: locationVerification.error ??
                'You are outside the locked institute GPS zone.',
          );
        }
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      // 🔥 Use old AttendanceCameraScreen with multi-pose registration (3 photos: front, left, right)
      if (!mounted) return;
      final photos = await Navigator.push<List<XFile>>(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceCameraScreen(
            studentName: widget.studentName,
            studentId: widget.studentId,
            multiPoseRegistration: true,  // 🎯 3-angle registration mode
            autoCaptureWhenReady: true,
            requireBlink: true,
          ),
        ),
      );

      if (photos == null || photos.length != 3) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      print('✅ Got 3 photos from camera');
      print('📸 Front: ${photos[0].path}');
      print('📸 Left: ${photos[1].path}');
      print('📸 Right: ${photos[2].path}');

      // 🔥 Send to backend for 512-D ArcFace embeddings (HIGH ACCURACY!)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                'Generating 512-D ArcFace embeddings...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );

      print('📤 Sending 3 photos to backend for ArcFace processing...');
      final result = await AntiSpoofApiService.registerStudentFace(
        studentId: widget.studentId,
        studentName: widget.studentName,
        frontPhoto: File(photos[0].path),
        leftPhoto: File(photos[1].path),
        rightPhoto: File(photos[2].path),
        instituteId: widget.instituteId,
      );

      if (!mounted) {
        Navigator.pop(context);
        return;
      }
      Navigator.pop(context); // Close loading dialog

      // Check backend response
      if (result['success'] != true) {
        throw Exception(result['message'] ?? 'Backend registration failed');
      }

      print('✅ Backend generated 512-D embeddings');
      final embeddings = result['embeddings'] as Map<String, dynamic>?;
      if (embeddings == null) {
        throw Exception('No embeddings in response');
      }

      // Extract embeddings from backend response (3 angles only)
      final frontEmbedding = List<double>.from(
        (embeddings['face_embedding_front'] as List?)?.map((x) => (x as num).toDouble()) ?? [],
      );
      final leftEmbedding = List<double>.from(
        (embeddings['face_embedding_left'] as List?)?.map((x) => (x as num).toDouble()) ?? [],
      );
      final rightEmbedding = List<double>.from(
        (embeddings['face_embedding_right'] as List?)?.map((x) => (x as num).toDouble()) ?? [],
      );

      print('✅ Front: ${frontEmbedding.length}-D');
      print('✅ Left: ${leftEmbedding.length}-D');
      print('✅ Right: ${rightEmbedding.length}-D');

      // 📸 Upload photos to Backblaze B2 with compression
      print('📸 Compressing & uploading photos to Backblaze B2...');
      String? facePhotoUrl;
      bool photosUploadedSuccessfully = false;

      try {
        // Compress each photo first
        final frontBytes = await PhotoCompressionService.compressPhoto(photos[0].path);
        final leftBytes = await PhotoCompressionService.compressPhoto(photos[1].path);
        final rightBytes = await PhotoCompressionService.compressPhoto(photos[2].path);

        print('  ✅ Front: ${(frontBytes.length / 1024).toStringAsFixed(1)}KB');
        print('  ✅ Left: ${(leftBytes.length / 1024).toStringAsFixed(1)}KB');
        print('  ✅ Right: ${(rightBytes.length / 1024).toStringAsFixed(1)}KB');

        // Generate path: instituteId/studentName/photo-registration/
        final photoPath = '${widget.instituteId}/${widget.studentName}/photo-registration';

        // Upload front photo (primary registration photo)
        facePhotoUrl = await B2BStorageService.uploadFile(
          '$photoPath/front.jpg',
          frontBytes,
          contentType: 'image/jpeg',
        );
        print('✅ Front photo uploaded: $facePhotoUrl');

        // Upload left photo
        await B2BStorageService.uploadFile(
          '$photoPath/left.jpg',
          leftBytes,
          contentType: 'image/jpeg',
        );
        print('✅ Left photo uploaded');

        // Upload right photo
        await B2BStorageService.uploadFile(
          '$photoPath/right.jpg',
          rightBytes,
          contentType: 'image/jpeg',
        );
        print('✅ Right photo uploaded');

        photosUploadedSuccessfully = true;
      } catch (e) {
        print('❌ Photo upload FAILED (CRITICAL): $e');
        throw Exception('Photo upload failed - registration incomplete: $e');
      }

      // ✅ Only mark as "registered" if BOTH embeddings AND photos are saved
      if (!photosUploadedSuccessfully || facePhotoUrl == null) {
        throw Exception('Photos not uploaded - cannot complete registration');
      }

      // 💾 Save 512-D embeddings + photo URL to database (ONLY IF ALL SUCCESSFUL)
      print('💾 Saving 512-D ArcFace embeddings (3 angles) + photo URL to database...');
      await appDb.from('students').update({
        'face_embedding_front': jsonEncode(frontEmbedding),
        'face_embedding_left': jsonEncode(leftEmbedding),
        'face_embedding_right': jsonEncode(rightEmbedding),
        'face_photo_url': facePhotoUrl,
        'face_registration_status': 'registered',  // ✅ ONLY mark after ALL fields saved
        'is_face_real': true,
        'face_registered_at': DateTime.now().toIso8601String(),
      }).eq('sr_no', widget.srNo);

      print('✅ 512-D ArcFace embeddings (3 angles) saved! Uses MAX similarity for attendance');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${widget.studentName} registered with 3 embeddings!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      widget.onRegistrationSuccess();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Registration error: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog if open
        ProfessionalMessaging.showError(
          context,
          title: 'Registration failed',
          message: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _captureOnePhotoAndSave() async {
    if (_isSaving) return;

    // 🔍 GPS VERIFICATION: Verify location before face registration (for PIN login users)
    final hasPinSession = await PinSessionManager.hasActivePinSession();
    if (hasPinSession) {
      final locationVerification = await LocationVerificationService.verifyLocationNow(
        instituteId: widget.instituteId,
      );

      if (!locationVerification.isWithinRadius) {
        if (mounted) {
          ProfessionalMessaging.showError(
            context,
            title: 'Outside Location',
            message: locationVerification.error ??
                'You are outside the locked institute GPS zone (${locationVerification.distance != null ? PinSessionManager.formatDistance(locationVerification.distance!) : "unknown"} from center). '
                'Stand where attendance is locked, improve GPS signal (e.g. near a window), and try again.',
          );
        }
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      // 📱 Open Media Pipe camera with live distance checking
      XFile? picked;
      try {
        picked = await Navigator.push<XFile>(
          context,
          MaterialPageRoute(
            builder: (_) => AttendanceCameraScreen(
              studentName: widget.studentName,
              studentId: widget.studentId,
              registrationPose: 'front',
              autoCaptureWhenReady: true,
            ),
          ),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('❌ Camera screen error: $e');
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      if (picked == null) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      final workPath =
          await FaceRecognitionService.ensureNormalizedJpegForFacePipeline(
            picked.path,
          );

      final prepared = widget.changePhotoOnce
          ? await FaceRecognitionService.prepareFacePhotoChangeOnePhoto(
              workPath,
              widget.instituteId,
              widget.srNo,
              widget.studentId,
            )
          : await FaceRecognitionService.prepareFaceRegistrationOnePhoto(
              workPath,
              widget.instituteId,
              widget.srNo,
              widget.studentId,
            );

      if (prepared == null) {
        throw Exception(
          'Could not prepare face registration. Try a clearer photo with one face and good light.',
        );
      }

      var photoBytes = await File(workPath).readAsBytes();

      // Generate tiny thumbnail for instant loading
      final tinyThumbnail = await PhotoCompressionService.createTinyThumbnail(photoBytes);

      photoBytes = await PhotoCompressionService.compressPhotoBytes(photoBytes);

      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final photoPath =
          'registrations/${widget.instituteId}/${widget.studentId}_$timestamp.jpg';
      final photoUrl = await B2BStorageService.uploadFile(
        photoPath,
        photoBytes,
        contentType: 'image/jpeg',
      );

      // Increment photo version to bust cache
      final currentStudent = await appDb
          .from('students')
          .select(
            'photo_version, face_photo_url, registration_photo_path, face_photo_changed_once, face_embedding',
          )
          .eq('id', widget.studentId)
          .maybeSingle();
      final int newVersion = (currentStudent?['photo_version'] as int? ?? 0) + 1;

      final embeddingField = prepared.embeddingPayload['embedding'];
      if (embeddingField is! List) {
        throw Exception('Invalid embedding payload — cannot save face templates');
      }
      final List<double> cleanEmbedding = List<double>.from(
        embeddingField.map((e) => (e as num).toDouble()),
      );
      final mergedEmbeddingPayload = appendFaceTemplateToPayload(
        currentStudent?['face_embedding'],
        cleanEmbedding,
        pose: 'front',
      );

      await _persistRegistration(
        photoUrl: photoUrl,
        photoPath: photoPath,
        tinyThumbnail: tinyThumbnail,
        newVersion: newVersion,
        mergedEmbeddingPayload: mergedEmbeddingPayload,
        primaryEmbedding: cleanEmbedding,
        currentStudent: currentStudent,
        successTitle: widget.changePhotoOnce ? 'Photo updated' : 'Registration complete',
        successMessage: widget.changePhotoOnce
            ? '${widget.studentName}\'s registration photo was changed once.\n\nAttendance will use the new face. The previous photo is kept on the MSCE website.'
            : '${widget.studentName}\'s face was saved from one photo.\n\nReady for attendance.',
      );
    } on DuplicateFaceRegistrationException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      final title = msg.contains('similar') ||
              msg.contains('blocked') ||
              msg.contains('cannot register twice')
          ? 'Duplicate face'
          : msg.contains('not found')
              ? 'Student not found'
              : msg.contains('already changed')
                  ? 'Already changed'
                  : msg.contains('register the face first')
                      ? 'Face not registered'
                      : 'Cannot update photo';
      ProfessionalMessaging.showError(
        context,
        title: title,
        message: e.message,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Face registration error: $e');
      if (!mounted) return;
      ProfessionalMessaging.showError(
        context,
        title: 'Registration failed',
        message: ProfessionalMessaging.messageForFaceProcessingError(e),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _persistRegistration({
    required String photoUrl,
    required String photoPath,
    required String? tinyThumbnail,
    required int newVersion,
    required Map<String, dynamic> mergedEmbeddingPayload,
    required List<double> primaryEmbedding,
    required Map<String, dynamic>? currentStudent,
    required String successTitle,
    required String successMessage,
    List<List<double>> duplicateCheckEmbeddings = const [],
  }) async {
    final embeddingsToCheck = duplicateCheckEmbeddings.isNotEmpty
        ? duplicateCheckEmbeddings
        : [primaryEmbedding];
    await FaceRecognitionService.assertNoDuplicateRegistration(
      embeddings: embeddingsToCheck,
      instituteId: widget.instituteId,
      excludeStudentId: widget.studentId,
    );

    final updatePayload = <String, dynamic>{
      'face_photo_url': photoUrl,
      'registration_photo_path': photoPath,
      'photo_thumbnail': tinyThumbnail,
      'photo_version': newVersion,
      'face_embedding': mergedEmbeddingPayload,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (widget.changePhotoOnce) {
      final prevUrl = currentStudent?['face_photo_url']?.toString().trim() ?? '';
      final prevPath =
          currentStudent?['registration_photo_path']?.toString().trim() ?? '';
      if (prevUrl.isNotEmpty) {
        updatePayload['original_face_photo_url'] = prevUrl;
      }
      if (prevPath.isNotEmpty) {
        updatePayload['original_registration_photo_path'] = prevPath;
      }
      updatePayload['face_photo_changed_once'] = true;
      updatePayload['face_photo_changed_at'] =
          DateTime.now().toUtc().toIso8601String();
    }

    await appDb.from('students').update(updatePayload).eq('id', widget.studentId);
    StudentFaceMatchIndex.invalidateCache();

    final existingRegistration = await appDb
        .from('student_registrations')
        .select('id')
        .eq('student_id', widget.studentId)
        .maybeSingle();

    final faceEmbeddingPgArray =
        jsonDecode(jsonEncode(primaryEmbedding)) as List<dynamic>;

    late final String registrationId;
    try {
      if (existingRegistration != null) {
        registrationId = existingRegistration['id']!.toString();
        await appDb.from('student_registrations').update(<String, dynamic>{
          'student_id': widget.studentId,
          'registration_photo_path': photoUrl,
          'face_embedding': faceEmbeddingPgArray,
        }).eq('id', registrationId);
      } else {
        registrationId = _randomUuidV4();
        await appDb.from('student_registrations').insert(<String, dynamic>{
          'id': registrationId,
          'student_id': widget.studentId,
          'registration_photo_path': photoUrl,
          'face_embedding': faceEmbeddingPgArray,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ student_registrations optional sync failed (${e.code}): ${e.message}',
        );
      }
    }

    if (!mounted) return;
    ProfessionalMessaging.showSuccess(
      context,
      title: successTitle,
      message: successMessage,
    );

    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) {
      widget.onRegistrationSuccess();
      Navigator.pop(context, {
        'success': true,
        'registrationId': registrationId,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingRegistration) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking existing face registration...'),
            ],
          ),
        ),
      );
    }

    if (_hasExistingRegistration && !_allowReregister && !widget.changePhotoOnce) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face registration')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.verified_user, size: 56, color: Colors.green),
                const SizedBox(height: 16),
                Text(
                  '${widget.studentName} already has a saved face embedding.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Attendance uses 3 face templates (front, left, right). Tap Register again to replace all 3 photos.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go back'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _allowReregister = true),
                    child: const Text('Register again'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isChange = widget.changePhotoOnce;
    return Scaffold(
      appBar: AppBar(
        title: Text(isChange ? 'Change registration photo' : 'Face registration'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isSaving) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(isChange ? 'Saving new photo…' : 'Saving face template…'),
              ] else ...[
                const Icon(
                  Icons.camera_alt_outlined,
                  size: 56,
                  color: Colors.blue,
                ),
                const SizedBox(height: 16),
                Text(
                  isChange
                      ? 'One-time photo change for ${widget.studentName}'
                      : '3 photos for ${widget.studentName}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  isChange
                      ? 'You can do this only once. The app will show your new photo; the old one stays on the MSCE website.'
                      : 'Front, left, and right — 3 photos with the back camera. '
                          '${DistanceCheckService.recommendedDistanceShort} (same as auto attendance).',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _captureAndSave,
                    icon: const Icon(Icons.photo_camera),
                    label: Text(
                      isChange
                          ? 'Take new registration photo'
                          : 'Start 3-photo registration',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

}
