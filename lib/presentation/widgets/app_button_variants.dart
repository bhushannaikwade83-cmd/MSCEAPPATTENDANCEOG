import 'package:flutter/material.dart';
import 'package:smart_attendance_app/core/theme/app_theme.dart';

/// Button variant types for the application
enum ButtonVariant {
  primary,    // Navy blue, elevated, main action
  secondary,  // Outlined, navy text
  tertiary,   // Saffron background, secondary action
  danger,     // Red background, destructive action
  ghost,      // Transparent, minimal style
}

/// Comprehensive button widget with support for multiple variants
/// Replaces simple PrimaryButton with a more flexible system
class AppButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final ButtonVariant variant;
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final FocusNode? focusNode;
  final String? tooltip;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = ButtonVariant.primary,
    this.width,
    this.height = 56,
    this.borderRadius = 12,
    this.padding,
    this.focusNode,
    this.tooltip,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.quickFeedback,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    widget.focusNode?.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _controller.dispose();
    widget.focusNode?.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {
      _isFocused = widget.focusNode?.hasFocus ?? false;
    });
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
    if (widget.onPressed != null && !widget.isLoading) {
      widget.onPressed!();
    }
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final child = ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        child: _buildButton(context),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: child,
      );
    }

    return child;
  }

  Widget _buildButton(BuildContext context) {
    return SizedBox(
      width: widget.width ?? double.infinity,
      height: widget.height,
      child: switch (widget.variant) {
        ButtonVariant.primary => _buildPrimaryButton(context),
        ButtonVariant.secondary => _buildSecondaryButton(context),
        ButtonVariant.tertiary => _buildTertiaryButton(context),
        ButtonVariant.danger => _buildDangerButton(context),
        ButtonVariant.ghost => _buildGhostButton(context),
      },
    );
  }

  Widget _buildPrimaryButton(BuildContext context) {
    final isDisabled = widget.onPressed == null && !widget.isLoading;

    return Focus(
      focusNode: widget.focusNode,
      onKey: (node, event) {
        // Allow Space/Enter to activate button
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: _isFocused
              ? Border.all(
                  color: AppTheme.focusRing,
                  width: 2,
                )
              : null,
        ),
        child: ElevatedButton(
          onPressed: widget.isLoading ? null : widget.onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: isDisabled
                ? AppTheme.disabledGray
                : AppTheme.primaryBlue,
            foregroundColor: isDisabled ? Colors.white54 : Colors.white,
            elevation: isDisabled ? 0 : (_isPressed ? 1 : 2),
            shadowColor: AppTheme.primaryBlue.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
            padding: widget.padding ??
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: _buildButtonContent(Colors.white, isDisabled),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton(BuildContext context) {
    final isDisabled = widget.onPressed == null && !widget.isLoading;

    return Focus(
      focusNode: widget.focusNode,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: _isFocused
              ? Border.all(
                  color: AppTheme.focusRing,
                  width: 2,
                )
              : null,
        ),
        child: OutlinedButton(
          onPressed: widget.isLoading ? null : widget.onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: isDisabled ? Colors.grey : AppTheme.primaryBlue,
            side: BorderSide(
              color: isDisabled ? AppTheme.dividerColor : AppTheme.primaryBlue,
              width: 2,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
            padding: widget.padding ??
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: _buildButtonContent(
            isDisabled ? Colors.grey : AppTheme.primaryBlue,
            isDisabled,
          ),
        ),
      ),
    );
  }

  Widget _buildTertiaryButton(BuildContext context) {
    final isDisabled = widget.onPressed == null && !widget.isLoading;

    return Focus(
      focusNode: widget.focusNode,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: _isFocused
              ? Border.all(
                  color: AppTheme.focusRing,
                  width: 2,
                )
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isLoading ? null : widget.onPressed,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Container(
              decoration: BoxDecoration(
                color: isDisabled ? AppTheme.disabledGray : AppTheme.saffronLight,
                borderRadius: BorderRadius.circular(widget.borderRadius),
              ),
              padding: widget.padding ??
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: _buildButtonContent(
                isDisabled ? Colors.grey : AppTheme.accentSaffron,
                isDisabled,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDangerButton(BuildContext context) {
    final isDisabled = widget.onPressed == null && !widget.isLoading;

    return Focus(
      focusNode: widget.focusNode,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: _isFocused
              ? Border.all(
                  color: AppTheme.focusRing,
                  width: 2,
                )
              : null,
        ),
        child: ElevatedButton(
          onPressed: widget.isLoading ? null : widget.onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: isDisabled
                ? AppTheme.disabledGray
                : AppTheme.accentRed,
            foregroundColor: isDisabled ? Colors.white54 : Colors.white,
            elevation: isDisabled ? 0 : (_isPressed ? 1 : 2),
            shadowColor: AppTheme.accentRed.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
            padding: widget.padding ??
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: _buildButtonContent(Colors.white, isDisabled),
        ),
      ),
    );
  }

  Widget _buildGhostButton(BuildContext context) {
    final isDisabled = widget.onPressed == null && !widget.isLoading;

    return Focus(
      focusNode: widget.focusNode,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: _isFocused
              ? Border.all(
                  color: AppTheme.focusRing,
                  width: 2,
                )
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isLoading ? null : widget.onPressed,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            splashColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
            highlightColor: AppTheme.primaryBlue.withValues(alpha: 0.08),
            child: Padding(
              padding: widget.padding ??
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: _buildButtonContent(
                isDisabled ? Colors.grey : AppTheme.primaryBlue,
                isDisabled,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonContent(Color color, bool isDisabled) {
    if (widget.isLoading) {
      return SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }

    if (widget.icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: 20, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Mini button for compact spaces (toolbar, inline actions)
class AppMiniButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final ButtonVariant variant;
  final bool isLoading;

  const AppMiniButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          icon: Icon(icon),
          onPressed: isLoading ? null : onPressed,
          style: IconButton.styleFrom(
            backgroundColor: _getBackgroundColor(),
            foregroundColor: _getForegroundColor(),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Color _getBackgroundColor() {
    return switch (variant) {
      ButtonVariant.primary => AppTheme.primaryBlue,
      ButtonVariant.secondary => Colors.transparent,
      ButtonVariant.tertiary => AppTheme.saffronLight,
      ButtonVariant.danger => AppTheme.accentRed,
      ButtonVariant.ghost => Colors.transparent,
    };
  }

  Color _getForegroundColor() {
    return switch (variant) {
      ButtonVariant.primary => Colors.white,
      ButtonVariant.secondary => AppTheme.primaryBlue,
      ButtonVariant.tertiary => AppTheme.accentSaffron,
      ButtonVariant.danger => Colors.white,
      ButtonVariant.ghost => AppTheme.primaryBlue,
    };
  }
}

/// Compact button for tight layouts
class AppCompactButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final double? width;

  const AppCompactButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = ButtonVariant.primary,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton(
      text: text,
      onPressed: onPressed,
      variant: variant,
      width: width,
      height: 40,
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }
}
