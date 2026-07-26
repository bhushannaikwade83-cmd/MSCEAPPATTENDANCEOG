import 'package:flutter/material.dart';
import '../../services/distance_check_service.dart';

/// Live camera overlay — guide circle + distance feedback (green / yellow / red).
class DistanceCheckOverlay extends StatelessWidget {
  final DistanceStatus status;
  final double ratio;
  final double confidence;
  final DistanceProfile profile;
  final String? scanInstruction;

  const DistanceCheckOverlay({
    super.key,
    required this.status,
    required this.ratio,
    required this.confidence,
    this.profile = DistanceProfile.attendance,
    this.scanInstruction,
  });

  bool get _isRegistration => profile == DistanceProfile.registration;

  double _guideDiameter(double screenWidth) =>
      screenWidth * (_isRegistration ? 0.84 : 0.8);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final circleColor = _getCircleColor();
    final message = _getMessage();
    final guideSize = _guideDiameter(size.width);

    return Stack(
      children: [
        Center(
          child: Container(
            width: guideSize,
            height: guideSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: circleColor, width: 4),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_getIcon(), style: const TextStyle(fontSize: 44)),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: circleColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                  if (status == DistanceStatus.perfect)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(circleColor),
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        Positioned(
          top: 140,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DistanceCheckService.recommendedDistanceShortFor(profile),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Distance Status',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ratio: ${ratio.toStringAsFixed(3)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        Positioned(
          bottom: 160,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Too Far',
                      style: TextStyle(color: Colors.yellow[300], fontSize: 12),
                    ),
                    Text(
                      'Perfect',
                      style: TextStyle(
                        color: Colors.green[300],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Too Close',
                      style: TextStyle(color: Colors.red[300], fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _getRatioPosition(),
                    minHeight: 8,
                    backgroundColor: Colors.grey[700],
                    valueColor: AlwaysStoppedAnimation<Color>(circleColor),
                  ),
                ),
              ],
            ),
          ),
        ),

        Positioned(
          top: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: circleColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _getStatusLabel(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _getCircleColor() {
    switch (status) {
      case DistanceStatus.perfect:
        return Colors.green;
      case DistanceStatus.tooClosed:
        return Colors.red;
      case DistanceStatus.tooFar:
        return Colors.yellow;
      case DistanceStatus.noFace:
        return Colors.grey;
    }
  }

  String _getMessage() {
    if (status == DistanceStatus.perfect &&
        scanInstruction != null &&
        scanInstruction!.trim().isNotEmpty) {
      return scanInstruction!;
    }

    switch (status) {
      case DistanceStatus.perfect:
        return _isRegistration
            ? '3 ft ✓ Full face in circle\nHold still…'
            : 'Phone at 3 ft ✓\nHold still…';
      case DistanceStatus.tooClosed:
        return _isRegistration
            ? 'Too close\nMove back — fit full face in circle'
            : 'NOT 3 ft\nMove phone BACK';
      case DistanceStatus.tooFar:
        return _isRegistration
            ? 'Too far / off center\nMove closer — fill the circle'
            : 'NOT 3 ft\nMove phone CLOSER';
      case DistanceStatus.noFace:
        return _isRegistration
            ? 'Show your face\nin the circle'
            : 'NOT 3 ft\nShow your face';
    }
  }

  String _getIcon() {
    switch (status) {
      case DistanceStatus.perfect:
        return '✅';
      case DistanceStatus.tooClosed:
        return '📷';
      case DistanceStatus.tooFar:
        return '👤';
      case DistanceStatus.noFace:
        return '❓';
    }
  }

  String _getStatusLabel() {
    switch (status) {
      case DistanceStatus.perfect:
        return _isRegistration ? 'READY' : '3 FT OK';
      case DistanceStatus.tooClosed:
        return _isRegistration ? 'TOO CLOSE' : 'NOT 3 FT';
      case DistanceStatus.tooFar:
        return _isRegistration ? 'TOO FAR' : 'NOT 3 FT';
      case DistanceStatus.noFace:
        return 'NO FACE';
    }
  }

  double _getRatioPosition() {
    const minRatio = DistanceCheckService.MIN_RATIO;
    const maxRatio = DistanceCheckService.MAX_RATIO;

    if (ratio <= minRatio) return 0.0;
    if (ratio >= maxRatio) return 1.0;

    return ((ratio - minRatio) / (maxRatio - minRatio)).clamp(0.0, 1.0);
  }
}
