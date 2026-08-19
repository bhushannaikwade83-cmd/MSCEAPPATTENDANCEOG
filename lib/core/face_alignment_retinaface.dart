import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:math';

/// RetinaFace-compatible face alignment (106 landmarks)
class RetinaFaceAlignment {
  /// Align face using RetinaFace's 106 landmarks (NOT MediaPipe 468)
  /// Returns aligned 112×112 face for ArcFace
  static Future<img.Image?> alignFace({
    required img.Image image,
    required List<dynamic> landmarks,  // RetinaFace 106 landmarks
  }) async {
    try {
      // RetinaFace gives 106 landmarks (5 key face landmarks for alignment)
      // Key indices in RetinaFace:
      // [0-1]: right eye
      // [2-3]: left eye
      // [4-5]: nose
      // [6-7]: right mouth corner
      // [8-9]: left mouth corner

      if (landmarks.length < 10) {
        print('❌ Insufficient landmarks: ${landmarks.length}');
        return null;
      }

      // Extract 5 key points from RetinaFace (not 263!)
      final rightEye = _toPoint(landmarks, 0);    // landmarks[0-1]
      final leftEye = _toPoint(landmarks, 2);     // landmarks[2-3]
      final nose = _toPoint(landmarks, 4);        // landmarks[4-5]
      final rightMouth = _toPoint(landmarks, 6);  // landmarks[6-7]
      final leftMouth = _toPoint(landmarks, 8);   // landmarks[8-9]

      print('✅ Extracted 5 key points:');
      print('   Right eye: ${rightEye.toString()}');
      print('   Left eye:  ${leftEye.toString()}');
      print('   Nose:      ${nose.toString()}');
      print('   Right mouth: ${rightMouth.toString()}');
      print('   Left mouth:  ${leftMouth.toString()}');

      // ArcFace standard: use left eye and right eye for alignment
      final srcPoints = [leftEye, rightEye];
      final dstPoints = [
        Point(38.2946, 51.6963),  // Standard ArcFace left eye position
        Point(73.5318, 51.5014),  // Standard ArcFace right eye position
      ];

      // Calculate similarity transform
      final transform = _estimateSimilarityTransform(srcPoints, dstPoints);
      if (transform == null) {
        print('❌ Failed to calculate transform');
        return null;
      }

      print('✅ Similarity transform calculated');

      // Apply transform to get 112×112 aligned face
      final aligned = _applyTransform(image, transform, 112, 112);

      if (aligned == null) {
        print('❌ Transform application failed');
        return null;
      }

      print('✅ Face aligned to 112×112');
      return aligned;
    } catch (e) {
      print('❌ Alignment error: $e');
      return null;
    }
  }

  /// Convert landmark pair to Point
  static Point<double> _toPoint(List<dynamic> landmarks, int startIdx) {
    return Point<double>(
      (landmarks[startIdx] as num).toDouble(),
      (landmarks[startIdx + 1] as num).toDouble(),
    );
  }

  /// Estimate similarity transform (rotation, scale, translation)
  static Matrix3? _estimateSimilarityTransform(
    List<Point<double>> src,
    List<Point<double>> dst,
  ) {
    try {
      if (src.length != dst.length || src.isEmpty) return null;

      // Calculate centroids
      double srcMeanX = 0, srcMeanY = 0, dstMeanX = 0, dstMeanY = 0;
      for (int i = 0; i < src.length; i++) {
        srcMeanX += src[i].x;
        srcMeanY += src[i].y;
        dstMeanX += dst[i].x;
        dstMeanY += dst[i].y;
      }
      srcMeanX /= src.length;
      srcMeanY /= src.length;
      dstMeanX /= dst.length;
      dstMeanY /= dst.length;

      // Center points
      List<Point<double>> srcCentered = [
        for (var p in src) Point(p.x - srcMeanX, p.y - srcMeanY),
      ];
      List<Point<double>> dstCentered = [
        for (var p in dst) Point(p.x - dstMeanX, p.y - dstMeanY),
      ];

      // Calculate scale
      double srcScale = 0, dstScale = 0;
      for (int i = 0; i < srcCentered.length; i++) {
        srcScale += srcCentered[i].x * srcCentered[i].x +
            srcCentered[i].y * srcCentered[i].y;
        dstScale += dstCentered[i].x * dstCentered[i].x +
            dstCentered[i].y * dstCentered[i].y;
      }
      srcScale = sqrt(srcScale / srcCentered.length);
      dstScale = sqrt(dstScale / dstCentered.length);

      if (srcScale < 1e-6) return null;
      final scale = dstScale / srcScale;

      // Normalize
      for (int i = 0; i < srcCentered.length; i++) {
        srcCentered[i] = Point(srcCentered[i].x / srcScale, srcCentered[i].y / srcScale);
      }

      // Calculate rotation (Kabsch algorithm simplified)
      double h11 = 0, h12 = 0, h21 = 0, h22 = 0;
      for (int i = 0; i < srcCentered.length; i++) {
        h11 += srcCentered[i].x * dstCentered[i].x;
        h12 += srcCentered[i].x * dstCentered[i].y;
        h21 += srcCentered[i].y * dstCentered[i].x;
        h22 += srcCentered[i].y * dstCentered[i].y;
      }

      final det = sqrt(h11 * h11 + h12 * h12);
      if (det < 1e-6) return null;

      double a = h11 / det;
      double b = h12 / det;

      // Return similarity transform matrix
      return Matrix3(
        scale * a, scale * b, dstMeanX - (scale * a * srcMeanX - scale * b * srcMeanY),
        -scale * b, scale * a, dstMeanY - (-scale * b * srcMeanX - scale * a * srcMeanY),
        0, 0, 1,
      );
    } catch (e) {
      print('❌ Transform estimation error: $e');
      return null;
    }
  }

  /// Apply affine transform to image
  static img.Image? _applyTransform(
    img.Image src,
    Matrix3 transform,
    int outWidth,
    int outHeight,
  ) {
    try {
      final dst = img.Image(width: outWidth, height: outHeight);

      for (int y = 0; y < outHeight; y++) {
        for (int x = 0; x < outWidth; x++) {
          // Inverse transform
          final invX = transform.entry(0, 0) * x + transform.entry(0, 1) * y + transform.entry(0, 2);
          final invY = transform.entry(1, 0) * x + transform.entry(1, 1) * y + transform.entry(1, 2);

          if (invX >= 0 && invX < src.width - 1 && invY >= 0 && invY < src.height - 1) {
            // Bilinear interpolation
            final x0 = invX.floor();
            final y0 = invY.floor();
            final fx = invX - x0;
            final fy = invY - y0;

            final p00 = src.getPixel(x0, y0);
            final p10 = src.getPixel(x0 + 1, y0);
            final p01 = src.getPixel(x0, y0 + 1);
            final p11 = src.getPixel(x0 + 1, y0 + 1);

            final r = ((1 - fx) * (1 - fy) * p00.r +
                    fx * (1 - fy) * p10.r +
                    (1 - fx) * fy * p01.r +
                    fx * fy * p11.r)
                .toInt();
            final g = ((1 - fx) * (1 - fy) * p00.g +
                    fx * (1 - fy) * p10.g +
                    (1 - fx) * fy * p01.g +
                    fx * fy * p11.g)
                .toInt();
            final b = ((1 - fx) * (1 - fy) * p00.b +
                    fx * (1 - fy) * p10.b +
                    (1 - fx) * fy * p01.b +
                    fx * fy * p11.b)
                .toInt();

            dst.setPixelRgba(x, y, r, g, b, 255);
          }
        }
      }

      return dst;
    } catch (e) {
      print('❌ Transform application error: $e');
      return null;
    }
  }
}

/// Simple 3x3 Matrix for transformation
class Matrix3 {
  final List<List<double>> _data;

  Matrix3(
    double m00, double m01, double m02,
    double m10, double m11, double m12,
    double m20, double m21, double m22,
  ) : _data = [
    [m00, m01, m02],
    [m10, m11, m12],
    [m20, m21, m22],
  ];

  double entry(int row, int col) => _data[row][col];
}
