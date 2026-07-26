import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Face ID-style scanning animation widget
/// 
/// Displays animated dots in a circular pattern (like iPhone Face ID)
/// Dots animate around a circle to show scanning progress
class FaceScanningWidget extends StatefulWidget {
  final double size;
  final Color dotColor;
  final Color activeDotColor;
  final int dotCount;
  final Duration animationDuration;
  final String? message;

  const FaceScanningWidget({
    Key? key,
    this.size = 200.0,
    this.dotColor = Colors.white54,
    this.activeDotColor = Colors.white,
    this.dotCount = 12,
    this.animationDuration = const Duration(seconds: 2),
    this.message,
  }) : super(key: key);

  @override
  State<FaceScanningWidget> createState() => _FaceScanningWidgetState();
}

class _FaceScanningWidgetState extends State<FaceScanningWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    )..repeat();

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer circle (guide)
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.dotColor.withOpacity(0.3),
                width: 2,
              ),
            ),
          ),
          // Animated dots
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _FaceScanningPainter(
                  progress: _animation.value,
                  dotCount: widget.dotCount,
                  dotColor: widget.dotColor,
                  activeDotColor: widget.activeDotColor,
                  radius: widget.size / 2,
                ),
              );
            },
          ),
          // Center message
          if (widget.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 120),
              child: Text(
                widget.message!,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _FaceScanningPainter extends CustomPainter {
  final double progress;
  final int dotCount;
  final Color dotColor;
  final Color activeDotColor;
  final double radius;

  _FaceScanningPainter({
    required this.progress,
    required this.dotCount,
    required this.dotColor,
    required this.activeDotColor,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dotRadius = 6.0;
    final activeDotRadius = 8.0;
    
    // Number of dots to highlight at once (creates wave effect)
    final activeDotCount = 3;
    
    for (int i = 0; i < dotCount; i++) {
      // Calculate angle for this dot
      final angle = (i / dotCount) * 2 * math.pi - math.pi / 2; // Start from top
      
      // Calculate position on circle
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      
      // Determine if this dot should be active (based on progress)
      final dotProgress = (progress + (i / dotCount)) % 1.0;
      final isActive = dotProgress < (activeDotCount / dotCount);
      
      // Calculate opacity based on position in active wave
      double opacity = 0.3;
      if (isActive) {
        // Fade in/out effect
        final fadeProgress = dotProgress / (activeDotCount / dotCount);
        opacity = 0.3 + (0.7 * (1 - fadeProgress));
      }
      
      // Draw dot
      final paint = Paint()
        ..color = (isActive ? activeDotColor : dotColor).withOpacity(opacity)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(x, y),
        isActive ? activeDotRadius : dotRadius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FaceScanningPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Full-screen face scanning overlay
class FaceScanningOverlay extends StatelessWidget {
  final String message;
  final VoidCallback? onCancel;

  const FaceScanningOverlay({
    Key? key,
    required this.message,
    this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Scanning animation
            FaceScanningWidget(
              size: 200,
              message: message,
            ),
            const SizedBox(height: 40),
            // Instructions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Position your face within the frame\nKeep your eyes open and look at the camera',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 40),
            // Cancel button
            if (onCancel != null)
              TextButton(
                onPressed: onCancel,
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
