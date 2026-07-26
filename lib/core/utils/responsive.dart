import 'package:flutter/material.dart';

export 'adaptive_scroll.dart';

/// Responsive utility class for handling different screen sizes
class Responsive {
  /// Get screen width (viewport width, “vw” base).
  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;

  /// Get screen height (viewport height, “vh” base).
  static double height(BuildContext context) => MediaQuery.sizeOf(context).height;

  /// **vw** — width as percent of viewport (0–100), CSS-style: `vw(context, 10)` → 10% of screen width.
  static double vw(BuildContext context, double percent) {
    final p = percent.clamp(0.0, 100.0);
    return width(context) * (p / 100.0);
  }

  /// **vh** — height as percent of viewport (0–100): `vh(context, 5)` → 5% of screen height.
  static double vh(BuildContext context, double percent) {
    final p = percent.clamp(0.0, 100.0);
    return height(context) * (p / 100.0);
  }

  /// Same as [vw] — explicit “percent of width” name.
  static double percentWidth(BuildContext context, double zeroTo100) =>
      vw(context, zeroTo100);

  /// Same as [vh] — explicit “percent of height” name.
  static double percentHeight(BuildContext context, double zeroTo100) =>
      vh(context, zeroTo100);

  /// Fraction of screen width (0.0–1.0), e.g. `pctWidth(context, 0.9)` → 90% width.
  static double pctWidth(BuildContext context, double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    return width(context) * f;
  }

  /// Fraction of screen height (0.0–1.0).
  static double pctHeight(BuildContext context, double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    return height(context) * f;
  }

  /// Size from shorter side (stable on rotation); good for icons and tiles.
  static double pctShortestSide(BuildContext context, double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    final s = MediaQuery.of(context).size.shortestSide;
    return s * f;
  }
  
  /// Check if screen is mobile (< 600)
  static bool isMobile(BuildContext context) => width(context) < 600;
  
  /// Check if screen is tablet (600 - 1200)
  static bool isTablet(BuildContext context) => width(context) >= 600 && width(context) < 1200;
  
  /// Check if screen is desktop (> 1200)
  static bool isDesktop(BuildContext context) => width(context) >= 1200;
  
  /// Get responsive padding
  static EdgeInsets padding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = (width * 0.05).clamp(16.0, 40.0);
    final vertical = isDesktop(context)
        ? 20.0
        : isTablet(context)
            ? 16.0
            : 12.0;
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  }

  /// Shared content width cap for auth/setup flows and tablets/foldables.
  static double contentMaxWidth(BuildContext context, {double mobile = 560, double tablet = 720}) {
    final width = MediaQuery.sizeOf(context).width;
    if (isDesktop(context)) return tablet;
    if (isTablet(context)) return tablet.clamp(0.0, width);
    return mobile.clamp(0.0, width);
  }

  /// Prevents very large system font scaling from blowing up fixed-height UI.
  static TextScaler appTextScaler(BuildContext context) {
    final current = MediaQuery.textScalerOf(context);
    return current.clamp(minScaleFactor: 0.95, maxScaleFactor: 1.15);
  }
  
  /// Get responsive font size
  static double fontSize(BuildContext context, double baseSize) {
    if (isDesktop(context)) {
      return baseSize * 1.2;
    } else if (isTablet(context)) {
      return baseSize * 1.1;
    } else {
      return baseSize;
    }
  }
  
  /// Get responsive column count for grids
  static int gridColumns(BuildContext context) {
    if (isDesktop(context)) {
      return 4;
    } else if (isTablet(context)) {
      return 3;
    } else {
      return 2;
    }
  }
}

/// Shorthand for [Responsive] on [BuildContext]: `context.vw(4)`, `context.vh(2)`, `context.pctW(0.9)`.
extension ResponsiveViewport on BuildContext {
  double vw(double percent) => Responsive.vw(this, percent);

  double vh(double percent) => Responsive.vh(this, percent);

  double pctW(double fractionZeroToOne) => Responsive.pctWidth(this, fractionZeroToOne);

  double pctH(double fractionZeroToOne) => Responsive.pctHeight(this, fractionZeroToOne);

  double percentWidth(double zeroTo100) => Responsive.percentWidth(this, zeroTo100);

  double percentHeight(double zeroTo100) => Responsive.percentHeight(this, zeroTo100);

  double contentMaxWidth({double mobile = 560, double tablet = 720}) =>
      Responsive.contentMaxWidth(this, mobile: mobile, tablet: tablet);
}
