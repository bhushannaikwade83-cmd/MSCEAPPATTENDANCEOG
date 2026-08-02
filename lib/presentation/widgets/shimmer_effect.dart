import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_theme.dart';

/// Shimmer Effect Widget for Loading States
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
      period: const Duration(milliseconds: 1200),
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

/// Shimmer List Item - Student card loading placeholder
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(12.w),
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShimmerEffect(
                width: 60.w,
                height: 60.w,
                borderRadius: BorderRadius.circular(12.r),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerEffect(width: 120.w, height: 14.h),
                    SizedBox(height: 6.h),
                    ShimmerEffect(width: 80.w, height: 12.h),
                  ],
                ),
              ),
              ShimmerEffect(width: 50.w, height: 20.h, borderRadius: BorderRadius.circular(10.r)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerEffect(width: 100.w, height: 50.h, borderRadius: BorderRadius.circular(8.r)),
              ShimmerEffect(width: 100.w, height: 50.h, borderRadius: BorderRadius.circular(8.r)),
            ],
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

/// Shimmer Stat Card - For loading stat placeholders
class ShimmerStatCard extends StatelessWidget {
  const ShimmerStatCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ShimmerEffect(width: 80.w, height: 12.h),
          SizedBox(height: 8.h),
          ShimmerEffect(width: 120.w, height: 20.h),
        ],
      ),
    );
  }
}
