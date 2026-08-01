import 'dart:async' show unawaited;
import 'dart:ui' show Rect, Size;
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../core/stream_ui_throttle.dart';
import '../../core/camera_stream_frame_gate.dart';
import '../../core/camera_stream_thermal.dart';
import '../../core/camera_input_image_utils.dart';
import '../../core/camera_platform_config.dart';
import '../../core/camera_stream_pipeline.dart';
import '../../core/camera_lens_utils.dart';
import '../../core/face_tracking_helper.dart';
import '../../core/live_face_box_state.dart';
import '../../services/distance_check_service.dart';
import '../../services/device_performance_service.dart';
import '../../services/anti_spoof_service.dart';
import '../../services/pre_capture_liveness_tracker.dart';
import '../widgets/face_tracking_box_overlay.dart';
import '../widgets/session_monitor.dart';

/// Registration + capture camera — same live checks as [AutoFaceScanScreen].
/// Registration: 3 ft → stream PAD → head turn (left/right) or hold front → auto capture.
class AttendanceCameraScreen extends StatefulWidget {
  final String studentName;
  final String studentId;
  final String? appBarTitle;
  final String? stepLabel;
  final String? poseInstruction;

  /// `front` / `left` / `right` for 3-angle enrollment.
  final String? registrationPose;

  /// Blink liveness before capture (attendance default: 1; registration uses 2).
  final bool requireBlink;

  /// Auto [takePicture] when distance + liveness (+ head turn for L/R) are ready.
  final bool autoCaptureWhenReady;

  /// Single-session 3-pose registration: front (2 blinks) → left → right.
  /// Returns List<XFile> with 3 photos via Navigator.pop.
  final bool multiPoseRegistration;

  const AttendanceCameraScreen({
    super.key,
    required this.studentName,
    required this.studentId,
    this.appBarTitle,
    this.stepLabel,
    this.poseInstruction,
    this.registrationPose,
    this.requireBlink = true,
    this.autoCaptureWhenReady = false,
    this.multiPoseRegistration = false,
  });

  @override
  State<AttendanceCameraScreen> createState() => _AttendanceCameraScreenState();
}

class _AttendanceCameraScreenState extends State<AttendanceCameraScreen>
    with WidgetsBindingObserver {
  late PreCaptureLivenessTracker _livenessTracker;
  late final bool _autoCapture;
  late final bool _requireBlink;
  late final int _requiredBlinks;
  late final bool _isRegistration;
  late final DistanceProfile _distanceProfile;
  late CameraController _cameraController;
  late FaceDetector _faceDetector;
  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;
  bool _isStreaming = false;

  // Distance check state
  DistanceStatus _distanceStatus = DistanceStatus.noFace;
  double _faceRatio = 0.0;
  double _distanceConfidence = 0.0;
  bool _canCapture = false;
  Rect? _faceAnalysisRect;
  Size _faceAnalysisSize = Size.zero;
  LiveFaceBoxState _faceBoxState = LiveFaceBoxState.none;
  double _padConfidence = 0.0;
  final FaceTrackingHelper _faceTracking = FaceTrackingHelper();
  bool _padInFlight = false;
  int _padFrameTick = 0;

  String get _registrationLivenessHint => _poseInstruction(_currentPose);

  String get _attendanceLivenessHint {
    if (_requireBlink) {
      return _requiredBlinks > 1
          ? 'Blink $_requiredBlinks times, then we capture'
          : 'Blink your eyes to verify';
    }
    return 'Hold still at 3 ft';
  }

  String get _defaultLivenessHint =>
      _isRegistration ? _registrationLivenessHint : _attendanceLivenessHint;

  String _poseInstruction(String pose) => switch (pose) {
    'front' => 'Look straight — blink 2 times (auto capture)',
    'left'  => 'Now glance LEFT — hold for a moment',
    'right' => 'Now glance RIGHT — hold for a moment',
    _       => 'Hold still at ~3 ft',
  };

  String get _multiPoseStepLabel =>
      'Photo ${_multiPoseIndex + 1} of 3 — ${_multiPoses[_multiPoseIndex].toUpperCase()}';

  String _livenessMessage = '';
  bool _isCapturing = false;
  bool _isProcessingFrame = false;
  bool _capturePending = false;
  bool _captureSessionLocked = false;

  // Multi-pose registration state
  static const _multiPoses = ['front', 'left', 'right'];
  int _multiPoseIndex = 0;
  final List<XFile> _multiPosePhotos = [];
  String get _currentPose =>
      widget.multiPoseRegistration ? _multiPoses[_multiPoseIndex] : (widget.registrationPose ?? '');

  final CameraStreamFrameGate _frameGate = CameraStreamFrameGate();
  final StreamUiThrottle _uiThrottle = StreamUiThrottle();
  bool _streamPausedForBackground = false;

  PreCaptureLivenessTracker _buildLivenessTracker() {
    final pose = _currentPose.toLowerCase();
    ScanHeadTurnChallenge? headTurn;
    if (pose == 'left' || pose == 'right') {
      // Back camera mirrors yaw — swap challenge direction.
      if (pose == 'left') {
        headTurn = ScanHeadTurnChallenge.turnRight;
      } else {
        headTurn = ScanHeadTurnChallenge.turnLeft;
      }
    }

    final isSidePose = pose == 'left' || pose == 'right';
    final blinks = isSidePose ? 0 : (_isRegistration ? 2 : _requiredBlinks);
    final requireBlink = isSidePose ? false : (_isRegistration ? true : _requireBlink);

    return PreCaptureLivenessTracker(
      requiredBlinks: blinks,
      requireBlink: requireBlink,
      minMicroMotionEvents: 0,
      minCleanLiveFramesBeforeCapture:
          DevicePerformanceService.minCleanLiveFramesBeforeCapture,
      minPadLiveStreak: 2,
      enableStreamScreenSpoof: false,
      enableStreamPad: _isRegistration
          ? DevicePerformanceService.enableStreamPadOnRegistration
          : DevicePerformanceService.enableStreamPadOnLivePreview,
      requireLiveFaceBeforeLiveness: true,
      require3DPoseEvidence: false,
      blockVideoReplay: false,
      strictAutoScanPad: true,
      inlinePadOnly: true,
      randomHeadTurnChallenge: headTurn,
      // Detection uses the mirrored challenge above, but the on-screen text
      // must match the actual pose the user is capturing (left/right).
      directedTurnLabelOverride: pose == 'left'
          ? 'LEFT'
          : pose == 'right'
              ? 'RIGHT'
              : null,
      directedTurnYawDegrees: _isRegistration ? 12.0 : 15.0,
      distanceProfile: _distanceProfile,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final pose = widget.registrationPose?.trim().toLowerCase();
    final isRegistration =
        widget.multiPoseRegistration || (pose != null && pose.isNotEmpty);
    if (isRegistration) {
      _requireBlink = true;
      _requiredBlinks = 2;
    } else {
      _requireBlink = widget.requireBlink;
      _requiredBlinks = _requireBlink ? 1 : 0;
    }
    _autoCapture = isRegistration || widget.autoCaptureWhenReady;
    _isRegistration = isRegistration;
    _distanceProfile =
        isRegistration ? DistanceProfile.registration : DistanceProfile.attendance;
    _livenessTracker = _buildLivenessTracker();
    _livenessTracker.onPadUpdated = _onPadUpdated;
    _livenessMessage = _defaultLivenessHint;
    unawaited(AntiSpoofService.initializeForAutoScan());
    _initializeCamera();
  }

  void _onPadUpdated() {
    if (!mounted || _isCapturing) return;
    if (!_uiThrottle.shouldUpdate(
      force: false,
      minGapMs: DevicePerformanceService.uiUpdateMinGapMs,
    )) {
      return;
    }
    setState(() {
      _faceBoxState = _livenessTracker.faceBoxState(
        _distanceStatus,
        _distanceStatus == DistanceStatus.perfect,
      );
      _padConfidence = _livenessTracker.lastPadConfidence;
    });
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
          !_isCapturing &&
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

  bool _isInitializing = true;

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

      // Registration: back camera for all 3 poses (front/left/right).
      _selectedCameraIndex = preferredBackCameraIndex(_availableCameras);

      await _initController(_availableCameras[_selectedCameraIndex]);

      _faceDetector = FaceDetector(
        options: StreamFaceDetectorOptions.build(),
      );

      if (mounted) {
        setState(() => _isInitializing = false);
        _startFaceDetection();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Camera init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _initController(CameraDescription camera) async {
    // Registration: medium so ML Kit detects turned faces in the captured still.
    // Attendance: low to reduce heat/battery during continuous stream.
    _cameraController = await CameraPlatformConfig.createStreamController(
      camera: camera,
      resolution: _isRegistration
          ? ResolutionPreset.medium
          : DevicePerformanceService.streamCameraResolution,
    );
  }

  Future<void> _toggleCamera() async {
    if (_availableCameras.length < 2) return;

    setState(() => _isInitializing = true);

    // Stop current stream and dispose
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
        pipelineBusy: (_isCapturing && !_capturePending) ||
            _isProcessingFrame ||
            _capturePending ||
            _padInFlight,
      )) {
        return;
      }
      _frameGate.markStarted();
      _isProcessingFrame = true;
      unawaited(_processRegistrationStreamFrame(image));
    });
  }

  Future<void> _processRegistrationStreamFrame(CameraImage image) async {
      try {
        final mlInput = CameraStreamPipeline.mlKitInput(_cameraController, image);
        if (mlInput == null) return;

        final rotation = mlInput.rotation;
        final faces = await _faceDetector.processImage(mlInput.inputImage);

        if (!mounted) return;

        if (faces.isEmpty) {
          _livenessTracker.reset();
          _faceTracking.reset();
          setState(() {
            _distanceStatus = DistanceStatus.noFace;
            _canCapture = false;
            _faceAnalysisRect = null;
            _faceAnalysisSize = Size.zero;
            _faceBoxState = LiveFaceBoxState.none;
            _livenessMessage = _defaultLivenessHint;
          });
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

        if (!_isCapturing && !_capturePending) {
          _padFrameTick++;
          final streamPad = _isRegistration
              ? DevicePerformanceService.enableStreamPadOnRegistration
              : DevicePerformanceService.enableStreamPadOnLivePreview;
          if (kDebugMode && _padFrameTick == 1) {
            debugPrint('🔍 PAD gate: streamPad=$streamPad '
                'supportsStreamPad=${AntiSpoofService.supportsStreamPad} '
                'modulo=${DevicePerformanceService.padFrameModulo}');
          }
          if (streamPad &&
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
        }

        if (_capturePending &&
            !_isCapturing &&
            _livenessTracker.mayCaptureNow) {
          await _finishCaptureWithLiveCheck(image, faceRect);
          return;
        }

        final live = _livenessTracker.evaluate(
          image: image,
          face: face,
          displayWidth: displayWidth,
          displayHeight: displayHeight,
          imageRotation: rotation,
          streamFrame: streamFrame,
        );

        final effectiveStatus = live.distanceStatus;

        final atThreeFt = DistanceCheckService.allowsCapture(effectiveStatus);
        final distanceLocked = _livenessTracker.isDistanceLocked;
        final canCaptureNow = atThreeFt &&
            distanceLocked &&
            live.canCapture &&
            _livenessTracker.mayCaptureNow;

        final boxState = _livenessTracker.faceBoxState(
          effectiveStatus,
          effectiveStatus == DistanceStatus.perfect,
        );

        if (!mounted) return;

        final forceUi = boxState == LiveFaceBoxState.spoof ||
            boxState == LiveFaceBoxState.live ||
            live.spoofBlocked ||
            canCaptureNow;
        if (_uiThrottle.shouldUpdate(
          force: forceUi,
          minGapMs: DevicePerformanceService.uiUpdateMinGapMs,
        )) {
          setState(() {
            _distanceStatus = effectiveStatus;
            _faceRatio = live.faceRatio;
            _distanceConfidence = live.distanceConfidence;
            _canCapture = canCaptureNow &&
                boxState != LiveFaceBoxState.spoof &&
                !live.spoofBlocked;
            _faceAnalysisRect = streamFrame.analysisBox;
            _faceAnalysisSize = streamFrame.analysisSize;
            _faceBoxState = boxState;
            _padConfidence = _livenessTracker.lastPadConfidence;
            if (boxState == LiveFaceBoxState.spoof || live.spoofBlocked) {
              _livenessMessage = live.livenessMessage;
            } else if (!atThreeFt) {
              _livenessMessage =
                  DistanceCheckService.phoneNotAtThreeFeetMessage(
                effectiveStatus,
                profile: _distanceProfile,
              );
            } else if (!distanceLocked) {
              _livenessMessage =
                  DistanceCheckService.holdThreeFeetSteadyFor(_distanceProfile);
            } else if (boxState == LiveFaceBoxState.checking) {
              _livenessMessage = live.livenessMessage;
            } else if (!_autoCapture &&
                _canCapture &&
                _livenessTracker.mayCaptureNow) {
              _livenessMessage = 'Ready — tap Capture below';
            } else if (AntiSpoofService.captureTimePadOnly && !_autoCapture) {
              _livenessMessage = _requireBlink
                  ? 'Phone at 3 ft — blink once, then tap Capture'
                  : 'Phone at 3 ft — tap Capture';
            } else {
              _livenessMessage = live.livenessMessage;
            }
          });
        } else {
          _distanceStatus = effectiveStatus;
          _faceRatio = live.faceRatio;
          _distanceConfidence = live.distanceConfidence;
          _canCapture = canCaptureNow &&
              boxState != LiveFaceBoxState.spoof &&
              !live.spoofBlocked;
          _faceAnalysisRect = streamFrame.analysisBox;
          _faceAnalysisSize = streamFrame.analysisSize;
          _faceBoxState = boxState;
          _padConfidence = _livenessTracker.lastPadConfidence;
        }

        if (boxState == LiveFaceBoxState.spoof || live.spoofBlocked) return;

        if (_autoCapture &&
            !_captureSessionLocked &&
            !_isCapturing &&
            !_capturePending &&
            boxState == LiveFaceBoxState.live &&
            _canCapture &&
            _livenessTracker.mayCaptureNow &&
            distanceLocked &&
            effectiveStatus == DistanceStatus.perfect) {
          _captureSessionLocked = true;
          final liveOk =
              await _livenessTracker.verifyFrameIsLive(image, faceRect);
          if (!liveOk) {
            _captureSessionLocked = false;
            _livenessTracker.lockSpoofMessageForHold(
              'Photo or screen spoof detected — use your live face only',
            );
            if (mounted) {
              setState(() {
                _faceBoxState = LiveFaceBoxState.spoof;
                _livenessMessage =
                    _livenessTracker.activeSpoofUiMessage ??
                    'Photo or screen spoof detected — use your live face only';
              });
            }
            return;
          }
          if (kDebugMode) debugPrint('⚡️ Camera — auto capture');
          await _finishCaptureWithLiveCheck(image, faceRect);
          return;
        }

        if (kDebugMode) {
          debugPrint(
            '📱 Attendance camera - Status: $_distanceStatus, Distance: ${_faceRatio.toStringAsFixed(3)}, '
            'Ready: $_canCapture, Blinks: ${_livenessTracker.blinksDetected}/${_livenessTracker.requiredBlinks}, '
            'ScreenSpoof: ${_livenessTracker.screenSpoofScore.toStringAsFixed(3)} '
            '(streak=${_livenessTracker.screenSpoofStreak})',
          );
        }
      } catch (e) {
        if (kDebugMode) debugPrint('❌ Face detection error: $e');
      } finally {
        _isProcessingFrame = false;
        _frameGate.markFinished();
      }
  }

  Future<void> _capturePhoto() async {
    if (!DistanceCheckService.allowsCapture(_distanceStatus) ||
        !_livenessTracker.isDistanceLocked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              DistanceCheckService.phoneNotAtThreeFeetMessage(_distanceStatus),
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
      return;
    }
    if (!_livenessTracker.mayCaptureNow) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _livenessMessage.isNotEmpty
                  ? _livenessMessage
                  : _defaultLivenessHint,
            ),
          ),
        );
      }
      return;
    }
    if (_faceBoxState == LiveFaceBoxState.spoof ||
        _livenessTracker.padMarkedFake) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo or video — show your live face only'),
          ),
        );
      }
      return;
    }
    if (!_canCapture || _isCapturing || _capturePending || _captureSessionLocked) {
      return;
    }

    setState(() => _capturePending = true);
  }

  void _resetCaptureUi({bool restartStream = false}) {
    if (!mounted) return;
    setState(() {
      _isCapturing = false;
      _capturePending = false;
      _captureSessionLocked = false;
    });
    if (restartStream &&
        !_isStreaming &&
        _cameraController.value.isInitialized) {
      _startFaceDetection();
    }
  }

  Future<void> _finishCaptureWithLiveCheck(CameraImage image, Rect faceRect) async {
    if (_isCapturing) return;
    _captureSessionLocked = true;
    _capturePending = false;

    if (!DistanceCheckService.allowsCapture(_distanceStatus) ||
        !_livenessTracker.isDistanceLocked) {
      _resetCaptureUi(restartStream: true);
      return;
    }

    if (!mounted) return;
    setState(() => _isCapturing = true);

    try {
      SessionMonitor.beginSuppressResumeLock();

      if (_isStreaming) {
        await _cameraController.stopImageStream();
        _isStreaming = false;
      }

      final XFile photo = await _cameraController.takePicture();

      // Capture-time PAD removed — MiniFAS stream already gates the box green
      // before blink fires, so capture is only possible when stream confirmed live.

      await Future<void>.delayed(const Duration(milliseconds: 200));
      SessionMonitor.endSuppressResumeLock();

      if (!mounted) return;

      // Multi-pose: advance through front → left → right in one session.
      if (widget.multiPoseRegistration) {
        _multiPosePhotos.add(photo);
        if (_multiPosePhotos.length >= _multiPoses.length) {
          Navigator.pop(context, _multiPosePhotos);
          return;
        }
        // Advance to next pose.
        setState(() {
          _multiPoseIndex++;
          _livenessMessage = _poseInstruction(_multiPoses[_multiPoseIndex]);
          _faceBoxState = LiveFaceBoxState.none;
          _canCapture = false;
          _isCapturing = false;
          _capturePending = false;
          _captureSessionLocked = false;
        });
        // Replace tracker for new pose (final fields — must rebuild).
        _livenessTracker = _buildLivenessTracker();
        _livenessTracker.onPadUpdated = _onPadUpdated;
        _startFaceDetection();
        return;
      }

      Navigator.pop(context, photo);
    } catch (e) {
      SessionMonitor.endSuppressResumeLock();
      if (kDebugMode) debugPrint('❌ Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
      _resetCaptureUi(restartStream: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isStreaming) {
      _isStreaming = false;
      unawaited(_cameraController.stopImageStream());
    }
    _cameraController.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.appBarTitle ?? 'Mark Attendance'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_cameraController.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.appBarTitle ?? 'Mark Attendance'),
        ),
        body: const Center(
          child: Text('Camera not available'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.appBarTitle ?? 'Mark Attendance'),
        elevation: 0,
        actions: [
          if (_availableCameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: _isCapturing ? null : _toggleCamera,
              tooltip: _availableCameras[_selectedCameraIndex].lensDirection ==
                      CameraLensDirection.back
                  ? 'Use front (selfie) camera'
                  : 'Use back camera',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview - fill entire screen
          SizedBox.expand(
            child: CameraPreview(_cameraController),
          ),

          if (_faceAnalysisRect != null &&
              _faceAnalysisSize.width > 0 &&
              _cameraController.value.isInitialized)
            Positioned.fill(
              child: FaceTrackingBoxOverlay(
                analysisRect: _faceAnalysisRect!,
                analysisSize: _faceAnalysisSize,
                boxState: _faceBoxState,
                cameraController: _cameraController,
                padConfidence: _padConfidence,
                // live/spoof: show "REAL X%" / "FAKE X%"; otherwise distance hint.
                labelOverride: (_faceBoxState == LiveFaceBoxState.live ||
                        _faceBoxState == LiveFaceBoxState.spoof)
                    ? null
                    : FaceTrackingBoxOverlay.labelForDistanceGate(
                        distance: _distanceStatus,
                        distanceLocked: _livenessTracker.isDistanceLocked,
                        canCapture: _canCapture,
                        requireBlink: _isRegistration && _requireBlink,
                      ),
              ),
            ),

          if (!_autoCapture)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton.extended(
                  onPressed: _canCapture &&
                          _faceBoxState != LiveFaceBoxState.spoof &&
                          !_isCapturing &&
                          !_capturePending
                      ? _capturePhoto
                      : null,
                  backgroundColor: _canCapture &&
                          _faceBoxState != LiveFaceBoxState.spoof &&
                          !_isCapturing &&
                          !_capturePending
                      ? Colors.green
                      : Colors.grey,
                  icon: (_isCapturing || _capturePending)
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.camera_alt),
                  label: Text(
                    (_isCapturing || _capturePending)
                        ? 'Capturing...'
                        : _faceBoxState == LiveFaceBoxState.spoof
                            ? 'Not live — retake'
                            : _faceBoxState == LiveFaceBoxState.checking
                                ? 'Checking live face…'
                                : _canCapture
                                    ? 'Tap to capture (1 photo)'
                                    : 'Set phone to 3 ft first',
                  ),
                ),
              ),
            ),

          // Instructions (top)
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.multiPoseRegistration || widget.stepLabel != null) ...[
                    Text(
                      widget.multiPoseRegistration
                          ? _multiPoseStepLabel
                          : widget.stepLabel!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    widget.multiPoseRegistration
                        ? _poseInstruction(_currentPose)
                        : widget.poseInstruction ??
                            'Keep full face inside the box at arm\'s length (~3 ft)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _distanceStatus == DistanceStatus.perfect &&
                            _livenessTracker.isDistanceLocked
                        ? DistanceCheckService.phoneAtThreeFeetReadyMessage()
                        : DistanceCheckService.phoneNotAtThreeFeetMessage(
                            _distanceStatus,
                          ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _distanceStatus == DistanceStatus.perfect &&
                              _livenessTracker.isDistanceLocked
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_requireBlink &&
                      _livenessTracker.requiredBlinks > 0 &&
                      _distanceStatus == DistanceStatus.perfect &&
                      _livenessTracker.isDistanceLocked)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _livenessTracker.blinksDetected >=
                                  _livenessTracker.requiredBlinks
                              ? '✅ Capturing... $_livenessMessage'
                              : '📏 Distance OK! Blinks: ${_livenessTracker.blinksDetected}/${_livenessTracker.requiredBlinks}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _livenessTracker.blinksDetected >=
                                    _livenessTracker.requiredBlinks
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_livenessTracker.blinksDetected <
                            _livenessTracker.requiredBlinks)
                          const Text(
                            '👁️ Blink your eyes to verify',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    )
                  else if (_autoCapture &&
                      _distanceStatus == DistanceStatus.perfect &&
                      _livenessTracker.isDistanceLocked)
                    Text(
                      _isCapturing || _capturePending
                          ? '✅ Capturing…'
                          : '✅ $_livenessMessage',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else if (!_autoCapture &&
                      _distanceStatus == DistanceStatus.perfect)
                    Text(
                      '✅ Distance OK — tap Capture',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else if (_distanceStatus == DistanceStatus.tooClosed)
                    Text(
                      DistanceCheckService.userMessageFor(DistanceStatus.tooClosed),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else if (_distanceStatus == DistanceStatus.tooFar)
                    Text(
                      DistanceCheckService.userMessageFor(DistanceStatus.tooFar),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    const Text(
                      '❓ No face detected',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
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
