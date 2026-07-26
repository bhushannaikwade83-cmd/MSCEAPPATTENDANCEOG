import 'package:flutter/material.dart';

class PrimaryButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? textColor;
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool isOutlined;
  final double elevation;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.backgroundColor,
    this.textColor,
    this.width,
    this.height = 56,
    this.borderRadius = 12,
    this.padding,
    this.isOutlined = false,
    this.elevation = 2,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      setState(() => _isPressed = true);
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    
    final backgroundColor = widget.backgroundColor ?? colorScheme.primary;
    final textColor = widget.textColor ?? colorScheme.onPrimary;
    final isDisabled = widget.onPressed == null && !widget.isLoading;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        child: SizedBox(
          width: widget.width ?? double.infinity,
          height: widget.height,
          child: widget.isOutlined
              ? _buildOutlinedButton(
                  context,
                  colorScheme,
                  textTheme,
                  backgroundColor,
                  textColor,
                  isDisabled,
                )
              : _buildElevatedButton(
                  context,
                  colorScheme,
                  textTheme,
                  backgroundColor,
                  textColor,
                  isDisabled,
                ),
        ),
      ),
    );
  }

  Widget _buildElevatedButton(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    Color backgroundColor,
    Color textColor,
    bool isDisabled,
  ) {
    return ElevatedButton(
      onPressed: widget.isLoading ? null : widget.onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isDisabled
            ? colorScheme.surfaceContainerHighest
            : backgroundColor,
        foregroundColor: textColor,
        elevation: isDisabled ? 0 : (_isPressed ? 1 : widget.elevation),
        shadowColor: backgroundColor.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        padding: widget.padding ??
            const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        disabledBackgroundColor: colorScheme.surfaceContainerHighest,
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
      ),
      child: widget.isLoading
          ? SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(textColor),
              ),
            )
          : _buildButtonContent(textTheme, textColor),
    );
  }

  Widget _buildOutlinedButton(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    Color backgroundColor,
    Color textColor,
    bool isDisabled,
  ) {
    return OutlinedButton(
      onPressed: widget.isLoading ? null : widget.onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: backgroundColor,
        side: BorderSide(
          color: isDisabled
              ? colorScheme.outline.withValues(alpha: 0.3)
              : backgroundColor,
          width: 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        padding: widget.padding ??
            const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
      ),
      child: widget.isLoading
          ? SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(backgroundColor),
              ),
            )
          : _buildButtonContent(textTheme, backgroundColor),
    );
  }

  Widget _buildButtonContent(TextTheme textTheme, Color color) {
    if (widget.icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.text,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Text(
      widget.text,
      style: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: color,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}
