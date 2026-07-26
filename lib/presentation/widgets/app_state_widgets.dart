import 'package:flutter/material.dart';
import 'package:smart_attendance_app/core/theme/app_theme.dart';
import 'app_button_variants.dart';

/// Empty state widget for screens with no data
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? actionCallback;
  final String? actionLabel;
  final Color? iconColor;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionCallback,
    this.actionLabel,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Large icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlueLighter,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 48,
                  color: iconColor ?? AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                description,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textGray,
                      height: 1.6,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Action button
              if (actionCallback != null && actionLabel != null)
                AppButton(
                  text: actionLabel!,
                  onPressed: actionCallback,
                  icon: Icons.add_rounded,
                  width: 200,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error state widget for showing errors
class ErrorStateWidget extends StatelessWidget {
  final String title;
  final String message;
  final String? details;
  final VoidCallback? retryCallback;
  final VoidCallback? dismissCallback;
  final IconData icon;
  final bool isExpandable;

  const ErrorStateWidget({
    super.key,
    required this.title,
    required this.message,
    this.details,
    this.retryCallback,
    this.dismissCallback,
    this.icon = Icons.error_outline_rounded,
    this.isExpandable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Error icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.redLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 48,
                  color: AppTheme.accentRed,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentRed,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Message
              Text(
                message,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textGray,
                      height: 1.6,
                    ),
                textAlign: TextAlign.center,
              ),

              // Details section (expandable)
              if (details != null && isExpandable)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _ErrorDetailsSection(details: details!),
                ),

              const SizedBox(height: 32),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (dismissCallback != null)
                    Expanded(
                      child: AppButton(
                        text: 'Dismiss',
                        onPressed: dismissCallback,
                        variant: ButtonVariant.secondary,
                      ),
                    ),
                  if (retryCallback != null) const SizedBox(width: 12),
                  if (retryCallback != null)
                    Expanded(
                      child: AppButton(
                        text: 'Retry',
                        onPressed: retryCallback,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorDetailsSection extends StatefulWidget {
  final String details;

  const _ErrorDetailsSection({required this.details});

  @override
  State<_ErrorDetailsSection> createState() => _ErrorDetailsSectionState();
}

class _ErrorDetailsSectionState extends State<_ErrorDetailsSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.redLight.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.redLight, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Error Details',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppTheme.accentRed,
                          ),
                    ),
                    Icon(
                      _isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppTheme.accentRed,
                      size: 20,
                    ),
                  ],
                ),
                if (_isExpanded) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.details,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textGray,
                          fontFamily: 'monospace',
                        ),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading state widget with skeleton
class LoadingStateWidget extends StatelessWidget {
  final String? message;
  final bool showProgress;

  const LoadingStateWidget({
    super.key,
    this.message,
    this.showProgress = true,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated loading indicator
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlueLighter,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: CircularProgressIndicator(
                color: AppTheme.primaryBlue,
                strokeWidth: 3,
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 24),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.textGray,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (showProgress) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: LinearProgressIndicator(
                backgroundColor: AppTheme.dividerColor,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppTheme.primaryBlue,
                ),
                borderRadius: BorderRadius.circular(4),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Status indicator widget
class StatusIndicator extends StatelessWidget {
  final StatusType status;
  final String label;
  final bool showIcon;
  final double size;

  enum StatusType {
    success,
    error,
    warning,
    info,
    pending,
  }

  const StatusIndicator({
    super.key,
    required this.status,
    required this.label,
    this.showIcon = true,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    final (backgroundColor, textColor, icon) = _getStatusStyle();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 1.5,
        vertical: size * 0.75,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(size),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(icon, size: size * 1.2, color: textColor),
            SizedBox(width: size * 0.75),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color, IconData) _getStatusStyle() {
    return switch (status) {
      StatusType.success => (
          AppTheme.greenLight,
          AppTheme.primaryGreen,
          Icons.check_circle_outline_rounded,
        ),
      StatusType.error => (
          AppTheme.redLight,
          AppTheme.accentRed,
          Icons.cancel_outlined,
        ),
      StatusType.warning => (
          AppTheme.orangeLight,
          AppTheme.accentOrange,
          Icons.warning_outlined,
        ),
      StatusType.info => (
          AppTheme.primaryBlueLighter,
          AppTheme.primaryBlue,
          Icons.info_outline_rounded,
        ),
      StatusType.pending => (
          AppTheme.yellowLight,
          AppTheme.accentYellow,
          Icons.schedule_rounded,
        ),
    };
  }
}

/// Horizontal divider with text
class DividerWithText extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const DividerWithText({
    super.key,
    required this.text,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppTheme.dividerColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppTheme.textGray,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppTheme.dividerColor)),
        ],
      ),
    );
  }
}

/// Info banner widget
class InfoBanner extends StatelessWidget {
  final String title;
  final String? description;
  final VoidCallback? onDismiss;
  final IconData icon;
  final Color backgroundColor;
  final Color textColor;
  final Color? accentColor;

  const InfoBanner({
    super.key,
    required this.title,
    this.description,
    this.onDismiss,
    this.icon = Icons.info_outline_rounded,
    this.backgroundColor = const Color(0xFFE3F2FD),
    this.textColor = AppTheme.primaryBlue,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accentColor ?? textColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: textColor.withValues(alpha: 0.8),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: Icon(Icons.close_rounded, color: textColor, size: 20),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
        ],
      ),
    );
  }
}
