import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../services/anti_spoof_api_service.dart';
import '../../services/student_api_service.dart';
import '../../core/theme/app_theme.dart';

class LiveAntiSpoofCameraScreen extends StatefulWidget {
  static const routeName = '/live-anti-spoof-camera';

  final String? studentName;
  final String? studentId;
  final bool isRegistration;

  const LiveAntiSpoofCameraScreen({
    super.key,
    this.studentName,
    this.studentId,
    this.isRegistration = false,
  });

  @override
  State<LiveAntiSpoofCameraScreen> createState() =>
      _LiveAntiSpoofCameraScreenState();
}

class _LiveAntiSpoofCameraScreenState extends State<LiveAntiSpoofCameraScreen>
    with WidgetsBindingObserver {
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  bool _cameraInitialized = false;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isProcessing = false;

  bool _isRealFace = false;
  double _confidence = 0.0;
  double _score = 0.0;
  String _status = 'Initializing...';

  int _realCount = 0;
  int _spoofCount = 0;
  Timer? _captureTimer;
  bool _canCapture = false;
  bool _faceDetected = false;

  // 3-second frame collection
  List<double> _frameScores = [];
  DateTime? _frameCollectionStartTime;

  // Blink detection for liveness
  int _blinkCount = 0;
  bool _eyesWereClosed = false;
  bool _blinkDetected = false;
  DateTime? _blinkDetectionStartTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureTimer?.cancel();
    _cameraController.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _setStatus('❌ No cameras found');
        return;
      }

      _cameraController = CameraController(
        _cameras[_selectedCameraIndex],
        ResolutionPreset.high,
      );

      await _cameraController.initialize();

      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableClassification: true,
        ),
      );

      setState(() => _cameraInitialized = true);
      _setStatus('Ready');

      _startPeriodicCapture();
    } catch (e) {
      _setStatus('❌ Error: $e');
    }
  }

  void _startPeriodicCapture() {
    _captureTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!_cameraInitialized || _isProcessing) return;
      await _captureAndAnalyzeFrame();
    });
  }

  Future<void> _captureAndAnalyzeFrame() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final picture = await _cameraController.takePicture();
      final imageFile = File(picture.path);

      final inputImage = InputImage.fromFilePath(picture.path);
      final faces = await _faceDetector.processImage(inputImage);
      print('🟢 [FRAME] Captured and analyzed. Faces found: ${faces.length}');

      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _status = 'No face detected';
            _faceDetected = false;
            _canCapture = false;
          });
        }
      } else {
        print('🔵 [FACE DETECTED] Found ${faces.length} face(s)');
        setState(() => _faceDetected = true);

        // Check for blink if waiting for liveness confirmation
        if (_isRealFace && _blinkDetectionStartTime != null && !_blinkDetected) {
          final face = faces.first;
          final eyesOpen = _checkIfEyesOpen(face);

          if (!eyesOpen && !_eyesWereClosed) {
            _eyesWereClosed = true;
            print('👁️ [BLINK] Eyes closed');
          } else if (eyesOpen && _eyesWereClosed) {
            _blinkCount++;
            _eyesWereClosed = false;
            print('👁️ [BLINK] Blink #$_blinkCount');

            if (_blinkCount >= 1) {
              _blinkDetected = true;
              print('═════════════════════════════════════════════');
              print('✅ BLINK DETECTED - LIVENESS CONFIRMED');
              print('═════════════════════════════════════════════');
              setState(() => _status = '✓ Blink confirmed - Processing...');
              await Future.delayed(const Duration(milliseconds: 800));
              if (!widget.isRegistration && mounted) {
                print('🚀 STARTING FACE MATCHING & ATTENDANCE');
                await _autoMarkAttendance();
              }
            }
          }

          if (!_blinkDetected) {
            setState(() => _status = 'Waiting for blink... $_blinkCount/1');
          }
        } else if (!_isRealFace) {
          // Call spoof detection API
          final result = await AntiSpoofApiService.detectFace(imageFile);
          print('🔵 [API RESPONSE] Got result: $result');

          if (!mounted) return;

          if (result.containsKey('error')) {
            print('❌ [API ERROR] ${result['error']}');
            setState(() {
              _status = 'API Error: ${result['error']}';
              _canCapture = false;
            });
          } else {
            final isRealFromBackend = result['is_real'] as bool? ?? false;
            final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
            final spoofPercent = confidence * 100;

            // REAL-TIME DECISION (no averaging)
            final isReal = isRealFromBackend;

            if (isReal) {
              print('═════════════════════════════════════════════');
              print('✅ LIVE FACE DETECTED');
              print('   Spoof Score: ${spoofPercent.toStringAsFixed(1)}%');
              print('   Status: Face Verified ✓');
              print('🔍 NOW WAITING FOR BLINK FOR LIVENESS...');
              print('═════════════════════════════════════════════');

              setState(() {
                _isRealFace = true;
                _confidence = confidence;
                _score = confidence;
                _status = 'Waiting for blink... 0/1';
                _realCount++;
                _canCapture = false;
                _blinkDetectionStartTime = DateTime.now();
              });
            } else {
              print('═════════════════════════════════════════════');
              print('❌ SPOOF DETECTED');
              print('   Spoof Score: ${spoofPercent.toStringAsFixed(1)}%');
              print('   Status: Fake photo/video/screen detected');
              print('═════════════════════════════════════════════');

              setState(() {
                _isRealFace = false;
                _confidence = confidence;
                _score = confidence;
                _status = 'Spoof Detected - ${spoofPercent.toStringAsFixed(1)}%';
                _spoofCount++;
                _canCapture = false;
              });
            }
          }
        }
      }

      await imageFile.delete();
    } catch (e) {
      debugPrint('Frame error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  bool _checkIfEyesOpen(Face face) {
    // Check if left and right eyes are open based on landmarks
    // ML Kit Face Detection provides eye open probabilities (0-1 confidence)
    final leftEyeOpen = face.leftEyeOpenProbability ?? 0.5;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 0.5;

    // Eyes are considered open if both have > 0.3 probability
    return leftEyeOpen > 0.3 && rightEyeOpen > 0.3;
  }

  void _setStatus(String status) {
    if (mounted) {
      setState(() => _status = status);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;

    await _cameraController.dispose();
    _cameraController = CameraController(
      _cameras[_selectedCameraIndex],
      ResolutionPreset.high,
    );

    try {
      await _cameraController.initialize();
      setState(() {});
      _setStatus('Camera Switched');
    } catch (e) {
      _setStatus('Switch error');
    }
  }

  Future<void> _capturePhoto() async {
    if (!_canCapture || !_isRealFace) return;

    try {
      _captureTimer?.cancel();
      final image = await _cameraController.takePicture();
      if (!mounted) return;
      Navigator.pop(context, image);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _autoMarkAttendance() async {
    try {
      print('═════════════════════════════════════════════');
      print('📸 CAPTURING PHOTO FOR MATCHING');
      print('═════════════════════════════════════════════');

      _captureTimer?.cancel();
      final image = await _cameraController.takePicture();
      final imageFile = File(image.path);

      if (!mounted) return;

      // Step 1: Match face against database
      print('═════════════════════════════════════════════');
      print('🔍 MATCHING FACE AGAINST DATABASE');
      print('═════════════════════════════════════════════');

      setState(() {
        _status = '🔍 Matching face...';
      });

      final matchResult = await AntiSpoofApiService.markAttendanceAuto(imageFile);

      if (!mounted) return;

      if (matchResult.containsKey('error')) {
        print('═════════════════════════════════════════════');
        print('❌ MATCHING FAILED');
        print('   Error: ${matchResult['error']}');
        print('═════════════════════════════════════════════');

        setState(() {
          _status = '❌ No match found\nExiting...';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
        return;
      }

      // Step 2: Show matched student
      final matchedName = matchResult['student_name'] ?? 'Unknown';
      final similarity = matchResult['similarity'] ?? 0.0;
      final srNo = matchResult['sr_no'] ?? 'N/A';

      print('═════════════════════════════════════════════');
      print('✅ MATCH SUCCESSFUL');
      print('   Student: $matchedName');
      print('   SR No: $srNo');
      print('   Similarity: ${(similarity * 100).toStringAsFixed(1)}%');
      print('═════════════════════════════════════════════');

      setState(() {
        _status = '✅ Matched!\n$matchedName\n${(similarity * 100).toStringAsFixed(1)}% match';
      });

      print('═════════════════════════════════════════════');
      print('✅ ATTENDANCE MARKED');
      print('   Status: SUCCESS');
      print('   Exiting in 3 seconds...');
      print('═════════════════════════════════════════════');

      // Wait 3 seconds then return
      await Future.delayed(const Duration(seconds: 3));

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('═════════════════════════════════════════════');
      print('❌ PROCESSING ERROR');
      print('   Error: $e');
      print('═════════════════════════════════════════════');

      setState(() {
        _status = '❌ Error\n$e\nExiting...';
      });

      await Future.delayed(const Duration(seconds: 3));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              Text(
                _status,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Feed
          SizedBox.expand(child: CameraPreview(_cameraController)),

          // Top Header - Professional
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // LIVE SPOOF SCORE - BIG NUMBER
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      border: Border.all(
                        color: _faceDetected
                            ? (_isRealFace ? Colors.green : Colors.red)
                            : Colors.grey,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'SPOOF SCORE',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(_confidence * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: _isRealFace ? Colors.greenAccent : Colors.redAccent,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Face Verification',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (widget.studentName != null)
                            Text(
                              widget.studentName!,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                      // Status Indicator
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _faceDetected
                              ? Colors.green.withOpacity(0.2)
                              : Colors.grey.withOpacity(0.2),
                          border: Border.all(
                            color: _faceDetected ? Colors.green : Colors.grey,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _faceDetected
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _faceDetected ? 'Scanning' : 'Ready',
                              style: TextStyle(
                                color: _faceDetected
                                    ? Colors.green
                                    : Colors.grey,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Spoof Status Box (Green/Red indicator)
                  if (_faceDetected && _isRealFace != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _isRealFace
                            ? Colors.green.withOpacity(0.15)
                            : Colors.red.withOpacity(0.15),
                        border: Border.all(
                          color: _isRealFace ? Colors.green : Colors.red,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: (_isRealFace ? Colors.green : Colors.red)
                                .withOpacity(0.2),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isRealFace ? Colors.green : Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    _isRealFace
                                        ? '✓ Real Face (Live)'
                                        : '✗ Spoof Detected',
                                    style: TextStyle(
                                      color: _isRealFace
                                          ? Colors.greenAccent
                                          : Colors.redAccent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(_confidence * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: _isRealFace
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        border: Border.all(
                          color: Colors.blue.withOpacity(0.5),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _status,
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom Controls - Professional
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.9),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Capture Instructions
                  if (_canCapture)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Press the button to capture',
                        style: TextStyle(
                          color: Colors.green.withOpacity(0.8),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Switch Camera
                      if (_cameras.length > 1)
                        GestureDetector(
                          onTap: _switchCamera,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.1),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.flip_camera_android,
                              color: Colors.white.withOpacity(0.7),
                              size: 24,
                            ),
                          ),
                        ),

                      const SizedBox(width: 24),

                      // Capture Button
                      GestureDetector(
                        onTap: _canCapture ? _capturePhoto : null,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _canCapture
                                ? LinearGradient(
                                    colors: [
                                      Colors.green.shade400,
                                      Colors.green.shade600,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : LinearGradient(
                                    colors: [
                                      Colors.grey.shade700,
                                      Colors.grey.shade800,
                                    ],
                                  ),
                            boxShadow: _canCapture
                                ? [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.5),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    )
                                  ]
                                : [],
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),

                      const SizedBox(width: 24),

                      // Close Button
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withOpacity(0.1),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.close,
                            color: Colors.red.withOpacity(0.7),
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
