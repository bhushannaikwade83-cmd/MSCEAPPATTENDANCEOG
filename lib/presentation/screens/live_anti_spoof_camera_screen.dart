import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/anti_spoof_api_service.dart';
import '../../services/attendance_photo_service.dart';

class LiveAntiSpoofCameraScreen extends StatefulWidget {
  static const routeName = '/live-anti-spoof-camera';
  final String? studentName;
  final String? studentId;
  final bool isRegistration;
  final String instituteId;

  const LiveAntiSpoofCameraScreen({
    super.key,
    this.studentName,
    this.studentId,
    this.isRegistration = false,
    required this.instituteId,
  });

  @override
  State<LiveAntiSpoofCameraScreen> createState() =>
      _LiveAntiSpoofCameraScreenState();
}

class _LiveAntiSpoofCameraScreenState extends State<LiveAntiSpoofCameraScreen> {
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  bool _cameraInitialized = false;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0; // 0 = front, 1 = back

  // UI State
  String _currentStage = 'Initializing...';
  bool _isCapturing = false;
  int _captureCountdown = 0;

  // Recognition
  String _matchedStudentName = '';
  double _similarityScore = 0.0;
  String _srNo = '';
  String _matchedStudentId = '';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      print('📷 [INIT] Initializing camera...');
      _cameras = await availableCameras();
      print('✅ [INIT] Available cameras: ${_cameras.length}');
      if (_cameras.isEmpty) {
        _setStatus('❌ No cameras found');
        print('❌ [INIT] No cameras available!');
        return;
      }

      // Print available cameras
      for (var i = 0; i < _cameras.length; i++) {
        print('   Camera $i: ${_cameras[i].name} (${_cameras[i].lensDirection})');
      }

      await _setupCamera(_currentCameraIndex);

      print('🔍 [INIT] Initializing FaceDetector...');
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: false,
          enableClassification: false,
        ),
      );
      print('✅ [INIT] FaceDetector initialized');

      setState(() {
        _cameraInitialized = true;
      });

      _setStatus('🎥 Ready - Press CAPTURE');
      print('✅ [INIT] Screen ready for attendance marking');
    } catch (e) {
      print('❌ [INIT] Initialization error: $e');
      _setStatus('❌ Error: $e');
    }
  }

  Future<void> _setupCamera(int cameraIndex) async {
    try {
      // Dispose old controller if exists
      if (_cameraInitialized) {
        await _cameraController.dispose();
      }

      final camera = _cameras[cameraIndex];
      print('📷 [CAMERA] Setting up camera: ${camera.name}');

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
      );

      await _cameraController.initialize();
      print('✅ [CAMERA] Camera initialized: ${camera.lensDirection}');
    } catch (e) {
      print('❌ [CAMERA] Setup error: $e');
      throw e;
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) {
      print('⚠️ Only ${_cameras.length} camera available');
      return;
    }

    try {
      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
      print('🔄 [CAMERA] Switching to camera $_currentCameraIndex');

      await _setupCamera(_currentCameraIndex);

      setState(() {
        _cameraInitialized = true;
      });

      print('✅ [CAMERA] Camera switched!');
    } catch (e) {
      print('❌ [CAMERA] Switch error: $e');
      _setStatus('❌ Camera switch error: $e');
    }
  }

  void _startCapture() async {
    print('📸 [CAPTURE] Button clicked!');

    setState(() {
      _isCapturing = true;
      _captureCountdown = 2;
      _currentStage = 'Capturing in 2...';
    });

    print('📸 [CAPTURE] Starting 2-second countdown...');

    for (int i = 2; i > 0; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _captureCountdown = i - 1;
          _currentStage = i > 1 ? 'Capturing in $i...' : 'Capturing...';
        });
        print('📸 [CAPTURE] Countdown: ${i-1}s');
      }
    }

    print('📸 [CAPTURE] Countdown complete, calling _performCapture()');
    if (mounted) {
      await _performCapture();
    }
  }

  Future<void> _performCapture() async {
    try {
      print('📸 [CAPTURE] Taking picture...');
      // Single frame capture (like registration)
      final picture = await _cameraController.takePicture();
      final imageFile = File(picture.path);
      print('✅ [CAPTURE] Picture taken: ${picture.path}');
      print('📊 [CAPTURE] File size: ${await imageFile.length()} bytes');

      setState(() {
        _currentStage = 'Matching Face...';
      });

      print('🔍 [DETECT] Starting face detection...');
      // Detect face in captured image
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);
      print('✅ [DETECT] Face detection complete. Faces found: ${faces.length}');

      if (!mounted) return;

      if (faces.isEmpty) {
        print('❌ [DETECT] No face detected in image');
        setState(() {
          _currentStage = '❌ No Face Detected';
        });
        await Future.delayed(const Duration(seconds: 2));
      } else if (faces.length > 1) {
        print('❌ [DETECT] Multiple faces detected: ${faces.length}');
        setState(() {
          _currentStage = '❌ Multiple Faces - Show Only 1';
        });
        await Future.delayed(const Duration(seconds: 2));
      } else {
        print('✅ [DETECT] Single face detected, proceeding to backend...');
        // Face detected - send to API
        print('🌐 [API] Calling /api/mark-attendance-auto...');
        final result = await AntiSpoofApiService.markAttendanceAuto(imageFile);
        print('✅ [API] Response received: $result');

        if (mounted) {
          if (result.containsKey('error')) {
            print('❌ [API] Error in response: ${result['error']}');
            setState(() {
              _currentStage = '❌ No Match Found';
            });
            await Future.delayed(const Duration(seconds: 2));
          } else {
            _matchedStudentName = result['student_name'] ?? 'Unknown';
            _similarityScore = result['similarity'] ?? 0.0;
            _srNo = result['sr_no'] ?? 'N/A';
            _matchedStudentId = result['student_id']?.toString() ?? '';

            // ⚠️ Both ENTRY and EXIT already marked today — skip save, no B2 upload
            if (result['already_marked'] == true) {
              print('⚠️ [MATCH] $_matchedStudentName already has ENTRY+EXIT today — skipping save');
              setState(() {
                _currentStage = '⚠️ Already Marked Today ($_matchedStudentName)';
              });
              await Future.delayed(const Duration(seconds: 2));
            } else {
              // ⚡ Backend already determined entry/exit (STEP 7) — no extra round trip
              final recordType = result['record_type'] ?? 'entry';

              print('✅ [MATCH] Student found: $_matchedStudentName');
              print('📊 [MATCH] SR No: $_srNo');
              print('📊 [MATCH] Similarity: ${(_similarityScore * 100).toStringAsFixed(1)}%');
              print('📍 [MATCH] Record type: $recordType');

              // Save attendance to Supabase
              print('💾 [SAVE] Saving attendance to Supabase...');
              await _saveAttendanceToSupabase(_srNo, recordType, picture.path);

              setState(() {
                _currentStage = '✅ Attendance Marked ($recordType)';
              });

              await Future.delayed(const Duration(seconds: 2));
            }
          }
        }
      }

      await imageFile.delete();
      print('🔄 [CAPTURE] Resetting for next student...');
      _resetUI();
    } catch (e) {
      print('❌ [CAPTURE] Exception occurred: $e');
      print('📍 Stack trace: ${StackTrace.current}');
      setState(() {
        _currentStage = '❌ Capture Error: $e';
      });
      await Future.delayed(const Duration(seconds: 2));
      _resetUI();
    }
  }

  void _resetUI() {
    if (mounted) {
      setState(() {
        _isCapturing = false;
        _matchedStudentName = '';
        _similarityScore = 0.0;
        _srNo = '';
        _matchedStudentId = '';
        _currentStage = 'Ready for Next Student';
      });
    }
  }

  void _setStatus(String status) {
    if (mounted) {
      setState(() => _currentStage = status);
    }
  }

  Future<void> _saveAttendanceToSupabase(
    String srNo,
    String recordType,
    String photoPath,
  ) async {
    try {
      print('💾 [SAVE] Saving attendance to attendance table...');

      final supabase = Supabase.instance.client;
      final now = DateTime.now();
      final today = now.toIso8601String().split('T')[0]; // YYYY-MM-DD

      // 📸 STEP 1: Compress and upload photo to B2
      String? photoUrl;
      try {
        print('   📸 Uploading compressed photo to B2...');
        final photoFile = File(photoPath);
        if (photoFile.existsSync()) {
          photoUrl = await AttendancePhotoService.uploadAttendancePhoto(
            photoFile: photoFile,
            srNo: srNo,
            studentName: _matchedStudentName,
            instituteId: widget.instituteId,
            recordType: recordType,
          );
        }
      } catch (e) {
        print('   ⚠️ Photo upload failed: $e');
        photoUrl = null;
      }

      // 💾 STEP 2: Save attendance record with photo URL
      await supabase.from('attendance').insert({
        'sr_no': srNo,
        'student_name': _matchedStudentName,
        'institute_id': widget.instituteId,
        'attendance_date': today,
        'record_type': recordType, // 'entry' or 'exit'
        'marked_time': now.toIso8601String(),
        'similarity_score': _similarityScore,
        'photo_url': photoUrl, // B2 public URL (compressed, <100KB)
        'embedding': '[]',
        'status': 'present',
        'is_verified': _similarityScore > 0.75,
      });

      print('✅ [SAVE] Attendance saved successfully:');
      print('   SR No: $srNo');
      print('   Student: $_matchedStudentName');
      print('   Type: $recordType');
      print('   Date: $today');
      print('   Time: $now');
      print('   Similarity: ${(_similarityScore * 100).toStringAsFixed(1)}%');
      print('   Photo URL: $photoUrl');
    } catch (e) {
      print('❌ [SAVE] Error saving attendance: $e');
      print('📍 [SAVE] Stack: ${StackTrace.current}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E27),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              Text(
                _currentStage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: Stack(
        children: [
          // Camera Feed
          SizedBox.expand(child: CameraPreview(_cameraController)),

          // Top Status
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentStage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_matchedStudentName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Student: $_matchedStudentName',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'SR No: $_srNo',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Match: ${(_similarityScore * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom Controls
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // CAPTURE Button
                ElevatedButton(
                  onPressed: _isCapturing ? null : _startCapture,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCapturing ? Colors.orange : Colors.green,
                    disabledBackgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _isCapturing ? 'CAPTURING... $_captureCountdown' : '✅ CAPTURE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // SWITCH Camera Button
                if (_cameras.length > 1)
                  ElevatedButton.icon(
                    onPressed: _isCapturing ? null : _switchCamera,
                    icon: const Icon(Icons.flip_camera_android),
                    label: const Text('SWITCH CAMERA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      disabledBackgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                if (_cameras.length > 1) const SizedBox(height: 12),
                // EXIT Button
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.7),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'EXIT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
