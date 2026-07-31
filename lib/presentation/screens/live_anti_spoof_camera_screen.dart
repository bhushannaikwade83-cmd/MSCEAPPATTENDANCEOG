import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../services/anti_spoof_api_service.dart';

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

  // Face Detection
  int _detectedFaces = 0;
  Rect? _faceBoundingBox;
  bool _faceDetected = false;

  // UI State
  int _fps = 0;
  DateTime _lastFrameTime = DateTime.now();
  int _frameCount = 0;
  String _currentStage = 'Initializing...';
  bool _isCapturing = false;
  int _captureCountdown = 0;
  Timer? _countdownTimer;

  // Recognition
  String _matchedStudentName = '';
  double _similarityScore = 0.0;
  String _srNo = '';
  String _attendanceType = ''; // entry or exit

  // Detection Locking
  bool _isProcessingFrame = false;
  int _frameSkipCounter = 0;
  int _consecutiveFaceFrames = 0; // Track stable face detection
  int _framesSinceLastDetection = 0; // Reset if no detection for X frames
  static const int FRAME_SKIP = 4; // Process every 5th frame (much faster)
  static const int FACE_STABILITY_FRAMES = 2; // Need 2 consecutive detections
  static const int FACE_TIMEOUT_FRAMES = 20; // Disable if no detection for 20 frames

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
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

      final frontCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras[0],
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController.initialize();

      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: false,
          enableClassification: false,
          enableTracking: true,
        ),
      );

      setState(() {
        _cameraInitialized = true;
      });

      _setStatus('🎥 Ready - Press CAPTURE');
      _cameraController.startImageStream(_processImageStream);
    } catch (e) {
      _setStatus('❌ Error: $e');
    }
  }

  Future<void> _processImageStream(CameraImage cameraImage) async {
    if (_isProcessingFrame || _isCapturing) return;

    // Skip frames for faster detection
    _frameSkipCounter++;
    if (_frameSkipCounter % FRAME_SKIP != 0) {
      _updateFPS();
      return;
    }

    _isProcessingFrame = true;

    try {
      _updateFPS();

      // Use lower resolution for faster detection (480p instead of full resolution)
      final inputImage = InputImage.fromBytes(
        bytes: cameraImage.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          ),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: cameraImage.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      if (mounted && !_isCapturing) {
        setState(() {
          _detectedFaces = faces.length;
          _framesSinceLastDetection++;

          if (faces.isEmpty) {
            _consecutiveFaceFrames = 0;
            _currentStage = 'No Face Detected';
            // Disable button only after X frames of no detection
            if (_framesSinceLastDetection > FACE_TIMEOUT_FRAMES) {
              _faceDetected = false;
              _faceBoundingBox = null;
            }
          } else if (faces.length > 1) {
            _consecutiveFaceFrames = 0;
            _faceDetected = false;
            _faceBoundingBox = null;
            _currentStage = 'Multiple Faces - Show Only 1';
          } else {
            final face = faces.first;
            _faceBoundingBox = face.boundingBox;
            _framesSinceLastDetection = 0; // Reset timeout
            _consecutiveFaceFrames++;

            // Enable button only after consistent detection
            if (_consecutiveFaceFrames >= FACE_STABILITY_FRAMES) {
              _faceDetected = true;
              _currentStage = 'Face Detected ✓ - Press CAPTURE';
            } else {
              _currentStage = 'Stabilizing... ${_consecutiveFaceFrames}/$FACE_STABILITY_FRAMES';
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _startCapture() {
    if (!_faceDetected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Face not detected')),
      );
      return;
    }

    setState(() {
      _isCapturing = true;
      _captureCountdown = 2;
      _currentStage = 'Capturing in ${_captureCountdown}...';
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _captureCountdown--;
          _currentStage = _captureCountdown > 0
              ? 'Capturing in ${_captureCountdown}...'
              : 'Capturing...';
        });

        if (_captureCountdown <= 0) {
          timer.cancel();
          _performCapture();
        }
      }
    });
  }

  Future<void> _performCapture() async {
    try {
      final picture = await _cameraController.takePicture();
      final imageFile = File(picture.path);

      setState(() {
        _currentStage = 'Matching Face...';
      });

      final result = await AntiSpoofApiService.markAttendanceAuto(imageFile);

      if (mounted) {
        if (result.containsKey('error')) {
          setState(() {
            _currentStage = '❌ No Match Found';
          });
          await Future.delayed(const Duration(seconds: 2));
        } else {
          _matchedStudentName = result['student_name'] ?? 'Unknown';
          _similarityScore = result['similarity'] ?? 0.0;
          _srNo = result['sr_no'] ?? 'N/A';
          _attendanceType = result['record_type'] ?? 'entry';

          setState(() {
            _currentStage = '✅ ${_attendanceType.toUpperCase()} Marked';
          });

          await Future.delayed(const Duration(seconds: 2));
        }
      }

      await imageFile.delete();
      _resetUI();
    } catch (e) {
      debugPrint('Capture error: $e');
      setState(() {
        _currentStage = '❌ Capture Error';
      });
      await Future.delayed(const Duration(seconds: 2));
      _resetUI();
    }
  }

  void _resetUI() {
    if (mounted) {
      setState(() {
        _isCapturing = false;
        _detectedFaces = 0;
        _faceBoundingBox = null;
        _faceDetected = false;
        _matchedStudentName = '';
        _similarityScore = 0.0;
        _srNo = '';
        _currentStage = 'Ready for Next Student';
      });
    }
  }

  void _updateFPS() {
    _frameCount++;
    final now = DateTime.now();
    final diff = now.difference(_lastFrameTime);

    if (diff.inMilliseconds >= 1000) {
      setState(() {
        _fps = _frameCount;
        _frameCount = 0;
        _lastFrameTime = now;
      });
    }
  }

  void _setStatus(String status) {
    if (mounted) {
      setState(() => _currentStage = status);
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

          // Face Bounding Box
          if (_faceBoundingBox != null)
            Positioned(
              left: _faceBoundingBox!.left,
              top: _faceBoundingBox!.top,
              width: _faceBoundingBox!.width,
              height: _faceBoundingBox!.height,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _faceDetected ? Colors.green : Colors.red,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

          // Top Status Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentStage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Faces: $_detectedFaces | FPS: $_fps',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    DateTime.now().toString().split('.')[0],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Student Details Card (on success)
          if (_matchedStudentName.isNotEmpty)
            Positioned(
              top: screenSize.height * 0.15,
              left: screenSize.width * 0.05,
              right: screenSize.width * 0.05,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Student: $_matchedStudentName',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'SR No: $_srNo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Match: ${(_similarityScore * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Type: ${_attendanceType.toUpperCase()}',
                      style: TextStyle(
                        color: _attendanceType == 'entry'
                            ? Colors.blueAccent
                            : Colors.orangeAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Control Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // CAPTURE Button (real-time enable/disable based on face)
                  ElevatedButton(
                    onPressed: (_isCapturing || !_faceDetected) ? null : _startCapture,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isCapturing
                          ? Colors.orange
                          : (_faceDetected ? Colors.green : Colors.red.withOpacity(0.6)),
                      disabledBackgroundColor: _isCapturing
                          ? Colors.orange
                          : Colors.red.withOpacity(0.6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _isCapturing
                          ? 'CAPTURING... $_captureCountdown'
                          : (_faceDetected ? '✅ CAPTURE' : '❌ NO FACE'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Close Button
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
          ),
        ],
      ),
    );
  }
}
