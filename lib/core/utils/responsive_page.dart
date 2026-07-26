import 'package:flutter/material.dart';

import 'responsive.dart';

class ResponsiveScrollBody extends StatelessWidget {
  const ResponsiveScrollBody({
    super.key,
    required this.child,
    this.padding,
    this.physics = const BouncingScrollPhysics(),
    this.mobileMaxWidth = 560,
    this.tabletMaxWidth = 760,
    this.minHeight = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics physics;
  final double mobileMaxWidth;
  final double tabletMaxWidth;
  final bool minHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: physics,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: padding ?? Responsive.padding(context),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.contentMaxWidth(
                  context,
                  mobile: mobileMaxWidth,
                  tablet: tabletMaxWidth,
                ),
                minHeight: minHeight ? constraints.maxHeight : 0,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
