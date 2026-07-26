import 'package:flutter/material.dart';

/// Automatically handles text overflow on narrow screens (fold devices, etc.)
class ResponsiveText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;
  final bool softWrap;

  const ResponsiveText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
    this.softWrap = true,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap,
    );
  }
}

/// Row that wraps to column on narrow screens
class ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final double narrowScreenThreshold;

  const ResponsiveRow({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.narrowScreenThreshold = 400,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < narrowScreenThreshold;

    if (isNarrow) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: crossAxisAlignment,
        children: children,
      );
    }

    return Row(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: children,
    );
  }
}

/// Responsive padding that reduces on narrow screens
class ResponsivePadding extends StatelessWidget {
  final Widget child;
  final EdgeInsets normalPadding;
  final EdgeInsets narrowPadding;
  final double narrowScreenThreshold;

  const ResponsivePadding({
    super.key,
    required this.child,
    this.normalPadding = const EdgeInsets.all(16),
    this.narrowPadding = const EdgeInsets.all(12),
    this.narrowScreenThreshold = 400,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < narrowScreenThreshold;

    return Padding(
      padding: isNarrow ? narrowPadding : normalPadding,
      child: child,
    );
  }
}

/// Safe container for text that prevents overflow
class SafeTextContainer extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final EdgeInsets padding;

  const SafeTextContainer({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.padding = const EdgeInsets.all(8.0),
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: padding,
        child: Text(
          text,
          style: style,
          maxLines: maxLines,
          overflow: overflow,
        ),
      ),
    );
  }
}

/// Constrained text that handles overflow
class ConstrainedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final double maxWidth;

  const ConstrainedText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.maxWidth = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: maxWidth,
      child: Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

/// Row that automatically wraps children on narrow screens
class WrapRow extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final double narrowScreenThreshold;

  const WrapRow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 4,
    this.narrowScreenThreshold = 400,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < narrowScreenThreshold;

    if (isNarrow) {
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: children,
      );
    }

    return Row(
      children: children,
    );
  }
}

/// Safe icon size based on screen width
class ResponsiveIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double normalSize;
  final double narrowSize;
  final double narrowScreenThreshold;

  const ResponsiveIcon(
    this.icon, {
    super.key,
    this.color,
    this.normalSize = 24,
    this.narrowSize = 20,
    this.narrowScreenThreshold = 400,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < narrowScreenThreshold;

    return Icon(
      icon,
      color: color,
      size: isNarrow ? narrowSize : normalSize,
    );
  }
}

/// Safe font size based on screen width
double getResponsiveFontSize(
  BuildContext context, {
  double normalSize = 16,
  double narrowSize = 14,
  double narrowScreenThreshold = 400,
}) {
  final screenWidth = MediaQuery.of(context).size.width;
  return screenWidth < narrowScreenThreshold ? narrowSize : normalSize;
}

/// Get safe padding for narrow screens
EdgeInsets getResponsivePadding(
  BuildContext context, {
  double normalValue = 16,
  double narrowValue = 12,
  double narrowScreenThreshold = 400,
}) {
  final isNarrow = MediaQuery.of(context).size.width < narrowScreenThreshold;
  final value = isNarrow ? narrowValue : normalValue;
  return EdgeInsets.all(value);
}

/// Check if screen is narrow (fold device, etc.)
bool isNarrowScreen(
  BuildContext context, {
  double threshold = 400,
}) {
  return MediaQuery.of(context).size.width < threshold;
}
