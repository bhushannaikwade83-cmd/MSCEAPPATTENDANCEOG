import 'package:flutter/material.dart';
import 'package:smart_attendance_app/core/theme/app_theme.dart';

/// Standard card with consistent styling
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final double elevation;
  final double borderRadius;
  final bool isSelectable;
  final bool isSelected;
  final BorderSide? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.onTap,
    this.elevation = 2,
    this.borderRadius = 12,
    this.isSelectable = false,
    this.isSelected = false,
    this.border,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isInteractive = widget.onTap != null;

    return MouseRegion(
      onEnter: (_) => isInteractive ? setState(() => _isHovered = true) : null,
      onExit: (_) => isInteractive ? setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppAnimations.standard,
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? Colors.white,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: widget.border ??
                (widget.isSelected
                    ? Border.all(
                        color: AppTheme.primaryBlue,
                        width: 2,
                      )
                    : Border.all(
                        color: AppTheme.dividerColor,
                        width: 1,
                      )),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: _isHovered || widget.isSelected ? 0.1 : 0.07,
                ),
                blurRadius: _isHovered || widget.isSelected ? 16 : 12,
                offset: Offset(0, _isHovered || widget.isSelected ? 4 : 3),
              ),
              if (_isHovered || widget.isSelected)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
            ],
          ),
          child: Padding(
            padding: widget.padding ?? AppSpacing.cardPadding,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Card with left accent strip (government style)
class AccentCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  final double accentWidth;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double elevation;

  const AccentCard({
    super.key,
    required this.child,
    this.accentColor = AppTheme.primaryBlue,
    this.accentWidth = 4,
    this.padding,
    this.onTap,
    this.elevation = 2,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.dividerColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Accent strip
                SizedBox(
                  width: accentWidth,
                  child: ColoredBox(color: accentColor),
                ),
                // Content
                Expanded(
                  child: Padding(
                    padding: padding ?? AppSpacing.cardPadding,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Elevated card for highlighted content
class ElevatedAppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? accentColor;
  final bool showTopAccent;

  const ElevatedAppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.accentColor,
    this.showTopAccent = false,
  });

  @override
  State<ElevatedAppCard> createState() => _ElevatedAppCardState();
}

class _ElevatedAppCardState extends State<ElevatedAppCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppAnimations.standard,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered
                  ? AppTheme.primaryBlue.withValues(alpha: 0.3)
                  : AppTheme.dividerColor,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withValues(
                  alpha: _isHovered ? 0.12 : 0.08,
                ),
                blurRadius: _isHovered ? 20 : 16,
                offset: Offset(0, _isHovered ? 6 : 4),
                spreadRadius: _isHovered ? 1 : 0,
              ),
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: _isHovered ? 0.06 : 0.03,
                ),
                blurRadius: _isHovered ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                // Top accent
                if (widget.showTopAccent)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 3,
                      color: widget.accentColor ?? AppTheme.primaryBlue,
                    ),
                  ),
                // Content
                Padding(
                  padding: widget.padding ?? AppSpacing.cardPadding,
                  child: widget.child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined card (alternative style)
class OutlinedAppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double borderWidth;

  const OutlinedAppCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.onTap,
    this.borderWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor ?? AppTheme.primaryBlueLighter,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor ?? AppTheme.primaryBlue,
            width: borderWidth,
          ),
        ),
        child: Padding(
          padding: padding ?? AppSpacing.cardPadding,
          child: child,
        ),
      ),
    );
  }
}

/// Compact card for list items
class CompactCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool isSelected;

  const CompactCard({
    super.key,
    required this.child,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: child,
      ),
    );
  }
}

/// Minimal card (for subtle containers)
class MinimalCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final double borderRadius;

  const MinimalCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.backgroundOffWhite,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child,
    );
  }
}

/// Data card for displaying statistics
class DataCard extends StatelessWidget {
  final String? label;
  final String value;
  final IconData? icon;
  final Color? accentColor;
  final VoidCallback? onTap;
  final String? subtitle;

  const DataCard({
    super.key,
    this.label,
    required this.value,
    this.icon,
    this.accentColor,
    this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AccentCard(
      accentColor: accentColor ?? AppTheme.primaryBlue,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null || label != null)
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 20,
                    color: accentColor ?? AppTheme.primaryBlue,
                  ),
                  const SizedBox(width: 8),
                ],
                if (label != null)
                  Text(
                    label!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppTheme.textGray,
                          fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          if (icon != null || label != null) const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textGray,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
