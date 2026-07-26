import 'package:flutter/material.dart';

/// Scrollable column with **mainAxisSize.min** (“auto” height): children only take the space they need.
/// When content is taller than the viewport, it scrolls — avoids **RenderFlex overflow** on small screens
/// or with large text / keyboard.
///
/// Prefer this instead of a bare `Column` inside a fixed-height `Scaffold` body when not using
/// `Expanded` + `ListView` / `CustomScrollView`.
///
/// For toolbars + list, keep using `Column` + `Expanded(child: ListView(...))` or `CustomScrollView`.
class AdaptiveScrollColumn extends StatelessWidget {
  const AdaptiveScrollColumn({
    super.key,
    required this.children,
    this.padding,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.scrollPhysics = const AlwaysScrollableScrollPhysics(),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  final ScrollPhysics scrollPhysics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: scrollPhysics,
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              minHeight: constraints.maxHeight,
            ),
            child: Column(
              crossAxisAlignment: crossAxisAlignment,
              mainAxisAlignment: mainAxisAlignment,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        );
      },
    );
  }
}

/// Puts [flexible] in an [Expanded] so a **Row** / **Column** does not overflow (flex pattern).
Widget flexExpanded(Widget flexible, {int flex = 1}) => Expanded(flex: flex, child: flexible);

/// Puts [child] in a [Flexible] with loose fit — grows only if space allows.
Widget flexLoose(Widget child, {int flex = 1}) =>
    Flexible(flex: flex, fit: FlexFit.loose, child: child);
