import 'dart:async' show unawaited;
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
import '../../services/inline_student_attendance_service.dart';
import '../../services/anti_spoof_service.dart';
import '../../services/pre_capture_liveness_tracker.dart';
import '../../services/production_face_pipeline_service.dart';
import '../../services/student_face_match_index.dart';
import '../widgets/face_tracking_box_overlay.dart';
import '../widgets/secure_network_image.dart';

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
        if (mounted) {
          unawaited(
            InlineStudentAttendanceService.warmGpsForInstitute(
              context,
              widget.instituteId!,
            ),
          );
        }
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
          if (mounted) {
            unawaited(
              InlineStudentAttendanceService.warmGpsForInstitute(
                context,
                instituteId,
              ),
            );
          }
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
      final student = result.student!;
      final srNo = student['sr_no']?.toString() ?? '';
      final studentId = student['id']?.toString();

      await InlineStudentAttendanceService.markForRoll(
        context,
        instituteId: _instituteId!,
        srNo: srNo,
        studentId: studentId,
        preCapturedPhotoPath: result.photoPath,
        productionPipelineVerified: true,
        productionSimilarity: result.similarity,
      );

      if (mounted) {
        setState(() {
          _attendanceStatus = 'Attendance marked';
          _statusMessage = 'Done — next student can scan';
          _lastAutoMarkedStudentId = studentId;
          _lastAutoMarkAt = DateTime.now();
        });

        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          setState(() {
            _identifiedStudent = null;
            _lastPipelineResult = null;
            _attendanceStatus = null;
          });
          _livenessTracker.reset();
          _startFaceDetection();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _attendanceStatus = 'Mark failed';
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
          _buildInfoPanel(),
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
                    valueColor: _attendanceStatus == 'Attendance marked'
                        ? Colors.greenAccent
                        : Colors.white,
                  ),
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
