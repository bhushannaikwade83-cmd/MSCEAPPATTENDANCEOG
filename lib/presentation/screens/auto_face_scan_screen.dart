import 'dart:async' show unawaited;
import 'dart:convert' show jsonDecode;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';

import '../../core/app_db.dart';
import '../../core/camera_stream_frame_gate.dart';
import '../../core/camera_stream_thermal.dart';
import '../../core/live_face_box_state.dart';
import '../../core/camera_input_image_utils.dart';
import '../../core/camera_platform_config.dart';
import '../../core/camera_stream_pipeline.dart';
import '../../core/camera_lens_utils.dart';
import '../../core/face_tracking_helper.dart';
import '../../core/production_face_recognition_constants.dart';
import '../../core/theme/app_ui.dart';
import '../../services/device_performance_service.dart';
import '../../services/distance_check_service.dart'
    show DistanceCheckService, DistanceProfile, DistanceStatus;
import '../../services/attendance_marking_service.dart';
import '../../services/anti_spoof_service.dart';
import '../../services/pre_capture_liveness_tracker.dart';
import '../../services/production_face_pipeline_service.dart';
import '../../services/student_face_match_index.dart';
import '../../services/b2b_storage_service.dart';
import '../../services/photo_compression_service.dart';
import '../widgets/face_tracking_box_overlay.dart';
import '../widgets/secure_network_image.dart';
import 'dart:io';

/// Auto attendance scan pipeline:
/// Camera → ML Kit face detection → TFLite anti-spoof (MiniFAS) →
/// MobileFaceNet match → mark attendance.
///
/// Face box: **green** = live (PAD), **red** = photo/video/screen.
class AutoFaceScanScreen extends StatefulWidget {
  static const routeName = '/auto-face-scan';

  final String? instituteId;

  const AutoFaceScanScreen({super.key, this.instituteId});

  @override
  State<AutoFaceScanScreen> createState() => _AutoFaceScanScreenState();
}

class _AutoFaceScanScreenState extends State<AutoFaceScanScreen>
    with WidgetsBindingObserver {
  late CameraController _cameraController;
  bool _cameraControllerInitialized = false;
  late FaceDetector _faceDetector;
  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;
  bool _isStreaming = false;

  DistanceStatus _distanceStatus = DistanceStatus.noFace;
  double _faceRatio = 0.0;
  Rect? _faceAnalysisRect;
  Size _faceAnalysisSize = Size.zero;
  LiveFaceBoxState _liveBoxState = LiveFaceBoxState.none;
  double _padConfidence = 0.0;

  bool _isInitializing = true;
  bool _isProcessingFrame = false;
  bool _isPipelineRunning = false;
  bool _isMarkingAttendance = false;
  DateTime? _lastPipelineRun;

  String? _instituteId;
  bool _isLoadingInstituteId = true;

  Map<String, dynamic>? _identifiedStudent;
  ProductionFacePipelineResult? _lastPipelineResult;
  String? _statusMessage;
  String? _scanInstruction;
  String? _attendanceStatus;
  DateTime? _recognizedAt;

  String? _lastAutoMarkedStudentId;
  DateTime? _lastAutoMarkAt;

  // Marked attendance details
  String? _markedStudentName;
  String? _markedSrNo;
  String? _markedInstituteId;
  DateTime? _markedTimestamp;
  String? _markedRecordType; // 'entry' or 'exit'
  double? _markedSimilarityScore;

  // Debug console logs
  final List<String> _consoleLogs = [];
  void _addLog(String message) {
    debugPrint(message);
    if (mounted) {
      setState(() {
        _consoleLogs.add('${DateTime.now().toIso8601String().split('T')[1].split('.')[0]} $message');
        if (_consoleLogs.length > 20) _consoleLogs.removeAt(0);
      });
    }
  }

  late PreCaptureLivenessTracker _livenessTracker;

  bool _padInFlight = false;
  int _padFrameTick = 0;
  bool _loggedPadBackend = false;
  final FaceTrackingHelper _faceTracking = FaceTrackingHelper();
  final CameraStreamFrameGate _frameGate = CameraStreamFrameGate();
  bool _streamPausedForBackground = false;
  DateTime? _lastUiUpdate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Placeholder tracker — rebuilt after AntiSpoofService loads in _initializeCamera().
    _livenessTracker = _buildLivenessTracker();
    _livenessTracker.onPadUpdated = _onPadResult;
    _loadInstituteId();
  }

  PreCaptureLivenessTracker _buildLivenessTracker() {
    return PreCaptureLivenessTracker(
      requiredBlinks: 1,
      requireBlink: true,
      minMicroMotionEvents: 0,
      minCleanLiveFramesBeforeCapture:
          DevicePerformanceService.minCleanLiveFramesBeforeCapture,
      minPadLiveStreak: 2,
      enableStreamScreenSpoof: false,
      enableStreamPad: DevicePerformanceService.enableStreamPadOnLivePreview,
      requireLiveFaceBeforeLiveness: true,
      require3DPoseEvidence: false,
      blockVideoReplay: false,
      strictAutoScanPad: true,
      inlinePadOnly: true,
      distanceProfile: DistanceProfile.kiosk,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_isStreaming) {
        _streamPausedForBackground = true;
        unawaited(_stopImageStreamOnly());
      }
      return;
    }
    if (state == AppLifecycleState.resumed && _streamPausedForBackground) {
      _streamPausedForBackground = false;
      if (!_isInitializing &&
          !_isPipelineRunning &&
          !_isMarkingAttendance &&
          _cameraController.value.isInitialized) {
        _startFaceDetection();
      }
    }
  }

  Future<void> _stopImageStreamOnly() async {
    if (!_isStreaming) return;
    try {
      await _cameraController.stopImageStream();
    } catch (_) {}
    _isStreaming = false;
    _frameGate.reset();
  }

  void _scheduleWarmFaceCache(String instituteId) {
    final delay = DevicePerformanceService.deferredWarmCacheDelay;
    if (delay == Duration.zero) {
      unawaited(StudentFaceMatchIndex.warmCache(instituteId));
      return;
    }
    unawaited(
      Future<void>.delayed(delay, () {
        if (!mounted) return;
        unawaited(StudentFaceMatchIndex.warmCache(instituteId));
      }),
    );
  }

  bool _shouldPushUiUpdate({required bool force}) {
    if (force) {
      _lastUiUpdate = DateTime.now();
      return true;
    }
    final now = DateTime.now();
    final gap = DevicePerformanceService.uiUpdateMinGapMs;
    if (_lastUiUpdate == null ||
        now.difference(_lastUiUpdate!).inMilliseconds >= gap) {
      _lastUiUpdate = now;
      return true;
    }
    return false;
  }

  void _onPadResult() {
    if (!mounted || _isPipelineRunning || _isMarkingAttendance) return;
    setState(() {
      _liveBoxState = _livenessTracker.faceBoxState(
        _distanceStatus,
        _distanceStatus == DistanceStatus.perfect,
      );
      _padConfidence = _livenessTracker.lastPadConfidence;
    });
  }

  Future<void> _loadInstituteId() async {
    try {
      if (widget.instituteId != null && widget.instituteId!.isNotEmpty) {
        setState(() {
          _instituteId = widget.instituteId;
          _isLoadingInstituteId = false;
        });
        _scheduleWarmFaceCache(widget.instituteId!);
        await AntiSpoofService.initializeForAutoScan();
        await _initializeCamera();
        return;
      }

      final user = appDb.auth.currentUser;
      if (user != null) {
        final row = await appDb
            .from('profiles')
            .select('institute_id')
            .eq('id', user.id)
            .maybeSingle();
        final instituteId = row?['institute_id'] as String?;
        if (instituteId != null && instituteId.isNotEmpty) {
          setState(() {
            _instituteId = instituteId;
            _isLoadingInstituteId = false;
          });
          _scheduleWarmFaceCache(instituteId);
          await AntiSpoofService.initializeForAutoScan();
          await _initializeCamera();
          return;
        }
      }

      if (mounted) {
        setState(() => _isLoadingInstituteId = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Institute not set. Please sign in again.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading institute ID: $e');
      if (mounted) {
        setState(() => _isLoadingInstituteId = false);
        Navigator.pop(context);
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No camera found')),
          );
          Navigator.pop(context);
        }
        return;
      }

      _selectedCameraIndex = preferredFrontCameraIndex(_availableCameras);
      await _initController(_availableCameras[_selectedCameraIndex]);

      _faceDetector = FaceDetector(
        options: StreamFaceDetectorOptions.build(),
      );

      // Rebuild tracker now — model is loaded, enableStreamPad is correct.
      if (mounted) {
        _livenessTracker = _buildLivenessTracker();
        _livenessTracker.onPadUpdated = _onPadResult;
      }

      if (mounted) {
        setState(() => _isInitializing = false);
        _startFaceDetection();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Camera init error: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _initController(CameraDescription camera) async {
    // Samsung devices throw Broken pipe / ERROR_GRAPH_CONFIG on first session.
    // Retry once with a delay — CameraX recovers on the second attempt.
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          await Future.delayed(const Duration(milliseconds: 600));
          if (_cameraControllerInitialized) {
            try { await _cameraController.dispose(); } catch (_) {}
            _cameraControllerInitialized = false;
          }
        }
        _cameraController = await CameraPlatformConfig.createStreamController(
          camera: camera,
          resolution: DevicePerformanceService.streamCameraResolution,
        );
        _cameraControllerInitialized = true;
        return;
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Camera init attempt ${attempt + 1} failed: $e');
        if (attempt == 1) rethrow;
      }
    }
  }

  void _startFaceDetection() {
    if (_isStreaming ||
        _streamPausedForBackground ||
        !_cameraController.value.isInitialized) {
      return;
    }
    _isStreaming = true;
    _frameGate.reset();
    _cameraController.startImageStream((CameraImage image) {
      if (_frameGate.shouldSkip(
        minGap: DevicePerformanceService.streamFrameMinGap,
        pipelineBusy:
            _isPipelineRunning || _isMarkingAttendance || _isProcessingFrame ||
            _padInFlight,
      )) {
        return;
      }

      final now = DateTime.now();
      if (_lastPipelineRun != null &&
          now.difference(_lastPipelineRun!).inMilliseconds <
              DevicePerformanceService.minRecognitionIntervalMs) {
        return;
      }

      _frameGate.markStarted();
      _isProcessingFrame = true;
      unawaited(_processStreamFrame(image));
    });
  }

  Future<void> _processStreamFrame(CameraImage image) async {
      try {
        final mlInput = CameraStreamPipeline.mlKitInput(_cameraController, image);
        if (mlInput == null) return;

        final rotation = mlInput.rotation;
        final faces = await _faceDetector.processImage(mlInput.inputImage);
        if (!mounted) return;

        if (faces.isEmpty) {
          _livenessTracker.reset();
          _faceTracking.reset();
          if (_shouldPushUiUpdate(force: true)) {
            setState(() {
              _distanceStatus = DistanceStatus.noFace;
              _faceRatio = 0;
              _faceAnalysisRect = null;
              _faceAnalysisSize = Size.zero;
              _liveBoxState = LiveFaceBoxState.none;
              _padConfidence = 0;
              _statusMessage = 'Look at the camera';
              _scanInstruction = null;
            });
          }
          return;
        }

        final display = CameraInputImageUtils.displaySizeForImage(image, rotation);
        final displayWidth = display.width;
        final displayHeight = display.height;

        final face = _faceTracking.selectPrimaryFace(faces);
        if (face == null) return;

        final streamFrame = CameraStreamPipeline.faceFrame(
          face: face,
          image: image,
          rotation: rotation,
        );
        final faceRect = streamFrame.bufferRect;

        final activelyScanning = !_isPipelineRunning &&
            !_isMarkingAttendance &&
            _identifiedStudent == null;

        if (activelyScanning && AntiSpoofService.isModelLoaded && !_loggedPadBackend) {
          _loggedPadBackend = true;
          if (kDebugMode) {
            debugPrint(
              '🛡️ Auto-scan PAD: stream=${AntiSpoofService.supportsStreamPad} '
              'captureOnly=${AntiSpoofService.captureTimePadOnly}',
            );
          }
        }

        _padFrameTick++;
        if (activelyScanning &&
            DevicePerformanceService.enableStreamPadOnLivePreview &&
            AntiSpoofService.supportsStreamPad &&
            !_padInFlight &&
            _padFrameTick % DevicePerformanceService.padFrameModulo == 0) {
          _padInFlight = true;
          final pad = await AntiSpoofService.checkSpoofFromCameraFrame(
            image,
            streamFrame.analysisBox,
            rotation: rotation,
          );
          _livenessTracker.applyStreamPadResult(pad);
          _padInFlight = false;
        }

        final live = _livenessTracker.evaluate(
          image: image,
          face: face,
          displayWidth: displayWidth,
          displayHeight: displayHeight,
          imageRotation: rotation,
          streamFrame: streamFrame,
        );

        final boxState = _livenessTracker.faceBoxState(
          live.distanceStatus,
          live.distanceStatus == DistanceStatus.perfect,
        );

        if (!mounted) return;

        final forceUi = boxState == LiveFaceBoxState.spoof ||
            boxState == LiveFaceBoxState.live ||
            live.spoofBlocked ||
            live.canCapture;
        if (_shouldPushUiUpdate(force: forceUi)) {
          setState(() {
            _distanceStatus = live.distanceStatus;
            _faceRatio = live.faceRatio;
            _faceAnalysisRect = streamFrame.analysisBox;
            _faceAnalysisSize = streamFrame.analysisSize;
            _liveBoxState = boxState;
            _padConfidence = _livenessTracker.lastPadConfidence;
            if (boxState == LiveFaceBoxState.spoof || live.spoofBlocked) {
              _statusMessage = live.livenessMessage;
              _scanInstruction =
                  activelyScanning ? live.livenessMessage : null;
            } else if (live.distanceStatus != DistanceStatus.perfect) {
              _statusMessage =
                  DistanceCheckService.phoneNotAtThreeFeetMessage(live.distanceStatus);
              _scanInstruction = _statusMessage;
            } else if (!_livenessTracker.isDistanceLocked) {
              _statusMessage = live.livenessMessage;
              _scanInstruction = live.livenessMessage;
            } else if (boxState == LiveFaceBoxState.checking) {
              _statusMessage = live.livenessMessage;
              _scanInstruction = live.livenessMessage;
            } else if (activelyScanning) {
              _statusMessage = AntiSpoofService.captureTimePadOnly
                  ? 'Face OK — blink once (live check on capture)'
                  : 'Live face OK — blink once';
              _scanInstruction = live.livenessMessage;
            } else {
              _statusMessage = live.livenessMessage;
              _scanInstruction = null;
            }
          });
        } else {
          _distanceStatus = live.distanceStatus;
          _faceRatio = live.faceRatio;
          _faceAnalysisRect = streamFrame.analysisBox;
          _faceAnalysisSize = streamFrame.analysisSize;
          _liveBoxState = boxState;
          _padConfidence = _livenessTracker.lastPadConfidence;
        }

        if (boxState == LiveFaceBoxState.spoof || live.spoofBlocked) return;

        if (boxState == LiveFaceBoxState.live &&
            live.canCapture &&
            _livenessTracker.mayCaptureNow &&
            _livenessTracker.isDistanceLocked &&
            live.distanceStatus == DistanceStatus.perfect) {
          final liveOk = await _livenessTracker.verifyFrameIsLive(image, faceRect);
          if (!liveOk) {
            _livenessTracker.lockSpoofMessageForHold(
              'Photo or screen spoof detected — use your live face only',
            );
            if (mounted) {
              setState(() {
                _liveBoxState = LiveFaceBoxState.spoof;
                _statusMessage =
                    _livenessTracker.activeSpoofUiMessage ??
                    'Photo or screen spoof detected — use your live face only';
                _scanInstruction = _statusMessage;
              });
            }
            return;
          }
          await _runPipelineCapture();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Stream face detection error: $e');
      } finally {
        _isProcessingFrame = false;
        _frameGate.markFinished();
      }
  }

  Future<void> _runPipelineCapture() async {
    if (_instituteId == null || _isPipelineRunning) return;
    _isPipelineRunning = true;
    _lastPipelineRun = DateTime.now();
    if (mounted) {
      setState(() => _scanInstruction = null);
    }

    try {
      if (_isStreaming) {
        await _cameraController.stopImageStream();
        _isStreaming = false;
      }

      final photo = await _cameraController.takePicture();
      final result = await ProductionFacePipelineService.processFrame(
        photoPath: photo.path,
        instituteId: _instituteId!,
        fastAttendancePath: true,
      );

      if (!mounted) return;

      setState(() {
        _lastPipelineResult = result;
        _recognizedAt = DateTime.now();
      });

      if (!result.passed || result.student == null) {
        setState(() {
          _identifiedStudent = null;
          _statusMessage = result.message;
          if (result.livenessPassed == false) {
            _liveBoxState = LiveFaceBoxState.spoof;
          }
        });
        _livenessTracker.reset();
        _startFaceDetection();
        return;
      }

      final studentId = result.student!['id']?.toString() ?? '';

      setState(() {
        _identifiedStudent = result.student;
        _statusMessage = 'Verified — marking attendance…';
      });

      if (!_isMarkingAttendance && _canAutoMarkNow(studentId)) {
        await _autoMarkAttendance(result);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Pipeline capture error: $e');
      if (mounted) {
        setState(() => _statusMessage = 'Recognition error — retrying…');
      }
      _livenessTracker.reset();
      _startFaceDetection();
    } finally {
      _isPipelineRunning = false;
    }
  }

  bool _canAutoMarkNow(String studentId) {
    if (_lastAutoMarkedStudentId != studentId) return true;
    final last = _lastAutoMarkAt;
    if (last == null) return true;
    return DateTime.now().difference(last).inSeconds >
        ProductionFaceRecognitionConstants.postMarkCooldownSeconds;
  }

  Future<void> _autoMarkAttendance(ProductionFacePipelineResult result) async {
    if (_instituteId == null || result.student == null || result.photoPath == null) {
      return;
    }
    setState(() => _isMarkingAttendance = true);

    try {
      _addLog('🔵 Starting attendance marking...');

      final student = result.student!;
      final studentId = student['id']?.toString();
      final srNo = student['sr_no']?.toString() ?? '';
      final studentName = student['name']?.toString() ?? student['student_name']?.toString() ?? '';

      _addLog('👤 Student: ID=$studentId, Name=$studentName');

      if (studentId == null || studentId.isEmpty) {
        throw Exception('❌ Student ID not found');
      }

      // Get embedding from student record
      _addLog('🔍 Fetching student record...');
      final studentRecord = await appDb
          .from('students')
          .select('id, institute_id, sr_no, fname, lname, mname, face_embedding_average')
          .eq('id', studentId)
          .single();

      _addLog('✅ Student record fetched');

      final embeddingJson = studentRecord['face_embedding_average'] as String?;
      if (embeddingJson == null || embeddingJson.isEmpty) {
        throw Exception('❌ No face embedding found for student');
      }

      _addLog('🧮 Parsing 512-D embedding...');
      final embedding = List<double>.from(
        jsonDecode(embeddingJson).map((x) => (x as num).toDouble()),
      );
      _addLog('✅ Embedding ready (${embedding.length}D)');

      // Compress and upload photo to B2
      _addLog('📷 Compressing photo...');
      final photoBytes = await PhotoCompressionService.compressPhoto(result.photoPath!);
      _addLog('✅ Compressed: ${(photoBytes.length / 1024).toStringAsFixed(1)}KB');

      _addLog('☁️ Uploading to B2...');
      final photoUrl = await B2BStorageService.uploadFile(
        '$_instituteId/$studentName/photo-attendance/${DateTime.now().toIso8601String()}.jpg',
        photoBytes,
        contentType: 'image/jpeg',
      );

      _addLog('✅ B2 uploaded: $photoUrl');

      // Get constructed student name
      final fname = studentRecord['fname'] ?? '';
      final lname = studentRecord['lname'] ?? '';
      final mname = studentRecord['mname'] ?? '';
      final fullName = '$fname ${mname.isNotEmpty ? '$mname ' : ''}$lname'.trim();

      // Mark entry attendance
      final markResult = await AttendanceMarkingService.markAttendance(
        studentId: studentId,
        instituteId: _instituteId!,
        srNo: srNo,
        studentName: fullName,
        photoUrl: photoUrl,
        embedding: embedding,
        similarityScore: result.similarity ?? 0.0,
        timestamp: DateTime.now(),
        recordType: 'entry',
      );

      if (!markResult['success']) {
        throw Exception(markResult['message'] ?? 'Failed to mark attendance');
      }

      if (mounted) {
        final now = DateTime.now();
        setState(() {
          _attendanceStatus = '✓ Entry marked';
          _statusMessage = 'Done — next student can scan';
          _lastAutoMarkedStudentId = studentId;
          _lastAutoMarkAt = now;
          // Store marked attendance details
          _markedStudentName = fullName;
          _markedSrNo = srNo;
          _markedInstituteId = _instituteId;
          _markedTimestamp = now;
          _markedRecordType = 'entry';
          _markedSimilarityScore = result.similarity ?? 0.0;
        });

        await Future.delayed(const Duration(milliseconds: 3000));
        if (mounted) {
          setState(() {
            _identifiedStudent = null;
            _lastPipelineResult = null;
            _attendanceStatus = null;
            // Keep marked details visible temporarily
          });
          _livenessTracker.reset();
          _startFaceDetection();
        }
      }
    } catch (e) {
      _addLog('❌ ERROR: ${e.toString().split('\n').first}');
      if (mounted) {
        setState(() {
          _attendanceStatus = '✗ Mark failed';
          _statusMessage = e.toString().split('\n').first;
        });
        _livenessTracker.reset();
        _startFaceDetection();
      }
    } finally {
      if (mounted) setState(() => _isMarkingAttendance = false);
    }
  }

  Future<void> _toggleCamera() async {
    if (_availableCameras.length < 2) return;
    setState(() => _isInitializing = true);
    if (_isStreaming) {
      await _cameraController.stopImageStream();
      _isStreaming = false;
    }
    await _cameraController.dispose();
    _selectedCameraIndex =
        toggleFacingCameraIndex(_availableCameras, _selectedCameraIndex);
    await _initController(_availableCameras[_selectedCameraIndex]);
    if (mounted) {
      setState(() => _isInitializing = false);
      _livenessTracker.reset();
      _faceTracking.reset();
      _startFaceDetection();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isStreaming) {
      unawaited(_cameraController.stopImageStream());
    }
    _cameraController.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInstituteId) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: const Text('Auto Face Attendance'),
        actions: [
          if (_availableCameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: _toggleCamera,
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!_isInitializing && _cameraController.value.isInitialized)
            CameraPreview(_cameraController)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_faceAnalysisRect != null &&
              _faceAnalysisSize.width > 0 &&
              _cameraController.value.isInitialized)
            Positioned.fill(
              child: FaceTrackingBoxOverlay(
                analysisRect: _faceAnalysisRect!,
                analysisSize: _faceAnalysisSize,
                boxState: _liveBoxState,
                cameraController: _cameraController,
                padConfidence: _padConfidence,
                // For live/spoof states show "REAL X%" / "FAKE X%" directly.
                // Only override with distance/hold labels when not yet at the PAD stage.
                labelOverride: (_liveBoxState == LiveFaceBoxState.live ||
                        _liveBoxState == LiveFaceBoxState.spoof)
                    ? null
                    : FaceTrackingBoxOverlay.labelForDistanceGate(
                        distance: _distanceStatus,
                        distanceLocked: _livenessTracker.isDistanceLocked,
                        canCapture: false,
                        requireBlink: false,
                      ),
              ),
            ),
          // 🟢 Green face detection box (same as registration UI)
          if (_distanceStatus != DistanceStatus.noFace)
            Positioned(
              bottom: 240,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _statusMessage ?? 'Face detected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
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
                ),
              ),
            ),
          _buildInfoPanel(),
          // Debug Console
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              maxHeight: 120,
              color: Colors.black.withValues(alpha: 0.85),
              border: Border(top: BorderSide(color: Colors.cyan, width: 2)),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '📟 Console',
                          style: TextStyle(
                            color: Colors.cyan,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_consoleLogs.length} logs',
                          style: TextStyle(
                            color: Colors.cyan.withValues(alpha: 0.6),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: Colors.cyan.withValues(alpha: 0.3), height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          _consoleLogs.join('\n'),
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 8,
                            fontFamily: 'monospace',
                            height: 1.2,
                          ),
                        ),
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

  Widget _buildInfoPanel() {
    final student = _identifiedStudent;
    final pipeline = _lastPipelineResult;
    final photoUrl = student?['face_photo_url']?.toString();
    final timestamp = _recognizedAt != null
        ? DateFormat('HH:mm:ss').format(_recognizedAt!)
        : '--:--:--';

    return SafeArea(
      child: Column(
        children: [
          _HudCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusMessage ?? DistanceCheckService.recommendedDistanceShort,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DistanceCheckService.recommendedDistanceDetail,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                  ),
                ),
                if (_isPipelineRunning || _isMarkingAttendance)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white24,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
              ],
            ),
          ),
          if (student != null) ...[
            _HudCard(
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: photoUrl != null && photoUrl.isNotEmpty
                        ? SecureNetworkImage(
                            imageUrl: photoUrl,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 64,
                            height: 64,
                            color: Colors.white12,
                            child: const Icon(Icons.person, color: Colors.white54),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student['name']?.toString() ?? 'Student',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'ID: ${student['sr_no'] ?? student['user_id'] ?? '—'}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _HudCard(
              child: Column(
                children: [
                  _MetricRow(
                    label: 'Liveness',
                    value: pipeline?.livenessPassed == true ? 'PASS' : '—',
                    valueColor: pipeline?.livenessPassed == true
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                  ),
                  _MetricRow(
                    label: 'Confidence',
                    value: pipeline?.similarity != null
                        ? '${(pipeline!.similarity! * 100).toStringAsFixed(1)}%'
                        : '—',
                  ),
                  _MetricRow(
                    label: 'Margin',
                    value: pipeline?.margin != null
                        ? pipeline!.margin!.toStringAsFixed(3)
                        : '—',
                  ),
                  _MetricRow(label: 'Time', value: timestamp),
                  _MetricRow(
                    label: 'Attendance',
                    value: _attendanceStatus ?? 'Pending',
                    valueColor: _attendanceStatus?.contains('✓') == true
                        ? Colors.greenAccent
                        : _attendanceStatus?.contains('✗') == true
                        ? Colors.redAccent
                        : Colors.white,
                  ),
                  if (_markedTimestamp != null) ...[
                    const Divider(color: Colors.white24, height: 12),
                    _MetricRow(
                      label: 'Name',
                      value: _markedStudentName ?? '—',
                    ),
                    _MetricRow(
                      label: 'SR No',
                      value: _markedSrNo ?? '—',
                    ),
                    _MetricRow(
                      label: 'Institute',
                      value: (_markedInstituteId?.length ?? 0) > 12
                          ? '${_markedInstituteId?.substring(0, 12)}…'
                          : _markedInstituteId ?? '—',
                    ),
                    _MetricRow(
                      label: 'Type',
                      value: '${_markedRecordType?.toUpperCase() ?? '—'}',
                      valueColor: Colors.blueAccent,
                    ),
                    _MetricRow(
                      label: 'Marked At',
                      value: _markedTimestamp != null
                          ? DateFormat('HH:mm:ss').format(_markedTimestamp!)
                          : '—',
                    ),
                    _MetricRow(
                      label: 'Match Score',
                      value: _markedSimilarityScore != null
                          ? '${(_markedSimilarityScore! * 100).toStringAsFixed(1)}%'
                          : '—',
                      valueColor: _markedSimilarityScore != null && _markedSimilarityScore! > 0.8
                          ? Colors.greenAccent
                          : Colors.white,
                    ),
                  ],
                ],
              ),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}

class _HudCard extends StatelessWidget {
  const _HudCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: child,
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.valueColor = Colors.white,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
