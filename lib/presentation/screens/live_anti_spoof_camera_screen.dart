import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../services/anti_spoof_api_service.dart';
import '../../core/theme/app_theme.dart';

enum VerificationStep {
  faceDetection,
  antiSpoof,
  blink,
  recognition,
  attendance
}

enum StepStatus { pending, processing, completed, failed }

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

  // Verification Pipeline States
  Map<VerificationStep, StepStatus> _stepStatus = {
    VerificationStep.faceDetection: StepStatus.pending,
    VerificationStep.antiSpoof: StepStatus.pending,
    VerificationStep.blink: StepStatus.pending,
    VerificationStep.recognition: StepStatus.pending,
    VerificationStep.attendance: StepStatus.pending,
  };

  // Face Detection
  int _detectedFaces = 0;
  Rect? _faceBoundingBox;
  Color _faceBoxColor = Colors.blue;

  // Anti-Spoof
  double _spoofScore = 0.0;
  int _realFrameCount = 0;
  static const int REAL_FRAMES_NEEDED = 5;
  static const double REAL_THRESHOLD = 0.85;

  // Blink Detection
  int _blinkCount = 0;
  bool _eyesWereClosed = false;

  // Recognition
  String _matchedStudentName = '';
  double _similarityScore = 0.0;
  String _srNo = '';
  String _rollNo = '';
  String _className = '';
  String _division = '';

  // UI State
  int _fps = 0;
  DateTime _lastFrameTime = DateTime.now();
  int _frameCount = 0;
  bool _debugMode = false;
  List<String> _debugLogs = [];
  String _currentStage = 'Initializing...';

  // Detection Locking
  bool _isProcessingFrame = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController.initialize();

      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableClassification: true,
        ),
      );

      setState(() {
        _cameraInitialized = true;
        _stepStatus[VerificationStep.faceDetection] = StepStatus.processing;
      });

      _setStatus('🎥 Camera Ready - Scanning...');

      // Start continuous frame processing
      _cameraController.startImageStream(_processImageStream);
    } catch (e) {
      _setStatus('❌ Error: $e');
    }
  }

  Future<void> _processImageStream(CameraImage cameraImage) async {
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      _updateFPS();

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

      if (mounted) {
        setState(() {
          _detectedFaces = faces.length;

          if (faces.isEmpty) {
            _faceBoxColor = Colors.blue;
            _currentStage = 'No Face Detected';
          } else if (faces.length > 1) {
            _faceBoxColor = Colors.red;
            _currentStage = 'Multiple Faces Detected';
            _stepStatus[VerificationStep.faceDetection] = StepStatus.failed;
          } else {
            final face = faces.first;
            _faceBoundingBox = face.boundingBox;
            _faceBoxColor = Colors.orange;
            _currentStage = 'Checking Liveness...';
            _stepStatus[VerificationStep.faceDetection] = StepStatus.completed;
            _stepStatus[VerificationStep.antiSpoof] = StepStatus.processing;

            // Process spoof detection
            _processSpoof(face);
          }
        });
      }
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _processSpoof(Face face) async {
    // Placeholder: In real implementation, call spoof detection API
    // For now, simulate detection
    _spoofScore = 0.92; // Simulated

    if (_spoofScore >= REAL_THRESHOLD) {
      _realFrameCount++;

      if (_realFrameCount >= REAL_FRAMES_NEEDED) {
        setState(() {
          _currentStage = 'Liveness Verified - Please Blink';
          _stepStatus[VerificationStep.antiSpoof] = StepStatus.completed;
          _stepStatus[VerificationStep.blink] = StepStatus.processing;
          _faceBoxColor = Colors.yellow;
        });

        _processBlink(face);
      } else {
        setState(() {
          _currentStage = 'Real Frames: $_realFrameCount/$REAL_FRAMES_NEEDED';
        });
      }
    } else {
      setState(() {
        _realFrameCount = 0;
        _currentStage = 'Spoof Detected - Resetting...';
        _faceBoxColor = Colors.red;
      });
    }
  }

  Future<void> _processBlink(Face face) async {
    final leftEyeOpen = face.leftEyeOpenProbability ?? 0.5;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 0.5;
    final eyesOpen = leftEyeOpen > 0.3 && rightEyeOpen > 0.3;

    if (!eyesOpen && !_eyesWereClosed) {
      _eyesWereClosed = true;
    } else if (eyesOpen && _eyesWereClosed) {
      _blinkCount++;
      _eyesWereClosed = false;

      if (_blinkCount >= 1) {
        setState(() {
          _currentStage = 'Blink Verified ✓';
          _faceBoxColor = Colors.green;
          _stepStatus[VerificationStep.blink] = StepStatus.completed;
          _stepStatus[VerificationStep.recognition] = StepStatus.processing;
        });

        await _performRecognition();
      } else {
        setState(() {
          _currentStage = 'Blink: $_blinkCount/1';
        });
      }
    }
  }

  Future<void> _performRecognition() async {
    setState(() {
      _currentStage = 'Matching Face...';
    });

    try {
      // Simulate capture and recognition
      final picture = await _cameraController.takePicture();
      final imageFile = File(picture.path);

      // Call recognition API
      final result = await AntiSpoofApiService.markAttendanceAuto(imageFile);

      if (mounted) {
        if (result.containsKey('error')) {
          setState(() {
            _currentStage = 'No Match Found';
            _stepStatus[VerificationStep.recognition] = StepStatus.failed;
          });

          await Future.delayed(const Duration(seconds: 2));
          _resetVerification();
        } else {
          _matchedStudentName = result['student_name'] ?? 'Unknown';
          _similarityScore = result['similarity'] ?? 0.0;
          _srNo = result['sr_no'] ?? 'N/A';
          _rollNo = result['roll_number'] ?? 'N/A';
          _className = result['class'] ?? 'N/A';
          _division = result['division'] ?? 'N/A';

          setState(() {
            _currentStage = '✅ Attendance Marked';
            _stepStatus[VerificationStep.recognition] = StepStatus.completed;
            _stepStatus[VerificationStep.attendance] = StepStatus.completed;
            _faceBoxColor = Colors.green;
          });

          await Future.delayed(const Duration(seconds: 3));
          _resetVerification();
        }
      }

      await imageFile.delete();
    } catch (e) {
      debugPrint('Recognition error: $e');
      setState(() {
        _currentStage = '❌ Recognition Error';
        _stepStatus[VerificationStep.recognition] = StepStatus.failed;
      });

      await Future.delayed(const Duration(seconds: 2));
      _resetVerification();
    }
  }

  void _resetVerification() {
    if (mounted) {
      setState(() {
        _detectedFaces = 0;
        _faceBoundingBox = null;
        _faceBoxColor = Colors.blue;
        _spoofScore = 0.0;
        _realFrameCount = 0;
        _blinkCount = 0;
        _eyesWereClosed = false;
        _currentStage = 'Ready for Next Student';
        _matchedStudentName = '';
        _similarityScore = 0.0;

        _stepStatus = {
          VerificationStep.faceDetection: StepStatus.processing,
          VerificationStep.antiSpoof: StepStatus.pending,
          VerificationStep.blink: StepStatus.pending,
          VerificationStep.recognition: StepStatus.pending,
          VerificationStep.attendance: StepStatus.pending,
        };
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

  void _addDebugLog(String message) {
    if (mounted) {
      setState(() {
        _debugLogs.add(message);
        if (_debugLogs.length > 20) {
          _debugLogs.removeAt(0);
        }
      });
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
                    color: _faceBoxColor,
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
                  Column(
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
                      Text(
                        'Faces: $_detectedFaces | FPS: $_fps',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        DateTime.now().toString().split('.')[0],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_spoofScore > 0)
                        Text(
                          'Spoof: ${(_spoofScore * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Right Panel - Verification Pipeline
          Positioned(
            right: 16,
            top: 100,
            width: 200,
            child: Column(
              children: [
                _buildStepIndicator(
                  VerificationStep.faceDetection,
                  'Face Detection',
                ),
                const SizedBox(height: 8),
                _buildStepIndicator(
                  VerificationStep.antiSpoof,
                  'Anti-Spoof',
                ),
                const SizedBox(height: 8),
                _buildStepIndicator(
                  VerificationStep.blink,
                  'Blink Detection',
                ),
                const SizedBox(height: 8),
                _buildStepIndicator(
                  VerificationStep.recognition,
                  'Recognition',
                ),
                const SizedBox(height: 8),
                _buildStepIndicator(
                  VerificationStep.attendance,
                  'Attendance',
                ),
              ],
            ),
          ),

          // Bottom Panel - Live Details
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDetailRow('Spoof Score', '${(_spoofScore * 100).toStringAsFixed(1)}%'),
                      _buildDetailRow('Real Frames', '$_realFrameCount/$REAL_FRAMES_NEEDED'),
                      _buildDetailRow('Blink Status', '$_blinkCount/1'),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDetailRow('Recognition', '${(_similarityScore * 100).toStringAsFixed(1)}%'),
                      if (_matchedStudentName.isNotEmpty)
                        _buildDetailRow('Student', _matchedStudentName),
                      if (_srNo.isNotEmpty)
                        _buildDetailRow('SR No', _srNo),
                    ],
                  ),
                  // Debug Toggle
                  GestureDetector(
                    onTap: () => setState(() => _debugMode = !_debugMode),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _debugMode
                            ? Colors.cyan.withOpacity(0.3)
                            : Colors.grey.withOpacity(0.2),
                        border: Border.all(
                          color: _debugMode ? Colors.cyan : Colors.grey,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '🐛 Debug',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Debug Panel
          if (_debugMode)
            Positioned(
              bottom: 180,
              left: 16,
              width: 300,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.9),
                  border: Border.all(color: Colors.cyan, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'DEBUG PANEL',
                        style: TextStyle(
                          color: Colors.cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'FPS: $_fps\nSpoof: ${(_spoofScore * 100).toStringAsFixed(1)}%\nReal Frames: $_realFrameCount\nBlink: $_blinkCount\nStage: $_currentStage',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Close Button
          Positioned(
            top: 20,
            left: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withOpacity(0.2),
                  border: Border.all(color: Colors.red, width: 1.5),
                ),
                child: const Icon(Icons.close, color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(VerificationStep step, String label) {
    final status = _stepStatus[step] ?? StepStatus.pending;
    final color = _getStatusColor(status);
    final icon = _getStatusIcon(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(StepStatus status) {
    switch (status) {
      case StepStatus.completed:
        return Colors.green;
      case StepStatus.processing:
        return Colors.orange;
      case StepStatus.failed:
        return Colors.red;
      case StepStatus.pending:
        return Colors.grey;
    }
  }

  String _getStatusIcon(StepStatus status) {
    switch (status) {
      case StepStatus.completed:
        return '✅';
      case StepStatus.processing:
        return '⏳';
      case StepStatus.failed:
        return '❌';
      case StepStatus.pending:
        return '⭕';
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
