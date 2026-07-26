import 'package:flutter/material.dart';

/// Parallax Scroll Widget
/// Creates depth by moving background elements at different speeds
class ParallaxScroll extends StatelessWidget {
  final Widget background;
  final Widget foreground;
  final ScrollController? scrollController;
  final double parallaxSpeed;

  const ParallaxScroll({
    super.key,
    required this.background,
    required this.foreground,
    this.scrollController,
    this.parallaxSpeed = 0.5, // 0.0 to 1.0, lower = slower movement
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // This will be handled by the ParallaxScrollView
        return false;
      },
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // Background layer (moves slower)
                ParallaxBackground(
                  speed: parallaxSpeed,
                  child: background,
                ),
                // Foreground layer (moves normally)
                foreground,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Parallax Background Widget
class ParallaxBackground extends StatefulWidget {
  final Widget child;
  final double speed;

  const ParallaxBackground({
    super.key,
    required this.child,
    this.speed = 0.5,
  });

  @override
  State<ParallaxBackground> createState() => _ParallaxBackgroundState();
}

class _ParallaxBackgroundState extends State<ParallaxBackground> {
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, _scrollOffset * widget.speed),
      child: widget.child,
    );
  }
}

/// Simple Parallax Container
/// Use this for simple parallax effects in scrollable views
class ParallaxContainer extends StatelessWidget {
  final Widget child;
  final double speed;
  final ScrollController? scrollController;

  const ParallaxContainer({
    super.key,
    required this.child,
    this.speed = 0.5,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (scrollController == null) {
      return child;
    }

    return AnimatedBuilder(
      animation: scrollController!,
      builder: (context, child) {
        final offset = scrollController!.hasClients
            ? scrollController!.offset * speed
            : 0.0;
        return Transform.translate(
          offset: Offset(0, offset),
          child: this.child,
        );
      },
      child: child,
    );
  }
}
