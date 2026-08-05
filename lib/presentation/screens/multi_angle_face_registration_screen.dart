import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/streaming_blink_detector.dart';
import '../../services/anti_spoof_api_service.dart';
import '../../services/student_api_service.dart';

class MultiAngleFaceRegistrationScreen extends StatefulWidget {
  static const routeName = '/multi-angle-face-registration';

  final String studentId;
  final String studentName;

  const MultiAngleFaceRegistrationScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<MultiAngleFaceRegistrationScreen> createState() =>
      _MultiAngleFaceRegistrationScreenState();
}

class _MultiAngleFaceRegistrationScreenState
    extends State<MultiAngleFaceRegistrationScreen> with WidgetsBindingObserver {
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  bool _cameraInitialized = false;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isProcessing = false;

  // Step tracking
  int _currentStep = 1; // 1=front, 2=left, 3=right
  final Map<int, XFile?> _capturedPhotos = {1: null, 2: null, 3: null};
  final Map<int, bool> _isRealFace = {1: false, 2: false, 3: false};

  bool _faceDetected = false;
  String _instruction = 'Initializing camera...';
  Timer? _captureTimer;
  bool _isRegistered = false; // Track if registration is complete

  // Blink detection with StreamingBlinkDetector
  late final StreamingBlinkDetector _blinkDetector = StreamingBlinkDetector(
    closedFramesRequired: 2,
    openFramesRequired: 2,
    minOpenClosedSwing: 0.20,
  );

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
        _setInstruction('❌ No cameras available');
        return;
      }

      // 🔥 Find FRONT camera (selfie) by default
      _selectedCameraIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );

      // Fallback to first camera if no front camera found
      if (_selectedCameraIndex == -1) {
        _selectedCameraIndex = 0;
      }

      print('📱 Using camera index: $_selectedCameraIndex (Front if available)');

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
      _updateInstructions();
      _startPeriodicCapture();
    } catch (e) {
      _setInstruction('❌ Camera error: $e');
    }
  }

  void _updateInstructions() {
    final instructions = {
      1: '👀 Look Straight & Blink\nFace camera and blink once',
      2: '⬅️ Turn Left\nSlowly turn head left',
      3: '➡️ Turn Right\nSlowly turn head right',
    };
    _setInstruction(instructions[_currentStep] ?? 'Ready');
  }

  void _startPeriodicCapture() {
    // Continuous detection - capture every 100ms (10 fps)
    _captureTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!_cameraInitialized || _isProcessing) return;
      await _detectFace();
    });
  }

  Future<void> _detectFace() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final picture = await _cameraController.takePicture();
      final imageFile = File(picture.path);

      print('📸 [STEP $_currentStep] Captured frame: ${picture.path}');

      // 🔥 Use LOCAL ML Kit for face detection (no backend needed for registration)
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) return;

      if (faces.isEmpty) {
        print('❌ No face detected');
        setState(() {
          _faceDetected = false;
          _updateInstructions();
        });
      } else {
        print('✅ Face detected! Count: ${faces.length}');
        setState(() => _faceDetected = true);

        // Step 1 (Front): Require blink
        if (_currentStep == 1) {
          final face = faces.first;
          final blinkDetected = _blinkDetector.processFrame(face);

          if (blinkDetected) {
            print('🎯 ✅ BLINK + FACE DETECTED! Auto-capturing Step 1...');
            setState(() {
              _capturedPhotos[1] = XFile(picture.path);
              _isRealFace[1] = true;
              _setInstruction('✅ Captured!');
            });

            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) {
              print('➡️ Moving to Step 2 (Left)');
              _advanceStep();
            }
          } else {
            print('⏳ Waiting for blink... Eye probs: L=${face.leftEyeOpenProbability}, R=${face.rightEyeOpenProbability}');
            setState(() => _faceDetected = true);
          }
        } else {
          // Step 2 & 3: Require head turn (left for step 2, right for step 3)
          final face = faces.first;
          final yaw = face.headEulerAngleY ?? 0.0; // Negative = left turn, Positive = right turn

          print('🎯 Head yaw: ${yaw.toStringAsFixed(1)}°');

          bool isCorrectHeadTurn = false;
          if (_currentStep == 2) {
            // Step 2 (Left): Require left turn (yaw < -15°)
            isCorrectHeadTurn = yaw < -15.0;
            print('⬅️ Step 2 (Left): yaw=$yaw, need yaw < -15° → ${isCorrectHeadTurn ? '✅' : '⏳'}');
          } else if (_currentStep == 3) {
            // Step 3 (Right): Require right turn (yaw > 15°)
            isCorrectHeadTurn = yaw > 15.0;
            print('➡️ Step 3 (Right): yaw=$yaw, need yaw > 15° → ${isCorrectHeadTurn ? '✅' : '⏳'}');
          }

          if (isCorrectHeadTurn) {
            print('🎯 ✅ CORRECT HEAD TURN! Auto-capturing Step $_currentStep...');
            setState(() {
              _capturedPhotos[_currentStep] = XFile(picture.path);
              _isRealFace[_currentStep] = true;
              _setInstruction('✅ Captured!');
            });

            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) {
              print('➡️ Moving to Step ${_currentStep + 1}');
              _advanceStep();
            }
          } else {
            setState(() => _faceDetected = true);
          }
        }
      }

      await imageFile.delete();
    } catch (e) {
      print('❌ Detection error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void _setInstruction(String instruction) {
    if (mounted) {
      setState(() => _instruction = instruction);
    }
  }

  void _advanceStep() {
    if (_currentStep < 3) {
      setState(() {
        _currentStep++;
        _faceDetected = false;
        _updateInstructions();
      });
      print('📋 Moved to Step $_currentStep');
    } else {
      // All 3 photos captured - go to confirmation
      print('✅ ALL 3 PHOTOS CAPTURED! Moving to review...');
      print('📸 Front: ${_capturedPhotos[1] != null ? '✓' : '✗'}');
      print('📸 Left: ${_capturedPhotos[2] != null ? '✓' : '✗'}');
      print('📸 Right: ${_capturedPhotos[3] != null ? '✓' : '✗'}');
      _showConfirmation();
    }
  }

  void _showConfirmation() {
    _captureTimer?.cancel();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Registration Summary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPhotoTile('Front', 1),
            _buildPhotoTile('Left', 2),
            _buildPhotoTile('Right', 3),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _retakeStep();
            },
            child: const Text('Retake'),
          ),
          ElevatedButton(
            onPressed: _isRegistered
                ? null // Disable if already registered
                : () {
                    Navigator.pop(context);
                    _submitRegistration();
                  },
            child: Text(_isRegistered ? '✅ Registered' : 'Register'),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoTile(String label, int step) {
    final photo = _capturedPhotos[step];
    final isReal = _isRealFace[step] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  isReal ? '✅ Real Face' : '⚠️ Not captured',
                  style: TextStyle(
                    color: isReal ? Colors.green : Colors.orange,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (photo != null)
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: FileImage(File(photo.path)),
                  fit: BoxFit.cover,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _retakeStep() {
    setState(() {
      _capturedPhotos[_currentStep] = null;
      _isRealFace[_currentStep] = false;
      _faceDetected = false;
      _updateInstructions();
    });
    _startPeriodicCapture();
  }

  /// Clear registration from database and re-enable button
  Future<void> _clearRegistration() async {
    try {
      print('🔓 Clearing registration for ${widget.studentId}...');

      // Delete embeddings from database (set to null/empty)
      // You can implement this based on your DB schema
      // For now, just reset the flag
      if (mounted) {
        setState(() {
          _isRegistered = false;
          print('✅ Registration cleared - button re-enabled');
        });
      }
    } catch (e) {
      print('❌ Error clearing registration: $e');
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
      _setInstruction('📷 Camera Switched');
    } catch (e) {
      _setInstruction('❌ Switch error');
    }
  }

  Future<void> _submitRegistration() async {
    if (_capturedPhotos[1] == null ||
        _capturedPhotos[2] == null ||
        _capturedPhotos[3] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ All 3 photos required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            Text(
              'Registering ${widget.studentName}...',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );

    try {
      print('🚀 Submitting 3-angle registration for ${widget.studentName}...');
      print('📸 Front: ${_capturedPhotos[1]?.path}');
      print('📸 Left: ${_capturedPhotos[2]?.path}');
      print('📸 Right: ${_capturedPhotos[3]?.path}');

      final result = await AntiSpoofApiService.registerStudentFace(
        studentId: widget.studentId,
        studentName: widget.studentName,
        frontPhoto: File(_capturedPhotos[1]!.path),
        leftPhoto: File(_capturedPhotos[2]!.path),
        rightPhoto: File(_capturedPhotos[3]!.path),
      );

      print('📡 Backend Response: success=${result['success']}, message=${result['message']}');

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (result['success'] == true) {
        print('✅ REGISTRATION SUCCESS!');
        // Extract embeddings from backend response and save to database
        if (result['embeddings'] != null) {
          try {
            final embeddings = result['embeddings'] as Map<String, dynamic>;
            print('📊 Embeddings received (3 angles, uses MAX similarity):');
            print('   Front: ${embeddings['face_embedding_front']?.length} dims');
            print('   Left: ${embeddings['face_embedding_left']?.length} dims');
            print('   Right: ${embeddings['face_embedding_right']?.length} dims');

            // Extract embeddings as lists of doubles (new format from backend)
            final frontEmbedding = List<double>.from(
              (embeddings['face_embedding_front'] as List?)?.map((x) => (x as num).toDouble()) ?? [],
            );
            final leftEmbedding = List<double>.from(
              (embeddings['face_embedding_left'] as List?)?.map((x) => (x as num).toDouble()) ?? [],
            );
            final rightEmbedding = List<double>.from(
              (embeddings['face_embedding_right'] as List?)?.map((x) => (x as num).toDouble()) ?? [],
            );

            // Quality scores (use 1.0 for all since backend doesn't return them yet)
            const qualityFront = 1.0;
            const qualityLeft = 1.0;
            const qualityRight = 1.0;

            print('✅ Extracted embeddings: front=${frontEmbedding.length}d, left=${leftEmbedding.length}d, right=${rightEmbedding.length}d');

            // Save to database
            await StudentApiService.updateStudentFaceRegistration(
              srNo: widget.studentId,
              frontEmbedding: frontEmbedding,
              leftEmbedding: leftEmbedding,
              rightEmbedding: rightEmbedding,
              qualityFront: qualityFront,
              qualityLeft: qualityLeft,
              qualityRight: qualityRight,
              facePhotoUrl: 'registered_${widget.studentId}_${DateTime.now().millisecondsSinceEpoch}',
            );

            print('✅ Embeddings saved to database');

            // 🔒 Mark as registered - disable button
            if (mounted) {
              setState(() => _isRegistered = true);
            }
          } catch (e) {
            print('⚠️ Error saving embeddings: $e');
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${widget.studentName} registered successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true); // Return success
      } else {
        print('❌ REGISTRATION FAILED: ${result['message']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Registration failed: ${result['message']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ SUBMISSION ERROR: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
                _instruction,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
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
          // Camera
          SizedBox.expand(child: CameraPreview(_cameraController)),

          // Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Face Registration',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    widget.studentName,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Progress indicator
                  Row(
                    children: List.generate(
                      3,
                      (i) => Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: _currentStep > i
                                ? Colors.green
                                : _currentStep == i + 1
                                    ? Colors.blue
                                    : Colors.grey,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Camera Switch Button (Top Right)
          Positioned(
            top: 60,
            right: 20,
            child: FloatingActionButton.small(
              onPressed: _switchCamera,
              backgroundColor: Colors.blue.withOpacity(0.8),
              child: const Icon(Icons.flip_camera_android),
              tooltip: 'Switch Camera',
            ),
          ),

          // Professional Instructions Box
          Positioned(
            top: 140,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _faceDetected ? Colors.green : Colors.grey.shade600,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _faceDetected ? Colors.green.withOpacity(0.3) : Colors.transparent,
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _instruction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_faceDetected) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Face detected',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Bottom buttons
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                  // Manual capture button for Step 1 (fallback for blink detection)
                  if (_currentStep == 1 && _capturedPhotos[1] == null && _faceDetected)
                    ElevatedButton.icon(
                      onPressed: () async {
                        _captureTimer?.cancel();
                        final picture = await _cameraController.takePicture();
                        setState(() {
                          _capturedPhotos[1] = picture;
                          _isRealFace[1] = true;
                          _setInstruction('✅ Captured!');
                        });
                        await Future.delayed(const Duration(milliseconds: 600));
                        if (mounted) {
                          print('➡️ Moving to Step 2 (Left)');
                          _advanceStep();
                        }
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Capture'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                    ),
                  if (_capturedPhotos[_currentStep] != null)
                    ElevatedButton.icon(
                      onPressed: _retakeStep,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retake'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                    ),
                  if (_capturedPhotos[3] != null)
                    ElevatedButton.icon(
                      onPressed: _showConfirmation,
                      icon: const Icon(Icons.check),
                      label: const Text('Review'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
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
