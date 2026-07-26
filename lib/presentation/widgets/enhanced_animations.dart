import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_animate/flutter_animate.dart';

/// Enhanced Animation Utilities using flutter_animate
/// Provides easy-to-use animation chains for any widget

extension EnhancedAnimations on Widget {
  /// Fade in animation
  Widget fadeIn({
    Duration delay = Duration.zero,
    Duration duration = const Duration(milliseconds: 600),
    Curve curve = Curves.easeOut,
  }) {
    return animate()
        .fadeIn(
          delay: delay,
          duration: duration,
          curve: curve,
        )
        .slideY(
          begin: 0.1,
          end: 0,
          delay: delay,
          duration: duration,
          curve: curve,
        );
  }

  /// Slide in from bottom
  Widget slideInUp({
    Duration delay = Duration.zero,
    Duration duration = const Duration(milliseconds: 600),
    Curve curve = Curves.easeOutCubic,
    double begin = 0.3,
  }) {
    return animate()
        .slideY(
          begin: begin,
          end: 0,
          delay: delay,
          duration: duration,
          curve: curve,
        )
        .fadeIn(
          delay: delay,
          duration: duration,
          curve: curve,
        );
  }

  /// Slide in from right
  Widget slideInRight({
    Duration delay = Duration.zero,
    Duration duration = const Duration(milliseconds: 600),
    Curve curve = Curves.easeOutCubic,
    double begin = 0.3,
  }) {
    return animate()
        .slideX(
          begin: begin,
          end: 0,
          delay: delay,
          duration: duration,
          curve: curve,
        )
        .fadeIn(
          delay: delay,
          duration: duration,
          curve: curve,
        );
  }

  /// Scale in animation
  Widget scaleIn({
    Duration delay = Duration.zero,
    Duration duration = const Duration(milliseconds: 600),
    Curve curve = Curves.elasticOut,
    double begin = 0.5,
  }) {
    return animate()
        .scale(
          begin: Offset(begin, begin),
          end: const Offset(1, 1),
          delay: delay,
          duration: duration,
          curve: curve,
        )
        .fadeIn(
          delay: delay,
          duration: duration,
          curve: curve,
        );
  }

  /// Bounce in animation
  Widget bounceIn({
    Duration delay = Duration.zero,
    Duration duration = const Duration(milliseconds: 800),
  }) {
    return animate()
        .scale(
          begin: const Offset(0, 0),
          end: const Offset(1, 1),
          delay: delay,
          duration: duration,
          curve: Curves.elasticOut,
        )
        .fadeIn(
          delay: delay,
          duration: duration,
        );
  }

  /// Shake animation (for errors)
  Widget shake({
    Duration delay = Duration.zero,
    Duration duration = const Duration(milliseconds: 500),
  }) {
    return animate()
        .shake(
          delay: delay,
          duration: duration,
          hz: 4,
        );
  }

  /// Pulse animation
  Widget pulse({
    Duration delay = Duration.zero,
    Duration duration = const Duration(milliseconds: 1000),
    int count = 3,
  }) {
    var animation = animate()
        .scale(
          begin: const Offset(1, 1),
          end: const Offset(1.1, 1.1),
          delay: delay,
          duration: duration,
          curve: Curves.easeInOut,
        )
        .then()
        .scale(
          begin: const Offset(1.1, 1.1),
          end: const Offset(1, 1),
          duration: duration,
          curve: Curves.easeInOut,
        );
    
    // Repeat the animation
    for (int i = 1; i < count; i++) {
      animation = animation
          .then()
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.1, 1.1),
            duration: duration,
            curve: Curves.easeInOut,
          )
          .then()
          .scale(
            begin: const Offset(1.1, 1.1),
            end: const Offset(1, 1),
            duration: duration,
            curve: Curves.easeInOut,
          );
    }
    
    return animation;
  }

  /// Rotate animation
  Widget rotateIn({
    Duration delay = Duration.zero,
    Duration duration = const Duration(milliseconds: 600),
    double begin = -0.2,
  }) {
    return animate()
        .rotate(
          begin: begin,
          end: 0,
          delay: delay,
          duration: duration,
          curve: Curves.easeOut,
        )
        .fadeIn(
          delay: delay,
          duration: duration,
        );
  }

  /// Flip animation
  Widget flipIn({
    Duration delay = Duration.zero,
    Duration duration = const Duration(milliseconds: 600),
  }) {
    return animate()
        .flip(
          delay: delay,
          duration: duration,
          curve: Curves.easeOut,
        )
        .fadeIn(
          delay: delay,
          duration: duration,
        );
  }

  /// Staggered animation for lists
  Widget stagger({
    int index = 0,
    Duration staggerDelay = const Duration(milliseconds: 100),
    Duration duration = const Duration(milliseconds: 600),
  }) {
    return animate()
        .fadeIn(
          delay: staggerDelay * index,
          duration: duration,
        )
        .slideY(
          begin: 0.2,
          end: 0,
          delay: staggerDelay * index,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
  }
}

/// Animated Card with glassmorphism
class AnimatedGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double? width;
  final double? height;
  final Duration delay;
  final VoidCallback? onTap;

  const AnimatedGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.width,
    this.height,
    this.delay = Duration.zero,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Widget card = Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: card,
      );
    }

    return card
        .fadeIn(delay: delay)
        .scaleIn(delay: delay, begin: 0.9);
  }
}

/// Neumorphic Card
class NeumorphicCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final double borderRadius;

  const NeumorphicCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.borderRadius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = color ?? (isDark ? const Color(0xFF1F2933) : Colors.white);
    
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          // Light shadow (top-left)
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.5)
                : Colors.white.withOpacity(0.8),
            blurRadius: 15,
            offset: const Offset(-8, -8),
            spreadRadius: 0,
          ),
          // Dark shadow (bottom-right)
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.8)
                : Colors.grey.shade400.withOpacity(0.5),
            blurRadius: 15,
            offset: const Offset(8, 8),
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }
}
