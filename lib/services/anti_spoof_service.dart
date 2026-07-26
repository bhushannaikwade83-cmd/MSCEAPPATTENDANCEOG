import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    show InputImageRotation;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// Heuristic services removed — MiniFAS TFLite is the sole PAD source.

enum _AntiSpoofBackend { none, faceAntiSpoofing256, miniFas80, miniFasV1SE80, antispoofPrintReplay128 }

/// On-device face anti-spoof (PAD).
///
/// Loads [face_anti_spoofing.tflite] (256×256).
///
/// ⚠️ CAPTURE-TIME PAD ONLY: Stream detection disabled due to:
///   - YUV color space normalization issues
///   - Lighting variations in camera stream
///   - Device-specific sensor characteristics
///
/// Solution: Rely on high-threshold capture-time detection instead.
/// Real faces: 0.1-0.6, Fake (photo): 0.75+, Block threshold: 0.85+
class AntiSpoofService {
  /// Block fake ONLY when model is highly confident (>0.85).
  /// Avoids false positives on real faces. Real=0.1-0.6, Fake=0.75+
  static const double liveThreshold = 0.85;
  static const double _faceAntiSpoofAttackThreshold = 0.85;
  static const int _miniFasSize = 80;
  static const int _antispoofBinSize = 128;
  static const int _faceAntiSpoofSize = 256;
  static const double _miniFasBboxScale = 2.7;
  static const double _miniFasV1SEBboxScale = 4.0; // MiniFASNetV1SE scale=4.0
  static const double _antispoofBinBboxScale = 1.5;

  static const List<String> _assetCandidates = [
    'assets/models/minifas_v1se_80x80.tflite',      // MiniFASNetV1SE 80×80 — primary (float32, 3-class)
    'assets/models/anti_spoof_print_replay.tflite', // 128×128 3-class print+replay — supports stream PAD
    'assets/models/face_anti_spoofing.tflite',      // 256×256 fallback — capture only
  ];

  static const double strictStreamLiveThreshold = 0.56;
  static const double strictStreamSpoofThreshold = 0.40;

  static const int _faceAntiSpoofRouteIndex = 6;

  static Interpreter? _interpreter;
  static _AntiSpoofBackend _backend = _AntiSpoofBackend.none;
  static bool _isInitialized = false;
  static bool _allModelsFailed = false;
  static Future<void>? _initFuture;
  static Future<void>? _autoScanInitFuture;
  static bool _miniFasInputNormalized = true;

  static bool get isModelLoaded => _isInitialized && _interpreter != null;

  static bool get allModelsFailed => _allModelsFailed;

  /// 256×256 model: stream YUV PAD is skipped; still capture runs full PAD.
  static bool get useCaptureTimePadOnly =>
      isModelLoaded && !supportsStreamPad;

  /// Stream PAD for 128×128 print+replay model and MiniFAS.
  static bool get supportsStreamPad =>
      _backend == _AntiSpoofBackend.miniFas80 ||
      _backend == _AntiSpoofBackend.miniFasV1SE80 ||
      _backend == _AntiSpoofBackend.antispoofPrintReplay128;

  /// 256 model loaded but must not run on live camera stream.
  static bool get captureTimePadOnly => useCaptureTimePadOnly;

  static bool passesAttendanceCheck(AntiSpoofResult result) {
    // Different models expose confidence differently:
    // - MiniFAS / print-replay: confidence = live probability
    // - face_anti_spoofing256: confidence is derived from spoof score
    // Treat only strong spoof signals as a block so we do not reject
    // real students on uncertain capture-time PAD output.
    if (result.isReal) return true;
    return spoofConfidence(result) < 0.85;
  }

  /// Stricter gate for auto-scan stream + capture (live human only).
  static bool passesStrictAutoScan(AntiSpoofResult result) {
    if (!result.isReal) {
      return spoofConfidence(result) < 0.92;
    }
    return switch (_backend) {
      _AntiSpoofBackend.antispoofPrintReplay128 => result.confidence >= 0.50,
      _AntiSpoofBackend.miniFas80 =>
        result.confidence >= strictStreamLiveThreshold,
      _AntiSpoofBackend.miniFasV1SE80 =>
        result.confidence >= strictStreamLiveThreshold,
      _AntiSpoofBackend.faceAntiSpoofing256 => result.confidence >= 0.40,
      _ => result.confidence >= 0.55,
    };
  }

  /// Photo / screen / video on phone — turn box red only on STRONG signal.
  /// Require very high confidence to block on stream (stream PAD is unreliable).
  /// Most stream detection happens at capture time instead.
  static bool isImmediateSpoof(AntiSpoofResult result) {
    if (!result.isReal) {
      return spoofConfidence(result) >= 0.92;
    }
    return switch (_backend) {
      _AntiSpoofBackend.antispoofPrintReplay128 =>
        result.confidence < 0.20, // VERY strict to avoid false block
      _AntiSpoofBackend.miniFas80 =>
        result.confidence < 0.20, // VERY strict to avoid false block
      _AntiSpoofBackend.miniFasV1SE80 =>
        result.confidence < 0.20, // VERY strict to avoid false block
      _AntiSpoofBackend.faceAntiSpoofing256 =>
        result.confidence < 0.10, // Almost never block on stream for 256x256
      _ => false,
    };
  }

  /// Backend-aware "attack confidence" normalized to 0..1.
  ///
  /// MiniFAS-style models expose live probability, so spoof confidence is
  /// `1 - liveProb`. The 256x256 tree model already returns a score derived
  /// from spoof evidence, so we keep it as-is.
  static double spoofConfidence(AntiSpoofResult result) {
    final raw = switch (_backend) {
      _AntiSpoofBackend.miniFas80 => 1.0 - result.confidence,
      _AntiSpoofBackend.miniFasV1SE80 => 1.0 - result.confidence,
      _AntiSpoofBackend.antispoofPrintReplay128 => 1.0 - result.confidence,
      _AntiSpoofBackend.faceAntiSpoofing256 => result.confidence,
      _ => result.isReal ? 0.0 : 1.0 - result.confidence,
    };
    return raw.clamp(0.0, 1.0);
  }

  /// Final capture-time decision for auto attendance.
  ///
  /// The preview stream already requires distance + blink + stable live frames.
  /// At capture time we only want to reject when PAD is strongly indicating
  /// spoof, not when it is merely uncertain for a real face.
  static bool shouldRejectAutoScanCapture(AntiSpoofResult result) {
    if (allModelsFailed || !isModelLoaded) return false;
    if (result.isReal) return false;
    return spoofConfidence(result) >= 0.92;
  }

  /// Single entry: load once per app session (256 fallback on iOS).
  static Future<void> ensureLoaded() => initializeForAutoScan();

  /// One-time load (shared by registration + auto attendance).
  static Future<void> initializeForAutoScan() async {
    if (_isInitialized || _allModelsFailed) return;
    if (_autoScanInitFuture != null) {
      await _autoScanInitFuture;
      return;
    }
    if (_initFuture != null) {
      await _initFuture;
      return;
    }
    _autoScanInitFuture = initialize();
    try {
      await _autoScanInitFuture;
    } finally {
      _autoScanInitFuture = null;
    }
  }

  static Future<void> initialize() async {
    if (_isInitialized) return;
    if (_allModelsFailed) return;
    if (_initFuture != null) {
      await _initFuture;
      return;
    }
    _initFuture = _loadModel();
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  static Future<void> retryInitialize() async {
    _allModelsFailed = false;
    _isInitialized = false;
    _backend = _AntiSpoofBackend.none;
    _interpreter?.close();
    _interpreter = null;
    _initFuture = null;
    _autoScanInitFuture = null;
    await initializeForAutoScan();
  }

  static Future<void> _loadModel() async {
    try {
      Object? lastError;
      for (final assetPath in _assetCandidates) {
        try {
          final bundle = await rootBundle.load(assetPath);
          if (bundle.lengthInBytes < 10000) continue;

          if (kDebugMode) {
            debugPrint(
              '🔄 Loading anti-spoof ($assetPath, '
              '${(bundle.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MB)...',
            );
          }

          final bytes = bundle.buffer.asUint8List();
          final interpreter = await _tryOpenInterpreter(assetPath, bytes);
          if (interpreter == null) continue;

          _interpreter = interpreter;
          _backend = _detectBackend(interpreter, assetPath: assetPath);
          if (_backend == _AntiSpoofBackend.none) {
            interpreter.close();
            _interpreter = null;
            lastError = 'Unsupported model I/O for $assetPath';
            continue;
          }

          if (_backend == _AntiSpoofBackend.miniFas80 ||
              _backend == _AntiSpoofBackend.antispoofPrintReplay128) {
            _miniFasInputNormalized =
                interpreter.getInputTensor(0).type == TensorType.float32;
          }
          // MiniFASNetV1SE expects raw float32 pixel values [0,255] — no /255 normalization.
          if (_backend == _AntiSpoofBackend.miniFasV1SE80) {
            _miniFasInputNormalized = false;
          }

          if (kDebugMode) {
            final input = interpreter.getInputTensor(0);
            final outputs = interpreter.getOutputTensors();
            debugPrint(
              '✅ Anti-spoof loaded ($_backend) from $assetPath — '
              'input=${input.shape} outputs=${outputs.map((t) => t.shape).toList()}',
            );
          }

          _isInitialized = true;
          return;
        } catch (e) {
          lastError = e;
          _interpreter?.close();
          _interpreter = null;
        }
      }

      _markAllFailed('$lastError');
    } catch (e) {
      _markAllFailed('$e');
    }
  }

  static _AntiSpoofBackend _detectBackend(Interpreter interpreter, {String assetPath = ''}) {
    final shape = interpreter.getInputTensor(0).shape;
    if (kDebugMode) debugPrint('🔍 Anti-spoof model input shape: $shape');
    if (shape.length < 4) return _AntiSpoofBackend.none;

    final dims = shape.sublist(1); // drop batch dim
    final hasMiniFas = dims.contains(_miniFasSize);
    final hasBin128 = dims.contains(_antispoofBinSize);
    final hasFaceAntiSpoof = dims.contains(_faceAntiSpoofSize);
    final outputCount = interpreter.getOutputTensors().length;
    final outputShape = interpreter.getOutputTensor(0).shape;

    if (hasFaceAntiSpoof && outputCount >= 2) {
      return _AntiSpoofBackend.faceAntiSpoofing256;
    }
    // Print+replay 3-class model: [1,128,128,3] input + [1,3] output
    if (hasBin128 && outputShape.length == 2 && outputShape[1] == 3) {
      return _AntiSpoofBackend.antispoofPrintReplay128;
    }
    if (hasMiniFas) {
      // MiniFASNetV1SE: label==1 is live, scale=4.0, raw pixel values
      if (assetPath.contains('v1se') || assetPath.contains('V1SE')) {
        return _AntiSpoofBackend.miniFasV1SE80;
      }
      return _AntiSpoofBackend.miniFas80;
    }
    return _AntiSpoofBackend.none;
  }

  static Future<Interpreter?> _tryOpenInterpreter(
    String assetPath,
    Uint8List bytes,
  ) async {
    final loaders = <Future<Interpreter> Function()>[
      () async => Interpreter.fromBuffer(bytes),
      () async => Interpreter.fromAsset(assetPath),
      () async {
        final dir = await getTemporaryDirectory();
        final name = assetPath.split('/').last;
        final file = File('${dir.path}/$name');
        if (!await file.exists() || await file.length() != bytes.length) {
          await file.writeAsBytes(bytes, flush: true);
        }
        return Interpreter.fromFile(file);
      },
      () async => Interpreter.fromBuffer(
            bytes,
            options: InterpreterOptions()..threads = 1,
          ),
    ];

    for (final load in loaders) {
      try {
        return await load();
      } catch (_) {
        // try next loader
      }
    }
    return null;
  }

  static void _markAllFailed(String reason) {
    _allModelsFailed = true;
    _interpreter?.close();
    _interpreter = null;
    _backend = _AntiSpoofBackend.none;
    _isInitialized = false;
    if (kDebugMode) {
      debugPrint('❌ Failed to load anti-spoof model: $reason');
      debugPrint(
        'ℹ️ Using photo heuristics for spoof checks. '
        'Ensure assets/models/face_anti_spoofing.tflite is bundled '
        '(see tools/README_ANTI_SPOOF_MODEL.md).',
      );
    }
  }

  static Future<AntiSpoofResult?> checkSpoofFromCameraFrame(
    CameraImage image,
    Rect analysisBox, {
    InputImageRotation rotation = InputImageRotation.rotation270deg,
  }) async {
    try {
      if (!_isInitialized || _interpreter == null) {
        await ensureLoaded();
      }
      if (!_isInitialized || _interpreter == null) {
        return null;
      }
      if (!supportsStreamPad) {
        return null;
      }

      return switch (_backend) {
        _AntiSpoofBackend.miniFas80 => () {
            final patch = _miniFasPatchFromCamera(image, analysisBox) ??
                _miniFasPatchFromFaceCrop(image, analysisBox);
            if (patch == null) {
              if (kDebugMode) debugPrint('⚠️ Stream PAD: MiniFAS patch failed');
              return null;
            }
            return _runMiniFasInference(patch);
          }(),
        _AntiSpoofBackend.miniFasV1SE80 => () {
            final patch = _miniFasV1SEPatchFromCamera(image, analysisBox) ??
                _miniFasV1SEPatchFromFaceCrop(image, analysisBox);
            if (patch == null) {
              if (kDebugMode) debugPrint('⚠️ Stream PAD: MiniFASNetV1SE patch failed');
              return null;
            }
            return _runMiniFasV1SEInference(patch);
          }(),
        _AntiSpoofBackend.antispoofPrintReplay128 => () {
            final patch = _antispoofBinPatchFromCamera(image, analysisBox, rotation);
            if (patch == null) {
              if (kDebugMode) debugPrint('⚠️ Stream PAD: printReplay128 patch failed');
              return null;
            }
            return _runAntispoofBinInference(patch);
          }(),
        _ => null,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Stream anti-spoof failed: $e');
      return null;
    }
  }

  /// Small face ROI → RGB image (works for iOS BGRA + Android NV21).
  static img.Image? _cameraFaceCropRgb(CameraImage image, Rect faceRect) {
    try {
      if (image.width < 16 || image.height < 16) return null;
      final box = _scaledBox(
        image.width,
        image.height,
        faceRect,
        _miniFasBboxScale,
      );
      final left = box.left.floor().clamp(0, image.width - 2);
      final top = box.top.floor().clamp(0, image.height - 2);
      final right = box.right.ceil().clamp(left + 2, image.width);
      final bottom = box.bottom.ceil().clamp(top + 2, image.height);
      final cw = right - left;
      final ch = bottom - top;
      if (cw < 12 || ch < 12) return null;

      final out = img.Image(width: cw, height: ch);
      for (int j = 0; j < ch; j++) {
        for (int i = 0; i < cw; i++) {
          final rgb = _rgbAtCamera(image, left + i, top + j);
          out.setPixelRgb(i, j, rgb.$1, rgb.$2, rgb.$3);
        }
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ _cameraFaceCropRgb: $e');
      return null;
    }
  }

  static List<double>? _miniFasPatchFromFaceCrop(
    CameraImage image,
    Rect faceRect,
  ) {
    final crop = _cameraFaceCropRgb(image, faceRect);
    if (crop == null) return null;
    final resized = img.copyResize(crop, width: _miniFasSize, height: _miniFasSize);
    final patch = List<double>.filled(_miniFasSize * _miniFasSize * 3, 0.0);
    for (int j = 0; j < _miniFasSize; j++) {
      for (int i = 0; i < _miniFasSize; i++) {
        final p = resized.getPixel(i, j);
        final idx = (j * _miniFasSize + i) * 3;
        patch[idx] = p.r.toDouble();     // R
        patch[idx + 1] = p.g.toDouble(); // G
        patch[idx + 2] = p.b.toDouble(); // B
      }
    }
    return patch;
  }

  static List<double>? _faceAntiSpoofPatchFromImage(
    img.Image image,
    Rect faceRect,
  ) {
    final box = _scaledBox(
      image.width,
      image.height,
      faceRect,
      2.2,
    );
    final x = box.left.floor().clamp(0, image.width - 1);
    final y = box.top.floor().clamp(0, image.height - 1);
    final cw = box.width.floor().clamp(1, image.width - x);
    final ch = box.height.floor().clamp(1, image.height - y);
    if (cw < 12 || ch < 12) return null;
    final crop = img.copyCrop(image, x: x, y: y, width: cw, height: ch);
    return _rgbPatchFullFrame(crop, _faceAntiSpoofSize);
  }

/// Auto-scan capture: TFLite PAD only — no heuristics.
  /// MiniFAS 80×80 is primary; 256×256 is fallback.
  /// If model not loaded → allow (don't block on guesswork).
  static Future<AntiSpoofResult> checkSpoofForAutoScan(String photoPath) async {
    await ensureLoaded();

    if (isModelLoaded) {
      final pad = await checkSpoof(photoPath);
      if (kDebugMode) {
        debugPrint(
          '📸 PAD: isReal=${pad.isReal} '
          'conf=${(pad.confidence * 100).toStringAsFixed(0)}% — ${pad.reason}',
        );
      }
      return pad;
    }

    // Model not available — allow through rather than false-block.
    return AntiSpoofResult(
      isReal: true,
      confidence: 0.5,
      reason: 'PAD model not loaded — allowed',
    );
  }

  static Future<AntiSpoofResult> checkSpoof(String photoPath) async {
    try {
      if (!_isInitialized || _interpreter == null) {
        await ensureLoaded();
      }

      if (_isInitialized && _interpreter != null) {
        final bytes = await File(photoPath).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          return AntiSpoofResult(
            isReal: false,
            confidence: 0.0,
            reason: 'Failed to decode image',
          );
        }

        final faceBox = Rect.fromCenter(
          center: Offset(decoded.width / 2, decoded.height / 2),
          width: decoded.width * 0.45,
          height: decoded.height * 0.55,
        );

        return switch (_backend) {
          _AntiSpoofBackend.faceAntiSpoofing256 => () {
              final patch = _faceAntiSpoofPatchFromImage(decoded, faceBox) ??
                  _rgbPatchFullFrame(decoded, _faceAntiSpoofSize);
              if (patch == null) {
                return AntiSpoofResult(
                  isReal: false,
                  confidence: 0.0,
                  reason: 'Could not prepare face patch',
                );
              }
              return _runFaceAntiSpoofInference(patch);
            }(),
          _AntiSpoofBackend.miniFas80 => () {
              final patch = _miniFasPatchFromImage(decoded, faceBox);
              if (patch == null) {
                return AntiSpoofResult(
                  isReal: false,
                  confidence: 0.0,
                  reason: 'Could not prepare face patch',
                );
              }
              return _runMiniFasInference(patch);
            }(),
          _AntiSpoofBackend.miniFasV1SE80 => () {
              final patch = _miniFasV1SEPatchFromImage(decoded, faceBox);
              if (patch == null) {
                return AntiSpoofResult(
                  isReal: false,
                  confidence: 0.0,
                  reason: 'Could not prepare face patch',
                );
              }
              return _runMiniFasV1SEInference(patch);
            }(),
          _AntiSpoofBackend.antispoofPrintReplay128 => () {
              final patch = _antispoofBinPatchFromImage(decoded, faceBox);
              if (patch == null) {
                return AntiSpoofResult(
                  isReal: false,
                  confidence: 0.0,
                  reason: 'Could not prepare face patch',
                );
              }
              return _runAntispoofBinInference(patch);
            }(),
          _ => AntiSpoofResult(
              isReal: true,
              confidence: 0.5,
              reason: 'Unknown backend — allowed',
            ),
        };
      }

      return AntiSpoofResult(
        isReal: true,
        confidence: 0.5,
        reason: 'Model not ready — allowed',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Anti-spoof check failed: $e');
      return AntiSpoofResult(
        isReal: true,
        confidence: 0.5,
        reason: 'PAD error — allowed',
      );
    }
  }


  /// 256×256 RGB in [0, 1] — matches Android FaceAntiSpoofing.java (full frame resize).
  static AntiSpoofResult _runFaceAntiSpoofInference(List<double> rgb01Patch) {
    final input = Float32List(_faceAntiSpoofSize * _faceAntiSpoofSize * 3);
    for (int i = 0; i < rgb01Patch.length; i++) {
      input[i] = rgb01Patch[i].toDouble();
    }

    final inputTensor = input.reshape([1, _faceAntiSpoofSize, _faceAntiSpoofSize, 3]);
    final out0 = Float32List(8).reshape([1, 8]);
    final out1 = Float32List(8).reshape([1, 8]);
    _interpreter!.runForMultipleInputs(
      [inputTensor],
      {0: out0, 1: out1},
    );

    final leafScore1 = _faceAntiSpoofLeafScore1(out0, out1);
    final leafScore1Swapped = _faceAntiSpoofLeafScore1(out1, out0);
    final routeScore = (out0[0][_faceAntiSpoofRouteIndex] as num).toDouble();

    // Primary metric from reference Android code; swapped used if outputs are reversed.
    final score = math.min(leafScore1, leafScore1Swapped);
    final isReal = score <= _faceAntiSpoofAttackThreshold;
    final confidence = isReal
        ? (1.0 - (score / _faceAntiSpoofAttackThreshold)).clamp(0.0, 1.0)
        : (score / (_faceAntiSpoofAttackThreshold * 2)).clamp(0.0, 1.0);

    if (kDebugMode) {
      debugPrint(
        '📊 FaceAntiSpoof: leaf1=${leafScore1.toStringAsFixed(3)} '
        'leaf1s=${leafScore1Swapped.toStringAsFixed(3)} '
        'route=$routeScore score=$score isReal=$isReal',
      );
    }

    return AntiSpoofResult(
      isReal: isReal,
      confidence: confidence,
      reason: isReal
          ? 'Live face detected ✅'
          : 'Screen/photo/video spoof detected ❌',
    );
  }

  static double _faceAntiSpoofLeafScore1(List clss, List mask) {
    var score = 0.0;
    for (var i = 0; i < 8; i++) {
      score += (clss[0][i] as num).abs() * (mask[0][i] as num).toDouble();
    }
    return score;
  }

  static List<double>? _rgbPatchFullFrame(img.Image image, int size) {
    final resized = img.copyResize(image, width: size, height: size);
    final patch = List<double>.filled(size * size * 3, 0.0);
    for (int j = 0; j < size; j++) {
      for (int i = 0; i < size; i++) {
        final pixel = resized.getPixel(i, j);
        final idx = (j * size + i) * 3;
        patch[idx] = pixel.r / 255.0;
        patch[idx + 1] = pixel.g / 255.0;
        patch[idx + 2] = pixel.b / 255.0;
      }
    }
    return patch;
  }

  static AntiSpoofResult _runMiniFasInference(List<double> bgrPatch) {
    final input = Float32List(_miniFasSize * _miniFasSize * 3);
    for (int i = 0; i < bgrPatch.length; i++) {
      input[i] = _miniFasInputNormalized ? (bgrPatch[i] / 255.0) : bgrPatch[i];
    }

    final inputTensor = input.reshape([1, _miniFasSize, _miniFasSize, 3]);
    final output = Float32List(3).reshape([1, 3]);
    _interpreter!.run(inputTensor, output);

    final logits = [
      (output[0][0] as num).toDouble(),
      (output[0][1] as num).toDouble(),
      (output[0][2] as num).toDouble(),
    ];
    final probs = _softmax3(logits);
    // Class mapping for this onnx2tf-converted MiniFASNetV2:
    // index 0 = spoof type A, index 1 = spoof type B, index 2 = live.
    final liveProb = probs[2];
    final label = _argMax(probs);
    final isReal = label == 2 && liveProb >= liveThreshold;

    if (kDebugMode) {
      debugPrint(
        '📊 MiniFAS: live=${(liveProb * 100).toStringAsFixed(1)}% '
        'probs=[${probs.map((p) => (p * 100).toStringAsFixed(0)).join(", ")}]% '
        'label=$label isReal=$isReal',
      );
    }

    return AntiSpoofResult(
      isReal: isReal,
      confidence: liveProb,
      reason: isReal
          ? 'Live face detected ✅'
          : 'Screen/photo/video spoof detected ❌',
    );
  }

  // ── MiniFASNetV1SE 80×80 (scale=4.0, BGR [0-255], label==1 → live) ──────────

  /// Crop + resize with scale=4.0, returns BGR raw [0,255].
  static List<double>? _miniFasV1SEPatchFromImage(img.Image image, Rect faceRect) {
    final box = _scaledBox(image.width, image.height, faceRect, _miniFasV1SEBboxScale);
    final srcW = box.width;
    final srcH = box.height;
    if (srcW < 8 || srcH < 8) return null;
    final patch = List<double>.filled(_miniFasSize * _miniFasSize * 3, 0.0);
    for (int j = 0; j < _miniFasSize; j++) {
      for (int i = 0; i < _miniFasSize; i++) {
        final sx = (box.left + (i + 0.5) * srcW / _miniFasSize).floor().clamp(0, image.width - 1);
        final sy = (box.top + (j + 0.5) * srcH / _miniFasSize).floor().clamp(0, image.height - 1);
        final pixel = image.getPixel(sx, sy);
        final idx = (j * _miniFasSize + i) * 3;
        patch[idx]     = pixel.b.toDouble(); // BGR
        patch[idx + 1] = pixel.g.toDouble();
        patch[idx + 2] = pixel.r.toDouble();
      }
    }
    return patch;
  }

  static List<double>? _miniFasV1SEPatchFromCamera(CameraImage image, Rect faceRect) {
    final box = _scaledBox(image.width, image.height, faceRect, _miniFasV1SEBboxScale);
    final srcW = box.width;
    final srcH = box.height;
    if (srcW < 8 || srcH < 8) return null;
    final patch = List<double>.filled(_miniFasSize * _miniFasSize * 3, 0.0);
    for (int j = 0; j < _miniFasSize; j++) {
      for (int i = 0; i < _miniFasSize; i++) {
        final sx = box.left + (i + 0.5) * srcW / _miniFasSize;
        final sy = box.top + (j + 0.5) * srcH / _miniFasSize;
        final rgb = _rgbAtCamera(image, sx.floor(), sy.floor());
        final idx = (j * _miniFasSize + i) * 3;
        patch[idx]     = rgb.$3.toDouble(); // BGR
        patch[idx + 1] = rgb.$2.toDouble();
        patch[idx + 2] = rgb.$1.toDouble();
      }
    }
    return patch;
  }

  static List<double>? _miniFasV1SEPatchFromFaceCrop(CameraImage image, Rect faceRect) {
    final crop = _cameraFaceCropRgb(image, faceRect);
    if (crop == null) return null;
    final resized = img.copyResize(crop, width: _miniFasSize, height: _miniFasSize);
    final patch = List<double>.filled(_miniFasSize * _miniFasSize * 3, 0.0);
    for (int j = 0; j < _miniFasSize; j++) {
      for (int i = 0; i < _miniFasSize; i++) {
        final p = resized.getPixel(i, j);
        final idx = (j * _miniFasSize + i) * 3;
        patch[idx]     = p.b.toDouble(); // BGR
        patch[idx + 1] = p.g.toDouble();
        patch[idx + 2] = p.r.toDouble();
      }
    }
    return patch;
  }

  /// MiniFASNetV1SE inference:
  /// - Input: BGR float32 raw [0,255] — no normalization
  /// - Output: [1,3] logits → softmax → label==1 is live (per inference_tflite.py)
  /// - Bbox scale 4.0 matches the 4_0_0 in the original model filename
  static const double _miniFasV1SELiveThreshold = 0.50;

  static AntiSpoofResult _runMiniFasV1SEInference(List<double> bgrPatch) {
    final input = Float32List(_miniFasSize * _miniFasSize * 3);
    for (int i = 0; i < bgrPatch.length; i++) {
      input[i] = bgrPatch[i]; // raw pixel values, no /255
    }
    final inputTensor = input.reshape([1, _miniFasSize, _miniFasSize, 3]);
    final output = Float32List(3).reshape([1, 3]);
    _interpreter!.run(inputTensor, output);

    final logits = [
      (output[0][0] as num).toDouble(),
      (output[0][1] as num).toDouble(),
      (output[0][2] as num).toDouble(),
    ];
    final probs = _softmax3(logits);
    // label==1 → live (from inference_tflite.py in the source repo)
    final liveProb = probs[1];
    final label = _argMax(probs);
    final isReal = label == 1 && liveProb >= _miniFasV1SELiveThreshold;

    if (kDebugMode) {
      debugPrint(
        '📊 MiniFASNetV1SE: live[1]=${(liveProb * 100).toStringAsFixed(1)}% '
        'probs=[${probs.map((p) => (p * 100).toStringAsFixed(0)).join(", ")}]% '
        'label=$label isReal=$isReal',
      );
    }

    return AntiSpoofResult(
      isReal: isReal,
      confidence: liveProb,
      reason: isReal ? 'Live face detected ✅' : 'Screen/photo/video spoof detected ❌',
    );
  }

  static List<double>? _miniFasPatchFromCamera(CameraImage image, Rect faceRect) {
    final box = _scaledBox(
      image.width,
      image.height,
      faceRect,
      _miniFasBboxScale,
    );
    final patch = List<double>.filled(_miniFasSize * _miniFasSize * 3, 0.0);
    final srcW = box.width;
    final srcH = box.height;
    if (srcW < 8 || srcH < 8) return null;

    for (int j = 0; j < _miniFasSize; j++) {
      for (int i = 0; i < _miniFasSize; i++) {
        final sx = box.left + (i + 0.5) * srcW / _miniFasSize;
        final sy = box.top + (j + 0.5) * srcH / _miniFasSize;
        final rgb = _rgbAtCamera(image, sx.floor(), sy.floor());
        final idx = (j * _miniFasSize + i) * 3;
        patch[idx] = rgb.$1.toDouble();     // R
        patch[idx + 1] = rgb.$2.toDouble(); // G
        patch[idx + 2] = rgb.$3.toDouble(); // B
      }
    }
    return patch;
  }

  static List<double>? _miniFasPatchFromImage(img.Image image, Rect faceRect) {
    final box = _scaledBox(
      image.width,
      image.height,
      faceRect,
      _miniFasBboxScale,
    );
    final patch = List<double>.filled(_miniFasSize * _miniFasSize * 3, 0.0);
    final srcW = box.width;
    final srcH = box.height;
    if (srcW < 8 || srcH < 8) return null;

    for (int j = 0; j < _miniFasSize; j++) {
      for (int i = 0; i < _miniFasSize; i++) {
        final sx = (box.left + (i + 0.5) * srcW / _miniFasSize).floor().clamp(0, image.width - 1);
        final sy = (box.top + (j + 0.5) * srcH / _miniFasSize).floor().clamp(0, image.height - 1);
        final pixel = image.getPixel(sx, sy);
        final idx = (j * _miniFasSize + i) * 3;
        patch[idx] = pixel.r.toDouble();     // R
        patch[idx + 1] = pixel.g.toDouble(); // G
        patch[idx + 2] = pixel.b.toDouble(); // B
      }
    }
    return patch;
  }

  // ── AntispoofBin 128×128 ──────────────────────────────────────────────────

  /// Extract 128×128 patch from the camera YUV buffer, correcting for
  /// camera rotation so the model always receives an upright face crop.
  static List<double>? _antispoofBinPatchFromCamera(
    CameraImage image,
    Rect analysisBox,
    InputImageRotation rotation,
  ) {
    // Analysis dimensions: transposed for 90°/270° rotations
    final transposed = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final analysisW = transposed ? image.height : image.width;
    final analysisH = transposed ? image.width : image.height;

    final box = _scaledBox(analysisW, analysisH, analysisBox, _antispoofBinBboxScale);
    final srcW = box.width;
    final srcH = box.height;
    if (srcW < 8 || srcH < 8) return null;

    if (kDebugMode) {
      final ax0 = box.left + 0.5 * srcW / _antispoofBinSize;
      final ay0 = box.top + 0.5 * srcH / _antispoofBinSize;
      final (bx0, by0) = _analysisToBuffer(ax0, ay0, image.width, image.height, rotation);
      debugPrint('🔲 PAD crop: rot=$rotation buf=${image.width}×${image.height} '
          'analysisBox=$analysisBox scaledBox=$box '
          'pixel0_analysis=(${ax0.toStringAsFixed(0)},${ay0.toStringAsFixed(0)}) '
          'pixel0_buffer=($bx0,$by0)');
    }
    final patch = List<double>.filled(_antispoofBinSize * _antispoofBinSize * 3, 0.0);
    for (int j = 0; j < _antispoofBinSize; j++) {
      for (int i = 0; i < _antispoofBinSize; i++) {
        final ax = box.left + (i + 0.5) * srcW / _antispoofBinSize;
        final ay = box.top + (j + 0.5) * srcH / _antispoofBinSize;
        final (bx, by) = _analysisToBuffer(ax, ay, image.width, image.height, rotation);
        final rgb = _rgbAtCamera(image, bx, by);
        final idx = (j * _antispoofBinSize + i) * 3;
        patch[idx]     = rgb.$1.toDouble(); // R
        patch[idx + 1] = rgb.$2.toDouble(); // G
        patch[idx + 2] = rgb.$3.toDouble(); // B
      }
    }
    return patch;
  }

  /// Map an analysis-space (upright) point to YUV buffer coordinates.
  static (int, int) _analysisToBuffer(
    double ax,
    double ay,
    int bufW,
    int bufH,
    InputImageRotation rotation,
  ) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        // Buffer rotated 90° CW to form analysis image
        // analysis(ax,ay) → buffer(ay, bufH-1-ax)
        return (
          ay.round().clamp(0, bufW - 1),
          (bufH - 1 - ax).round().clamp(0, bufH - 1),
        );
      case InputImageRotation.rotation270deg:
        // Buffer rotated 270° CW to form analysis image
        // analysis(ax,ay) → buffer(bufW-1-ay, ax)
        return (
          (bufW - 1 - ay).round().clamp(0, bufW - 1),
          ax.round().clamp(0, bufH - 1),
        );
      case InputImageRotation.rotation180deg:
        return (
          (bufW - 1 - ax).round().clamp(0, bufW - 1),
          (bufH - 1 - ay).round().clamp(0, bufH - 1),
        );
      default: // rotation0deg
        return (
          ax.round().clamp(0, bufW - 1),
          ay.round().clamp(0, bufH - 1),
        );
    }
  }

  static List<double>? _antispoofBinPatchFromImage(img.Image image, Rect faceRect) {
    final box = _scaledBox(
      image.width,
      image.height,
      faceRect,
      _antispoofBinBboxScale,
    );
    final srcW = box.width;
    final srcH = box.height;
    if (srcW < 8 || srcH < 8) return null;

    final patch = List<double>.filled(_antispoofBinSize * _antispoofBinSize * 3, 0.0);
    for (int j = 0; j < _antispoofBinSize; j++) {
      for (int i = 0; i < _antispoofBinSize; i++) {
        final sx = (box.left + (i + 0.5) * srcW / _antispoofBinSize)
            .floor()
            .clamp(0, image.width - 1);
        final sy = (box.top + (j + 0.5) * srcH / _antispoofBinSize)
            .floor()
            .clamp(0, image.height - 1);
        final pixel = image.getPixel(sx, sy);
        final idx = (j * _antispoofBinSize + i) * 3;
        patch[idx]     = pixel.r.toDouble(); // R
        patch[idx + 1] = pixel.g.toDouble(); // G
        patch[idx + 2] = pixel.b.toDouble(); // B
      }
    }
    return patch;
  }

  // Print+replay 128×128: class 0=live, class 1=print spoof, class 2=replay spoof.
  // Training: cv2 BGR + ImageNet norm mean=[0.406,0.456,0.485] std=[0.225,0.224,0.229].
  static AntiSpoofResult _runAntispoofBinInference(List<double> rgbPatch) {
    if (kDebugMode && rgbPatch.isNotEmpty) {
      final mean = rgbPatch.reduce((a, b) => a + b) / rgbPatch.length;
      final max = rgbPatch.reduce(math.max);
      final r0 = rgbPatch[0].round();
      final g0 = rgbPatch.length > 1 ? rgbPatch[1].round() : 0;
      final b0 = rgbPatch.length > 2 ? rgbPatch[2].round() : 0;
      debugPrint('🎨 PAD raw: mean=${mean.toStringAsFixed(1)} max=${max.toStringAsFixed(0)} '
          'pixel0=(R=$r0,G=$g0,B=$b0)');
    }
    final input = Float32List(_antispoofBinSize * _antispoofBinSize * 3);
    const bMean = 0.406; const bStd = 0.225;
    const gMean = 0.456; const gStd = 0.224;
    const rMean = 0.485; const rStd = 0.229;
    final n = _antispoofBinSize * _antispoofBinSize;
    for (int i = 0; i < n; i++) {
      final r = rgbPatch[i * 3];
      final g = rgbPatch[i * 3 + 1];
      final b = rgbPatch[i * 3 + 2];
      input[i * 3]     = (b / 255.0 - bMean) / bStd; // B → channel 0
      input[i * 3 + 1] = (g / 255.0 - gMean) / gStd; // G → channel 1
      input[i * 3 + 2] = (r / 255.0 - rMean) / rStd; // R → channel 2
    }
    if (kDebugMode) {
      double normSum = 0;
      for (int k = 0; k < input.length; k++) {
        normSum += input[k];
      }
      final normMean = normSum / input.length;
      final mid = input.length ~/ 2;
      debugPrint('🧪 PAD normalized: mean=${normMean.toStringAsFixed(3)} '
          'pixel0=(B=${input[0].toStringAsFixed(2)},G=${input[1].toStringAsFixed(2)},R=${input[2].toStringAsFixed(2)}) '
          'mid=(${input[mid].toStringAsFixed(2)},${input[mid+1].toStringAsFixed(2)},${input[mid+2].toStringAsFixed(2)})');
    }
    // Log raw bytes of first 3 floats to verify what actually reaches the model
    if (kDebugMode) {
      final bytes = input.buffer.asUint8List(0, 12);
      debugPrint('🔢 PAD bytes[0..11]: ${bytes.map((b) => b.toRadixString(16).padLeft(2,'0')).join(' ')}');
    }
    // runForMultipleInputs with explicit input/output map — most reliable API
    final outputMap = <int, Object>{0: [[0.0, 0.0, 0.0]]};
    _interpreter!.runForMultipleInputs([input.buffer.asUint8List()], outputMap);
    final outList = outputMap[0] as List;

    final logits = [
      (outList[0][0] as num).toDouble(),
      (outList[0][1] as num).toDouble(),
      (outList[0][2] as num).toDouble(),
    ];
    if (kDebugMode) {
      debugPrint('🧪 PAD logits: [${logits[0].toStringAsFixed(2)}, '
          '${logits[1].toStringAsFixed(2)}, ${logits[2].toStringAsFixed(2)}]');
    }
    final probs = _softmax3(logits);
    // Python-verified: class 0=live, class 1=print spoof, class 2=replay spoof
    final liveProb = probs[0];
    final label = _argMax(probs);
    const liveThreshold = 0.50;
    final isReal = label == 0 && liveProb >= liveThreshold;

    if (kDebugMode) {
      debugPrint(
        '📊 PrintReplay128: live=${(liveProb * 100).toStringAsFixed(1)}% '
        'probs=[${probs.map((p) => (p * 100).toStringAsFixed(0)).join(", ")}]% '
        'label=$label isReal=$isReal',
      );
    }

    return AntiSpoofResult(
      isReal: isReal,
      confidence: liveProb,
      reason: isReal ? 'Live face detected ✅' : 'Screen/photo/video spoof detected ❌',
    );
  }

  static Rect _scaledBox(int srcW, int srcH, Rect box, double bboxScale) {
    final w = box.width;
    final h = box.height;
    final scale = math.min(
      (srcH - 1) / h,
      math.min((srcW - 1) / w, bboxScale),
    );
    final newW = w * scale;
    final newH = h * scale;
    final cx = w / 2 + box.left;
    final cy = h / 2 + box.top;
    var left = cx - newW / 2;
    var top = cy - newH / 2;
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    var right = left + newW;
    var bottom = top + newH;
    if (right > srcW - 1) {
      right = (srcW - 1).toDouble();
      left = right - newW;
    }
    if (bottom > srcH - 1) {
      bottom = (srcH - 1).toDouble();
      top = bottom - newH;
    }
    return Rect.fromLTRB(
      left.clamp(0.0, srcW.toDouble()),
      top.clamp(0.0, srcH.toDouble()),
      right.clamp(0.0, srcW.toDouble()),
      bottom.clamp(0.0, srcH.toDouble()),
    );
  }

  static (int, int, int) _rgbAtCamera(CameraImage image, int x, int y) {
    x = x.clamp(0, image.width - 1);
    y = y.clamp(0, image.height - 1);

    final plane = image.planes.first;
    final bpp = plane.bytesPerPixel ?? 1;

    if (bpp >= 3 && image.planes.length == 1) {
      final bytes = plane.bytes;
      final offset = y * plane.bytesPerRow + x * bpp;
      if (offset + 2 < bytes.length) {
        final b = bytes[offset];
        final g = bytes[offset + 1];
        final r = bytes[offset + 2];
        return (r, g, b);
      }
    }

    if (image.planes.length >= 3) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      final yRow = y * yPlane.bytesPerRow + x;
      if (yRow >= yPlane.bytes.length) return (128, 128, 128);
      final yVal = yPlane.bytes[yRow];

      final uvX = x ~/ 2;
      final uvY = y ~/ 2;
      // bytesPerPixel=2 on NV21 (interleaved VU) — must multiply by bpp
      final uBpp = uPlane.bytesPerPixel ?? 1;
      final vBpp = vPlane.bytesPerPixel ?? 1;
      final uRow = uvY * uPlane.bytesPerRow + uvX * uBpp;
      final vRow = uvY * vPlane.bytesPerRow + uvX * vBpp;
      final u = uRow < uPlane.bytes.length ? uPlane.bytes[uRow] : 128;
      final v = vRow < vPlane.bytes.length ? vPlane.bytes[vRow] : 128;

      final c = yVal - 16;
      final d = u - 128;
      final e = v - 128;
      final r = (298 * c + 409 * e + 128) ~/ 256;
      final g = (298 * c - 100 * d - 208 * e + 128) ~/ 256;
      final b = (298 * c + 516 * d + 128) ~/ 256;
      return (
        r.clamp(0, 255),
        g.clamp(0, 255),
        b.clamp(0, 255),
      );
    }

    final lum = _lumaAtCamera(image, x, y);
    return (lum, lum, lum);
  }

  static int _lumaAtCamera(CameraImage image, int x, int y) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final bpp = plane.bytesPerPixel ?? 1;
    final offset = y * plane.bytesPerRow + x * bpp;
    if (offset < 0 || offset >= bytes.length) return 0;
    if (bpp == 1) return bytes[offset];
    if (offset + 2 < bytes.length) {
      final b = bytes[offset];
      final g = bytes[offset + 1];
      final r = bytes[offset + 2];
      return ((0.299 * r) + (0.587 * g) + (0.114 * b)).round();
    }
    return bytes[offset];
  }

  static List<double> _softmax3(List<double> x) {
    final maxV = x.reduce(math.max);
    final exps = x.map((v) => math.exp(v - maxV)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  static int _argMax(List<double> values) {
    var best = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] > values[best]) best = i;
    }
    return best;
  }

  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _backend = _AntiSpoofBackend.none;
  }
}

class AntiSpoofResult {
  final bool isReal;
  final double confidence;
  final String reason;

  AntiSpoofResult({
    required this.isReal,
    required this.confidence,
    required this.reason,
  });
}
