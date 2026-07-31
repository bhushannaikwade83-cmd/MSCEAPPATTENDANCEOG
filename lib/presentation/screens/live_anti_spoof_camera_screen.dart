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

      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _status = 'No face detected';
            _faceDetected = false;
            _canCapture = false;
          });
        }
      } else {
        setState(() => _faceDetected = true);

        final result = await AntiSpoofApiService.detectFace(imageFile);

        if (!mounted) return;

        if (result.containsKey('error')) {
          setState(() {
            _status = 'API Error';
            _canCapture = false;
          });
        } else {
          final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;

          // Collect frame scores for 3 seconds
          _frameCollectionStartTime ??= DateTime.now();
          _frameScores.add(confidence);

          final elapsed = DateTime.now().difference(_frameCollectionStartTime!);
          final isCollectionComplete = elapsed.inSeconds >= 3;

          if (isCollectionComplete && _frameScores.isNotEmpty) {
            // Calculate average score over 3 seconds
            final avgScore = _frameScores.reduce((a, b) => a + b) / _frameScores.length;
            final avgScorePercent = avgScore * 100;

            // Threshold: 0-15% = REAL, 15%+ = SPOOF
            final isReal = avgScorePercent <= 15.0;

            if (isReal) {
              print('═════════════════════════════════════════════');
              print('✅ LIVE FACE DETECTED (3-second average)');
              print('   Frames analyzed: ${_frameScores.length}');
              print('   Avg Spoof Score: ${avgScorePercent.toStringAsFixed(1)}%');
              print('   Status: Face Verified ✓');
              print('═════════════════════════════════════════════');

              setState(() {
                _isRealFace = true;
                _confidence = avgScore;
                _score = avgScore;
                _status = 'Face Verified ✓';
                _realCount++;
                _canCapture = true;
              });
            } else {
              print('═════════════════════════════════════════════');
              print('❌ SPOOF DETECTED (3-second average)');
              print('   Frames analyzed: ${_frameScores.length}');
              print('   Avg Spoof Score: ${avgScorePercent.toStringAsFixed(1)}%');
              print('   Status: Fake photo/video/screen detected');
              print('═════════════════════════════════════════════');

              setState(() {
                _isRealFace = false;
                _confidence = avgScore;
                _score = avgScore;
                _status = 'Spoof Detected';
                _spoofCount++;
                _canCapture = false;
              });
            }

            // Reset for next collection
            _frameScores.clear();
            _frameCollectionStartTime = null;
          } else if (_frameScores.length == 1) {
            // Show collecting status on first frame
            setState(() {
              _status = 'Collecting frames... ${elapsed.inSeconds}s';
            });
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
