import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../services/anti_spoof_api_service.dart';
import '../../services/attendance_photo_service.dart';
import '../../services/backend_batch_service.dart';

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
  bool _faceDetected = false;
  int _blinkCount = 0;
  bool _autoCountdownStarted = false;

  // Face detection + eye tracking
  int? _lastEyeOpenCount;
  int _frameCounter = 0;
  int _framesSkipped = 0;
  int _framesProcessed = 0;
  static const int _frameSkip = 5; // Process every 5th frame

  // Recognition
  String _matchedStudentName = '';
  double _similarityScore = 0.0;
  String _srNo = '';
  String _matchedStudentId = '';

  // Face quality tracking
  double _faceQuality = 0.0; // 0.0 to 1.0

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

  /// Start streaming camera frames for face detection + blink detection
  void _startCameraFrameStream() {
    print('🎬 [STREAM] Checking stream conditions...');
    print('   Camera initialized: $_cameraInitialized');
    print('   Already streaming: ${_cameraController.value.isStreamingImages}');

    if (!_cameraInitialized) {
      print('❌ [STREAM] Camera not initialized yet!');
      return;
    }

    if (_cameraController.value.isStreamingImages) {
      print('⚠️ [STREAM] Already streaming!');
      return;
    }

    print('🎬 [STREAM] Starting frame stream...');

    _cameraController.startImageStream((CameraImage image) async {
      if (_isCapturing || _autoCountdownStarted) {
        return; // Skip processing if already capturing
      }

      _frameCounter++;
      if (_frameCounter % _frameSkip != 0) {
        _framesSkipped++;
        if (_framesSkipped % 50 == 0) {
          print('📹 [FRAME] Frames received: $_frameCounter | Skipped: $_framesSkipped | Processed: $_framesProcessed');
        }
        return; // Skip frames (every 5th frame)
      }

      _framesProcessed++;
      print('📹 [FRAME] Processing frame #$_framesProcessed (total: $_frameCounter)...');

      try {
        // Combine all planes for proper YUV420 processing
        final allBytesList = <int>[];
        for (int i = 0; i < image.planes.length; i++) {
          allBytesList.addAll(image.planes[i].bytes);
        }
        final allBytes = Uint8List.fromList(allBytesList);

        final inputImage = InputImage.fromBytes(
          bytes: allBytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes[0].bytesPerRow,
          ),
        );

        print('🔍 [DETECT] Running face detection...');
        final faces = await _faceDetector.processImage(inputImage);
        print('✅ [DETECT] Detection complete: ${faces.length} faces found');

        if (!mounted) return;

        if (faces.isEmpty) {
          print('❌ [DETECT] No faces in this frame');
          if (_faceDetected) {
            print('👤 [DETECT] Face lost');
            setState(() {
              _faceDetected = false;
              _currentStage = '👀 Position your face — blink to capture';
            });
          }
          return;
        }

        // Face detected
        final face = faces[0];

        // Calculate face quality (0-1 based on various factors)
        double quality = 0.8; // Base quality
        if (face.headEulerAngleY != null && face.headEulerAngleY! < 15) quality += 0.1;
        if (face.headEulerAngleZ != null && face.headEulerAngleZ! < 10) quality += 0.1;
        quality = quality.clamp(0.0, 1.0);

        if (!_faceDetected) {
          print('✅ [DETECT] Face detected! Quality: ${(quality * 100).toStringAsFixed(0)}%');
          setState(() {
            _faceDetected = true;
            _faceQuality = quality;
          });
        } else {
          setState(() {
            _faceQuality = quality;
          });
        }

        // Check for blink (eyes closed = headEulerAngleZ changes, or use eye landmarks)
        final leftEye = face.landmarks[FaceLandmarkType.leftEye];
        final rightEye = face.landmarks[FaceLandmarkType.rightEye];

        print('👁️ [EYES] Left eye: $leftEye | Right eye: $rightEye');

        // Simple blink detection: if both eyes are visible but tracking suggests closed
        int eyesOpenStatus = 0;
        if (leftEye != null && rightEye != null) {
          // If face is still tracked but eyes appear different, assume blink
          eyesOpenStatus = 1;
          print('   Eyes open status: OPEN (1)');
        } else {
          print('   Eyes open status: CLOSED (0)');
        }

        print('   Last eye status: $_lastEyeOpenCount | Current: $eyesOpenStatus');

        // Detect blink transition (open → closed → open)
        if (_lastEyeOpenCount != null && _lastEyeOpenCount == 1 && eyesOpenStatus == 0) {
          _blinkCount++;
          print('👁️ [BLINK] Blink detected! Count: $_blinkCount');

          if (_blinkCount == 1) {
            print('✨ [BLINK] Starting auto-capture countdown...');
            setState(() {
              _autoCountdownStarted = true;
            });
            await _performCountdownAndCapture();
          }
        }
        _lastEyeOpenCount = eyesOpenStatus;
      } catch (e) {
        print('❌ [STREAM] Frame processing error: $e');
        print('📍 [STREAM] Stack: ${StackTrace.current}');
      }
    }).then((_) {
      print('✅ [STREAM] Frame stream started successfully!');
      print('   Will process every ${_frameSkip}th frame');
    }).catchError((e) {
      print('❌ [STREAM] Failed to start stream: $e');
      print('📍 [STREAM] Stack: ${StackTrace.current}');
    });
  }

  /// Countdown 2 seconds and auto-capture
  Future<void> _performCountdownAndCapture() async {
    if (!mounted) return;

    print('⏳ [COUNTDOWN] Starting 2-second countdown...');

    for (int i = 2; i > 0; i--) {
      if (!mounted) return;

      setState(() {
        _captureCountdown = i;
        _currentStage = '📸 Capturing in $i...';
      });

      print('⏳ [COUNTDOWN] $i seconds...');
      await Future.delayed(const Duration(seconds: 1));
    }

    print('🎬 [COUNTDOWN] Countdown complete, capturing...');
    if (mounted) {
      await _performCapture();
    }
  }

  void _startCapture() async {
    print('📸 [CAPTURE] Button clicked! (Manual trigger)');

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
        await Future.delayed(const Duration(seconds: 6));
      } else if (faces.length > 1) {
        print('❌ [DETECT] Multiple faces detected: ${faces.length}');
        setState(() {
          _currentStage = '❌ Multiple Faces - Show Only 1';
        });
        await Future.delayed(const Duration(seconds: 6));
      } else {
        print('✅ [DETECT] Single face detected, proceeding to backend...');
        // Face detected - send to API
        print('🌐 [API] Calling /api/mark-attendance-auto...');
        final result = await AntiSpoofApiService.markAttendanceAuto(
          imageFile,
          instId: widget.instituteId,
        );
        print('✅ [API] Response received: $result');

        if (mounted) {
          if (result.containsKey('error')) {
            print('❌ [API] Error in response: ${result['error']}');
            setState(() {
              _currentStage = '❌ No Match Found';
            });
            await Future.delayed(const Duration(seconds: 6));
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
              await Future.delayed(const Duration(seconds: 6));
            } else {
              // ⚡ Backend already determined entry/exit (STEP 7) — no extra round trip
              var recordType = result['record_type'] ?? 'entry';

              // 🔍 Check if student already has entry today to auto-mark as exit
              try {
                final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
                final existingRecords = await appDb
                    .from('attendance')
                    .select('record_type')
                    .eq('institute_id', widget.instituteId)
                    .eq('sr_no', _srNo)
                    .eq('attendance_date', today);

                final hasEntry = existingRecords.any((r) => r['record_type'] == 'entry');
                if (hasEntry && recordType == 'entry') {
                  recordType = 'exit';
                  print('📍 [RECORD] Entry exists - switching to EXIT');
                }
              } catch (e) {
                print('⚠️ [RECORD] Could not check existing entry: $e');
              }

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

              await Future.delayed(const Duration(seconds: 6));
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
      await Future.delayed(const Duration(seconds: 6));
      _resetUI();
    }
  }

  void _resetUI() {
    if (mounted) {
      setState(() {
        _isCapturing = false;
        _autoCountdownStarted = false;
        _blinkCount = 0;
        _lastEyeOpenCount = null;
        _captureCountdown = 0;
        _matchedStudentName = '';
        _similarityScore = 0.0;
        _srNo = '';
        _matchedStudentId = '';
        _currentStage = '👀 Position your face — blink to capture';
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

      // 🔍 Check if student already has both entry and exit marked
      print('🔍 Checking if attendance already marked for today...');
      final existingRecords = await appDb
          .from('attendance')
          .select('record_type')
          .eq('institute_id', widget.instituteId)
          .eq('sr_no', srNo)
          .eq('attendance_date', today);

      final hasEntry = existingRecords.any((r) => r['record_type'] == 'entry');
      final hasExit = existingRecords.any((r) => r['record_type'] == 'exit');

      if (hasEntry && hasExit) {
        print('✅ [ALREADY MARKED] Student has both entry and exit marked');
        if (mounted) {
          setState(() {
            _currentStage = '✅ Attendance already marked for today!\n(Entry ✓ Exit ✓)';
          });
        }
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) _resetUI();
        return;
      }

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

      // 💾 STEP 2: Send to backend and WAIT for response
      print('📋 [BACKEND] Sending attendance to backend...');
      try {
        final backendResponse = await backendBatchService.queueAttendance(
          srNo: srNo,
          instituteId: widget.instituteId,
          recordType: recordType,
          markedTime: now.toUtc().toIso8601String(),
          remark: '',
          photoUrl: photoUrl,
          studentName: _matchedStudentName,
          similarityScore: _similarityScore,
        );

        // Check if successful
        if (backendResponse['success'] == true) {
          print('✅ [BACKEND] Attendance marked successfully!');
          print('   Attendance ID: ${backendResponse['attendance_id']}');
          print('   SR No: $srNo');
          print('   Student: $_matchedStudentName');
          print('   Type: $recordType');
          print('   Date: $today');
          print('   Time: ${backendResponse['marked_time']}');
          print('   Face Confidence: ${backendResponse['face_confidence']}%');
          print('   Photo URL: $photoUrl');

          // Show success to user with details
          if (mounted) {
            setState(() {
              _currentStage =
                  '✅ ${recordType.toUpperCase()} Marked Successfully!\n\n'
                  'Time: ${backendResponse['marked_time']}\n'
                  'Face: ${backendResponse['face_confidence']?.toStringAsFixed(0)}%\n'
                  'ID: ${(backendResponse['attendance_id'] as String).substring(0, 8)}';
            });
          }
          await Future.delayed(const Duration(seconds: 3));
          if (mounted) _resetUI();
        } else {
          // Backend rejected
          print('❌ [BACKEND] Attendance rejected: ${backendResponse['reason']}');

          if (mounted) {
            setState(() {
              _currentStage =
                  '❌ ${recordType.toUpperCase()} Failed\n\n'
                  'Reason: ${backendResponse['reason']}\n'
                  'Please try again\n\n'
                  'Error ID: ${backendResponse['error_id']}';
            });
          }
          await Future.delayed(const Duration(seconds: 4));
          if (mounted) _resetUI();
        }
      } catch (e) {
        print('❌ [BACKEND] Error: $e');

        if (mounted) {
          setState(() {
            _currentStage = '❌ Network Error\n\n'
                'Failed to connect to server\n'
                'Please try again\n\n'
                '$e';
          });
        }
        await Future.delayed(const Duration(seconds: 4));
        if (mounted) _resetUI();
        throw e;
      }
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

          // Top Status - Modern Design
          Positioned(
            top: 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.black.withOpacity(0.5),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                  ),
                ],
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

          // Face Quality Meter (Center-bottom)
          if (_faceDetected)
            Positioned(
              bottom: 120,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.black.withOpacity(0.5),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _faceQuality > 0.7
                        ? Colors.greenAccent
                        : _faceQuality > 0.4
                            ? Colors.yellowAccent
                            : Colors.redAccent,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '📊 Face Quality',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${(_faceQuality * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: _faceQuality > 0.7
                                ? Colors.greenAccent
                                : _faceQuality > 0.4
                                    ? Colors.yellowAccent
                                    : Colors.redAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _faceQuality,
                        minHeight: 8,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        valueColor: AlwaysStoppedAnimation(
                          _faceQuality > 0.7
                              ? Colors.greenAccent
                              : _faceQuality > 0.4
                                  ? Colors.yellowAccent
                                  : Colors.redAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _faceQuality > 0.7
                          ? '✅ Good quality - Ready to capture'
                          : _faceQuality > 0.4
                              ? '⚠️ Fair quality - Try to center face'
                              : '❌ Low quality - Improve position',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
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
                // CAPTURE Button - Modern Gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isCapturing
                          ? [Colors.orange.shade600, Colors.orange.shade800]
                          : [Colors.green.shade400, Colors.green.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: (_isCapturing ? Colors.orange : Colors.green)
                            .withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isCapturing ? null : _startCapture,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 18,
                        ),
                        child: Text(
                          _isCapturing
                              ? '🔴 CAPTURING... $_captureCountdown'
                              : '📸 CAPTURE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
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
