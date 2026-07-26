import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/theme/app_theme.dart';

/// Animated Background Widget - Creates floating particles effect
class AnimatedBackground extends StatefulWidget {
  final Widget child;
  final List<Color> colors;

  const AnimatedBackground({
    super.key,
    required this.child,
    this.colors = const [
      AppTheme.primaryBlue,
      AppTheme.primaryBlueDark,
      AppTheme.primaryBlueLight,
    ],
  });

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Create particles
    for (int i = 0; i < 20; i++) {
      _particles.add(Particle());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: ParticlePainter(
            particles: _particles,
            animationValue: _controller.value,
            colors: widget.colors,
          ),
          child: widget.child,
        );
      },
    );
  }
}

class Particle {
  late double x;
  late double y;
  late double radius;
  late double speed;
  late double angle;
  late Color color;

  Particle() {
    final random = math.Random();
    x = random.nextDouble();
    y = random.nextDouble();
    radius = random.nextDouble() * 3 + 1;
    speed = random.nextDouble() * 0.5 + 0.1;
    angle = random.nextDouble() * 2 * math.pi;
    color = Colors.white.withValues(alpha: random.nextDouble() * 0.3 + 0.1);
  }

  void update(double animationValue) {
    x += math.cos(angle) * speed * 0.01;
    y += math.sin(angle) * speed * 0.01;

    if (x < 0 || x > 1) angle = math.pi - angle;
    if (y < 0 || y > 1) angle = -angle;

    x = x.clamp(0.0, 1.0);
    y = y.clamp(0.0, 1.0);
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double animationValue;
  final List<Color> colors;

  ParticlePainter({
    required this.particles,
    required this.animationValue,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw gradient background first
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      )
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );

    // Draw particles on top
    final particlePaint = Paint()..style = PaintingStyle.fill;
    for (var particle in particles) {
      particle.update(animationValue);
      particlePaint.color = particle.color;
      canvas.drawCircle(
        Offset(particle.x * size.width, particle.y * size.height),
        particle.radius,
        particlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
