import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_theme.dart';

/// Shimmer Effect Widget for Loading States
/// Provides a modern, polished loading animation
class ShimmerEffect extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final Color? baseColor;
  final Color? highlightColor;
  final Widget? child;

  const ShimmerEffect({
    super.key,
    this.width = double.infinity,
    this.height = 20,
    this.borderRadius,
    this.baseColor,
    this.highlightColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Shimmer.fromColors(
      baseColor: baseColor ?? (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
      highlightColor: highlightColor ?? (isDark ? Colors.grey.shade700 : Colors.grey.shade100),
      period: const Duration(milliseconds: 1500),
      child: child ??
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.white,
              borderRadius: borderRadius ?? BorderRadius.circular(8),
            ),
          ),
    );
  }
}

/// Shimmer Card - For loading card placeholders
class ShimmerCard extends StatelessWidget {
  final double? width;
  final double? height;
  final EdgeInsets? padding;

  const ShimmerCard({
    super.key,
    this.width,
    this.height,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerEffect(
            width: 60,
            height: 60,
            borderRadius: BorderRadius.circular(30),
          ),
          const SizedBox(height: 16),
          ShimmerEffect(width: double.infinity, height: 16),
          const SizedBox(height: 8),
          ShimmerEffect(width: 150, height: 14),
          const SizedBox(height: 12),
          ShimmerEffect(width: double.infinity, height: 12),
          const SizedBox(height: 4),
          ShimmerEffect(width: 120, height: 12),
        ],
      ),
    );
  }
}

/// Shimmer List Item - For loading list placeholders
class ShimmerListItem extends StatelessWidget {
  final bool showAvatar;
  final bool showSubtitle;

  const ShimmerListItem({
    super.key,
    this.showAvatar = true,
    this.showSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showAvatar) ...[
            ShimmerEffect(
              width: 50,
              height: 50,
              borderRadius: BorderRadius.circular(25),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerEffect(width: double.infinity, height: 16),
                if (showSubtitle) ...[
                  const SizedBox(height: 8),
                  ShimmerEffect(width: 120, height: 14),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer Grid - For loading grid placeholders
class ShimmerGrid extends StatelessWidget {
  final int crossAxisCount;
  final int itemCount;
  final double childAspectRatio;

  const ShimmerGrid({
    super.key,
    this.crossAxisCount = 2,
    this.itemCount = 6,
    this.childAspectRatio = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return ShimmerCard();
      },
    );
  }
}
