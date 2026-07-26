import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../core/app_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/professional_messaging.dart';
import '../../services/auth_service.dart';
import '../../services/b2b_storage_service.dart';
import '../../services/face_recognition_service.dart';
import '../../services/photo_compression_service.dart';
import '../../services/subject_service.dart';
import '../widgets/session_monitor.dart';
import 'attendance_camera_screen.dart';
import 'help_desk_screen.dart';

class AddStudentScreen extends StatefulWidget {
  static const routeName = '/add-student';
  const AddStudentScreen({super.key});

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _yearController = TextEditingController();
  final AuthService _authService = AuthService();
  final SubjectService _subjectService = SubjectService();
  bool _isLoading = false;
  bool _isCapturingFace = false;
  bool _isLoadingSubjects = false;
  String? _facePhotoPath;
  bool _faceRegistered = false; // Set after one camera capture + embedding extracted
  List<double>? _faceEmbedding;
  Uint8List? _facePhotoBytes;
  String? _instituteId;
  String? _srNo; // Dense institute serial (1, 2, 3 …), matches DB after save
  List<Map<String, dynamic>> _availableSubjects = [];
  List<String> _selectedSubjects = []; // Multiple subjects

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();

    // Auto-populate year with current year
    final currentYear = DateTime.now().year;
    _yearController.text = 'Year $currentYear';

    _loadInstituteId();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _yearController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) {
        if (kDebugMode) debugPrint('No user logged in');
        return;
      }

      if (kDebugMode) debugPrint('Loading institute ID for user: ${user.id}');

      final profile = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      final foundInstituteId = profile?['institute_id'] as String?;
      if (foundInstituteId != null && foundInstituteId.isNotEmpty) {
        if (kDebugMode) debugPrint('✅ Institute from profile: $foundInstituteId');
        setState(() {
          _instituteId = foundInstituteId;
        });
        await _loadSubjects();
        return;
      }

      if (kDebugMode) debugPrint('⚠️ User not found in any institute');
    } catch (e) {
      if (kDebugMode) debugPrint('Institute load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading institute: ${e.toString()}'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }


  Future<void> _loadSubjects() async {
    if (_instituteId == null) {
      if (kDebugMode) debugPrint('⚠️ Cannot load subjects: instituteId is null');
      return;
    }

    setState(() => _isLoadingSubjects = true);
    try {
      _availableSubjects = await _subjectService.getSubjects(_instituteId!);
      
      // If no subjects, try to initialize defaults
      if (_availableSubjects.isEmpty) {
        try {
          await _subjectService.initializeDefaultSubjects(_instituteId!);
          _availableSubjects = await _subjectService.getSubjects(_instituteId!);
        } catch (initError) {
          if (kDebugMode) {
            debugPrint('⚠️ Could not initialize subjects (permission issue): $initError');
            debugPrint('   Subjects will need to be added manually in Firestore');
          }
          // Continue without subjects - user can add them manually
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading subjects: $e');
        debugPrint('   This might be a Firestore permissions issue.');
        debugPrint('   Please ensure subjects collection has proper read permissions.');
      }
      // Show user-friendly message
      if (mounted) {
        ProfessionalMessaging.showError(
          context,
          title: 'Failed to Load Subjects',
          message: 'Could not load subjects. Please add subjects manually or check Firestore permissions.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingSubjects = false);
      }
    }
  }

  /// Next dense serial for this institute (matches server [AuthService.addStudentManually]).
  Future<String> _generateNextSRNumber() async {
    try {
      if (_instituteId == null) {
        throw Exception('Institute ID not found');
      }
      final s = await _authService.previewNextStudentSrNo(_instituteId!);
      if (kDebugMode) debugPrint('✅ Generated SR_NO: $s');
      return s;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error generating SR_NO: $e');
      return '${DateTime.now().millisecondsSinceEpoch}';
    }
  }


  Future<void> _captureFacePhoto() async {
    setState(() => _isCapturingFace = true);

    try {
      if (_instituteId == null) {
        throw Exception('Institute ID not found');
      }

      _srNo ??= await _generateNextSRNumber();

      XFile? picked;
      try {
        picked = await Navigator.push<XFile>(
          context,
          MaterialPageRoute(
            builder: (_) => AttendanceCameraScreen(
              studentName:
                  '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
                      .trim()
                      .replaceAll(RegExp(r'\s+'), ' '),
              studentId: _srNo!,
              registrationPose: 'front',
              autoCaptureWhenReady: true,
            ),
          ),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('❌ Registration camera screen error: $e');
        rethrow;
      } finally {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        SessionMonitor.endSuppressResumeLock();
      }

      final xfile = picked;
      if (xfile == null) {
        // User cancelled
        setState(() => _isCapturingFace = false);
        return;
      }

      // Fix iOS/Android EXIF: ML Kit + TFLite must use the same upright pixels
      final workPath = await FaceRecognitionService.ensureNormalizedJpegForFacePipeline(xfile.path);

      if (kDebugMode) {
        debugPrint('📸 Photo captured: ${xfile.path} (face pipeline: $workPath)');
      }

      // Show processing message at bottom (like face registration message)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('🔄 Processing face...'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 90),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }

      // Extract embedding and photo data (aligned with detection / embedding)
      final photoBytes = await File(workPath).readAsBytes();

      if (kDebugMode) {
        debugPrint('🔄 Extracting face features...');
      }

      // Extract face features (async operation)
      final features = await FaceRecognitionService.extractFaceFeatures(workPath);
      if (features == null) {
        final detail = await FaceRecognitionService.getDiagnosticReasonForInvalidFace(workPath);
        throw Exception(detail ?? 'Could not extract face. Use good lighting, one person, facing the camera.');
      }

      if (kDebugMode) {
        debugPrint('✅ Face features extracted');
        debugPrint('🧠 Extracting neural embedding...');
      }

      // Extract embedding using MobileFaceNet
      final embedding = await FaceRecognitionService.extractNeuralEmbedding(
        workPath,
        features,
      );

      if (embedding == null || embedding.isEmpty) {
        throw Exception(
          'Neural face model failed. Reopen the app and try again, or check that the face model is installed.',
        );
      }

      if (kDebugMode) {
        debugPrint('✅ Face embedding extracted successfully');
      }

      // Dismiss "Processing face..." before duplicate check (may take a moment on slow networks).
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }

      // Check for duplicate registration (on main thread - database access)
      final duplicateError = await FaceRecognitionService.duplicateRegistrationBlockedMessageForEmbedding(
        embedding,
        _instituteId!,
        excludeStudentId: null,
      );

      if (duplicateError != null) {
        if (!mounted) return;
        ProfessionalMessaging.showError(
          context,
          title: 'Face Already Registered',
          message: duplicateError,
          durationSeconds: 5,
        );
        setState(() => _isCapturingFace = false);
        return;
      }

      // Face is valid and unique
      if (!mounted) return;

      // Store embedding and photo for later save
      setState(() {
        _facePhotoPath = workPath;
        _faceEmbedding = embedding;
        _facePhotoBytes = photoBytes;
        _faceRegistered = true;
        _isCapturingFace = false;
      });

      // Show success message
      if (mounted) {
        ProfessionalMessaging.showSuccess(
          context,
          title: 'Face saved',
          message: 'You can continue and submit the student form.',
          durationSeconds: 3,
        );
      }

      if (kDebugMode) {
        debugPrint('✅ Face registration complete');
        debugPrint('   _faceRegistered = $_faceRegistered');
        debugPrint('   Embedding: ${embedding.length}D vector');
        debugPrint('   Photo bytes: ${(photoBytes.length / 1024).toStringAsFixed(1)} KB');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ProfessionalMessaging.showError(
          context,
          title: 'Face not saved',
          message: ProfessionalMessaging.messageForFaceProcessingError(e),
          durationSeconds: 5,
        );
      }
      setState(() => _isCapturingFace = false);
    }
  }

  Future<void> _submit() async {
    if (kDebugMode) {
      debugPrint('🔵 _submit() called');
      debugPrint('   _faceRegistered: $_faceRegistered');
      debugPrint('   _faceEmbedding: ${_faceEmbedding != null}');
      debugPrint('   _selectedSubjects: ${_selectedSubjects.length}');
    }

    if (!_formKey.currentState!.validate()) {
      if (kDebugMode) debugPrint('❌ Form validation failed');
      return;
    }

    if (_selectedSubjects.isEmpty) {
      if (kDebugMode) debugPrint('❌ No subjects selected');
      ProfessionalMessaging.showWarning(
        context,
        title: 'Subject Selection Required',
        message: 'Please select at least one subject from the predefined list. Students can be enrolled in multiple subjects.',
      );
      return;
    }

    if (!_faceRegistered || _faceEmbedding == null || _facePhotoBytes == null) {
      if (kDebugMode) {
        debugPrint(
          '❌ Face not registered - registered=$_faceRegistered embedding=${_faceEmbedding != null} bytes=${_facePhotoBytes != null}',
        );
      }
      ProfessionalMessaging.showError(
        context,
        title: 'Face Registration Required',
        message: 'Please capture and register the student\'s face first. Click "Capture Face" button to take a photo.',
        durationSeconds: 5,
      );
      return;
    }

    if (kDebugMode) debugPrint('✅ All validations passed - proceeding with student creation');

    // Validate institute ID
    if (_instituteId == null || _instituteId!.isEmpty) {
      setState(() => _isLoading = false);
      ProfessionalMessaging.showError(
        context,
        title: 'Institute Not Found',
        message: 'Could not determine your institute. Please ensure you are logged in as an admin.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final firstName = _firstNameController.text.trim();
      final middleName = _middleNameController.text.trim();
      final lastName = _lastNameController.text.trim();

      if (kDebugMode) {
        debugPrint('📝 Adding student:');
        debugPrint('   Name: $firstName $middleName $lastName');
        debugPrint('   SR_NO: $_srNo');
        debugPrint('   Institute ID: $_instituteId');
        debugPrint('   Subjects: $_selectedSubjects');
      }

      final result = await _authService.addStudentManually(
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        year: _yearController.text.trim(),
        subject: _selectedSubjects.join(', '),
        subjects: _selectedSubjects,
        instituteId: _instituteId,
      );

      if (result['success'] == true) {
        final assignedSr = result['srNo']?.toString().trim();
        if (assignedSr != null && assignedSr.isNotEmpty) {
          _srNo = assignedSr;
        }
      }

      final resolvedInstituteId = (result['instituteId'] as String?)?.trim();
      if (result['success'] == true &&
          resolvedInstituteId != null &&
          _instituteId != null &&
          resolvedInstituteId != _instituteId) {
        setState(() => _isLoading = false);
        ProfessionalMessaging.showError(
          context,
          title: 'Institute Mismatch',
          message:
              'This device resolved a different institute while saving the student. Please logout and login again on this phone before retrying.',
        );
        return;
      }

      final studentId = result['studentId'] as String?;

      // One camera photo → embedding + B2 registration photo after student insert
      if (result['success'] &&
          _faceRegistered &&
          resolvedInstituteId != null &&
          studentId != null &&
          _faceEmbedding != null &&
          _facePhotoBytes != null) {
        try {
          if (kDebugMode) {
            debugPrint('📸 Saving face embedding + photo for student $studentId...');
          }

          // Re-check duplicate after student creation, before face is attached.
          // This protects against stale UI state or fast back-to-back registrations.
          final duplicateError = await FaceRecognitionService
              .duplicateRegistrationBlockedMessageForEmbedding(
            _faceEmbedding!,
            resolvedInstituteId,
            excludeStudentId: studentId,
          );
          if (duplicateError != null) {
            await appDb.from('students').delete().eq('id', studentId);
            setState(() => _isLoading = false);
            if (!mounted) return;
            ProfessionalMessaging.showError(
              context,
              title: 'Duplicate Face Detected',
              message:
                  '$duplicateError\n\nStudent record was not kept because the face matches another student.',
              durationSeconds: 6,
            );
            return;
          }

          final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
          final currentYear = DateTime.now().year.toString();
          final tinyThumbnail = await PhotoCompressionService.createTinyThumbnail(_facePhotoBytes!);

          if (kDebugMode) {
            debugPrint(
              '🗜️ Registration photo size: ${(_facePhotoBytes!.length / 1024).toStringAsFixed(1)} KB',
            );
          }
          final compressedPhotoBytes = await PhotoCompressionService.compressPhotoBytes(_facePhotoBytes!);
          if (kDebugMode) {
            debugPrint('✅ Compressed to: ${(compressedPhotoBytes.length / 1024).toStringAsFixed(1)} KB');
          }

          final uploadResult = await B2BStorageService.uploadAttendancePhoto(
            instituteId: resolvedInstituteId,
            folderYear: currentYear,
            rollNumber: _srNo!,
            subject: 'registration',
            date: timestamp,
            photoBytes: compressedPhotoBytes,
          );

          if (uploadResult['url'] != null && uploadResult['url']!.isNotEmpty) {
            final photoUrl = uploadResult['url']!;
            final currentStudent = await appDb
                .from('students')
                .select('photo_version')
                .eq('id', studentId)
                .maybeSingle();
            final int newVersion = (currentStudent?['photo_version'] as int? ?? 0) + 1;

            final embeddingMap = {
              'version': 2,
              'embedding': _faceEmbedding,
              'modelVersion': 'mobilefacenet_tflite_v1',
              'qualityScore': 95.0,
              'registrationMethod': 'mobile_camera_single',
            };

            final regPhotoPath = uploadResult['path']?.toString().trim() ?? '';
            await appDb.from('students').update({
              'face_embedding': embeddingMap,
              'face_photo_url': photoUrl,
              if (regPhotoPath.isNotEmpty) 'registration_photo_path': regPhotoPath,
              'photo_thumbnail': tinyThumbnail,
              'photo_version': newVersion,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', studentId);

            if (kDebugMode) {
              debugPrint('✅ Face registration saved (single camera)');
              debugPrint('   Photo URL: $photoUrl');
              debugPrint('   Embedding: ${_faceEmbedding!.length}D');
              debugPrint('   Thumbnail saved: ${tinyThumbnail.isNotEmpty}');
              debugPrint('   Photo version: $newVersion');
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Error saving face registration: $e');
        }
      } else if (result['success'] && !_faceRegistered) {
        // This should not happen as we check _faceRegistered before submit
        // But handle it just in case
        if (kDebugMode) {
          debugPrint('⚠️ WARNING: Student created but face was not registered!');
        }
        
        if (mounted) {
          ProfessionalMessaging.showError(
            context,
            title: 'Registration Error',
            message: 'Student was created but face registration status is invalid. Please contact support.',
          );
        }
      }

      setState(() => _isLoading = false);

      if (!mounted) return;

      if (result['success']) {
        ProfessionalMessaging.showSuccess(
          context,
          title: 'Student Added Successfully',
          message: '${_firstNameController.text.trim()} ${_middleNameController.text.trim()} ${_lastNameController.text.trim()}\n\nSR_NO: $_srNo\n\nFace recognition enabled for attendance marking.',
          actionLabel: 'Done',
          onAction: () {
            if (mounted) Navigator.pop(context, true);
          },
        );
      } else {
        ProfessionalMessaging.showError(
          context,
          title: 'Failed to Add Student',
          message: ProfessionalMessaging.getProfessionalErrorMessage(result['message'] ?? 'Unknown error occurred'),
        );
      }
    } catch (e, stackTrace) {
      setState(() => _isLoading = false);
      
      if (!mounted) return;
      
      if (kDebugMode) {
        debugPrint('❌ Unexpected error adding student: $e');
        debugPrint('   Stack trace: $stackTrace');
      }
      
      // Provide more specific error message
      String errorMessage = 'An unexpected error occurred while adding the student.';
      final errorString = e.toString().toLowerCase();
      
      if (errorString.contains('permission') || errorString.contains('permission-denied')) {
        errorMessage = 'Permission denied. Please check Firestore security rules for students collection.';
      } else if (errorString.contains('network') || errorString.contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection and try again.';
      } else if (errorString.contains('timeout')) {
        errorMessage = 'Request timed out. Please check your connection and try again.';
      } else {
        errorMessage = 'An unexpected error occurred: ${e.toString()}';
      }
      
      ProfessionalMessaging.showError(
        context,
        title: 'Failed to Add Student',
        message: errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Pop already happened, no action needed
          return;
        }
        // If pop was prevented, manually pop
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
      body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                _buildModernAppBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 24),
                          _buildGlassCard(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // First Name Field
                                _buildModernTextField(
                                  controller: _firstNameController,
                                  icon: Icons.person_outline,
                                  label: 'First Name',
                                  hint: 'Enter first name',
                                  validator: (v) => v!.isEmpty ? 'First name is required' : null,
                                ),
                                const SizedBox(height: 20),
                                // Middle Name Field
                                _buildModernTextField(
                                  controller: _middleNameController,
                                  icon: Icons.person_outline,
                                  label: 'Middle Name',
                                  hint: 'Enter middle name',
                                  validator: (v) => v!.isEmpty ? 'Middle name is required' : null,
                                ),
                                const SizedBox(height: 20),
                                // Last Name Field
                                _buildModernTextField(
                                  controller: _lastNameController,
                                  icon: Icons.person_outline,
                                  label: 'Last Name',
                                  hint: 'Enter last name',
                                  validator: (v) => v!.isEmpty ? 'Last name is required' : null,
                                ),
                                const SizedBox(height: 20),
                                // Year Field (Auto-populated)
                                _buildModernTextField(
                                  controller: _yearController,
                                  icon: Icons.calendar_today_outlined,
                                  label: 'Year',
                                  hint: 'Auto-generated from current date',
                                  readOnly: true,
                                  validator: (v) => v!.isEmpty ? 'Required' : null,
                                ),
                                const SizedBox(height: 16),
                                // Multiple Subject Selection
                                if (!_isLoadingSubjects && _availableSubjects.isNotEmpty) ...[
                                  Text(
                                    'Select Subjects (Multiple)',
                                    style: TextStyle(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.white.withValues(alpha: 0.9)
                                          : AppTheme.textDark,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    constraints: const BoxConstraints(maxHeight: 200),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.white.withValues(alpha: 0.1)
                                          : Colors.grey.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Theme.of(context).brightness == Brightness.dark
                                            ? Colors.white.withValues(alpha: 0.3)
                                            : AppTheme.textGray.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: _availableSubjects.length,
                                      itemBuilder: (context, index) {
                                        final subject = _availableSubjects[index];
                                        final subjectName = subject['name'] as String;
                                        final isSelected = _selectedSubjects.contains(subjectName);
                                        return CheckboxListTile(
                                          title: Text(
                                            subjectName,
                                            style: TextStyle(
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white
                                                  : AppTheme.textDark,
                                            ),
                                          ),
                                          value: isSelected,
                                          onChanged: (value) {
                                            setState(() {
                                              if (value == true) {
                                                _selectedSubjects.add(subjectName);
                                              } else {
                                                _selectedSubjects.remove(subjectName);
                                              }
                                            });
                                          },
                                          activeColor: AppTheme.primaryBlue,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                _buildFaceCaptureButton(),
                                  const SizedBox(height: 24),
                                  _buildSubmitButton(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                    },
                  ),
                ),
              ],
              ),
            ),
          ),
        ),
      );
  }

  Widget _buildModernAppBar() {
    return Container(
      width: double.infinity,
      color: AppTheme.primaryBlue,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Add New Student',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white, size: 24),
            onPressed: () {
              Navigator.pushNamed(context, HelpDeskScreen.routeName);
            },
            tooltip: 'Help & Instructions',
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.person_add, color: AppTheme.primaryBlue, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            'Register New Student',
            style: TextStyle(
              color: isDark ? Colors.white : AppTheme.textDark,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Fill in the details below',
            style: TextStyle(
              color: isDark ? Colors.white70 : AppTheme.textGray,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool readOnly = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: TextStyle(
        color: isDark ? Colors.white : AppTheme.textDark,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          color: isDark 
              ? Colors.white.withValues(alpha: 0.8) 
              : AppTheme.textDark.withValues(alpha: 0.7),
          fontSize: 14,
        ),
        hintStyle: TextStyle(
          color: isDark 
              ? Colors.white.withValues(alpha: 0.4) 
              : AppTheme.textGray.withValues(alpha: 0.6),
        ),
        prefixIcon: Icon(
          icon, 
          color: isDark 
              ? Colors.white.withValues(alpha: 0.8) 
              : AppTheme.primaryBlue,
          size: 20,
        ),
        filled: true,
        fillColor: isDark 
            ? Colors.white.withValues(alpha: 0.1) 
            : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.3) 
                : AppTheme.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.3) 
                : AppTheme.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.white : AppTheme.primaryBlue,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.accentRed, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.accentRed, width: 2),
        ),
        errorStyle: TextStyle(
          color: AppTheme.accentRed,
          fontSize: 12,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: validator,
    );
  }

  Widget _buildModernDropdown<T>({
    required T? value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required Function(T?) onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DropdownButtonFormField<T>(
      value: value,
      style: TextStyle(
        color: isDark ? Colors.white : AppTheme.textDark,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDark 
              ? Colors.white.withValues(alpha: 0.8) 
              : AppTheme.textDark.withValues(alpha: 0.7),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          icon, 
          color: isDark 
              ? Colors.white.withValues(alpha: 0.8) 
              : AppTheme.primaryBlue,
          size: 20,
        ),
        filled: true,
        fillColor: isDark 
            ? Colors.white.withValues(alpha: 0.1) 
            : Colors.white.withValues(alpha: 0.95),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.3) 
                : AppTheme.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.3) 
                : AppTheme.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.white : AppTheme.primaryBlue,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      dropdownColor: isDark ? AppTheme.primaryBlueDark : Colors.white,
      items: items,
      onChanged: onChanged,
      icon: Icon(
        Icons.arrow_drop_down,
        color: isDark 
            ? Colors.white.withValues(alpha: 0.8) 
            : AppTheme.primaryBlue,
      ),
      iconSize: 24,
    );
  }

  Widget _buildFaceCaptureButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Check if face is registered via either photo path or video embedding
    final isFaceRegistered =
        _faceRegistered && _faceEmbedding != null && _facePhotoBytes != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : AppTheme.primaryBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.3)
              : AppTheme.primaryBlue.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFaceRegistered ? Icons.face_retouching_natural : Icons.face,
            color: isFaceRegistered
                ? (isDark ? Colors.green : Colors.green.shade700)
                : (isDark ? Colors.white : AppTheme.primaryBlue),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isFaceRegistered
                      ? '✅ Face Successfully Registered'
                      : '📸 Capture Face',
                  style: TextStyle(
                    color: isFaceRegistered
                        ? (isDark ? Colors.green : Colors.green.shade700)
                        : (isDark ? Colors.white : AppTheme.textDark),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (!isFaceRegistered) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Take a live photo of the student\'s face',
                    style: TextStyle(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.7)
                          : AppTheme.textDark.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ready to add student - click "Add Student" below',
                    style: TextStyle(
                      color: isDark
                          ? Colors.green.withValues(alpha: 0.9)
                          : Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
          if (!isFaceRegistered) ...[
            TextButton(
              onPressed: _isCapturingFace ? null : _captureFacePhoto,
              child: _isCapturingFace
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: isDark ? Colors.white : AppTheme.primaryBlue,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Capture Now',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 24,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final faceReady = _faceRegistered && _faceEmbedding != null && _facePhotoBytes != null;
    final isEnabled = !_isLoading && faceReady;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: isEnabled
            ? const LinearGradient(
                colors: [Color(0xFF4CAF50), Color(0xFF45a049)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [Colors.grey.shade300, Colors.grey.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: isEnabled ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          disabledBackgroundColor: Colors.transparent,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    faceReady ? Icons.person_add_alt_1 : Icons.info_outline,
                    color: faceReady ? Colors.white : Colors.grey.shade600,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      faceReady
                          ? 'Add Student to System'
                          : 'Complete Face Registration First',
                      style: TextStyle(
                        color: faceReady ? Colors.white : Colors.grey.shade600,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
