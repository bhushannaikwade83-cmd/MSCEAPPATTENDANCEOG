import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../presentation/screens/help_desk_screen.dart';

/// Professional messaging utility for consistent user communication
/// Provides standardized success, error, warning, and info messages
class ProfessionalMessaging {
  /// Show professional success message
  static void showSuccess(
    BuildContext context, {
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    int durationSeconds = 5,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.accentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: Duration(seconds: durationSeconds),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  /// Show professional error message
  static void showError(
    BuildContext context, {
    required String title,
    required String message,
    bool showHelp = true,
    int durationSeconds = 5,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.accentRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: Duration(seconds: durationSeconds),
        action: showHelp
            ? SnackBarAction(
                label: 'Help',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.pushNamed(context, HelpDeskScreen.routeName);
                },
              )
            : null,
      ),
    );
  }

  /// Short, safe text for face capture / on-device processing failures (never raw stack or HTTP bodies).
  static String messageForFaceProcessingError(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) {
      return 'We could not use this photo. Face the camera, use good lighting, and try again.';
    }

    String? inner;
    final m = RegExp(r'^Exception:\s*(.+)$', caseSensitive: false, multiLine: false).firstMatch(raw);
    if (m != null) inner = m.group(1)?.trim();

    final candidate = (inner != null && inner.isNotEmpty) ? inner : raw.replaceAll('Exception: ', '').trim();

    if (_isPlainUserFaceMessage(candidate)) {
      return candidate;
    }

    final lower = raw.toLowerCase();
    if (lower.contains('postgrest') ||
        lower.contains('pgrst') ||
        lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network')) {
      return 'Connection problem. Check your internet and try again.';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'This took too long. Try again with better lighting or restart the camera.';
    }
    if (lower.contains('tflite') ||
        lower.contains('interpreter') ||
        lower.contains('failed to load model') ||
        lower.contains('model') && lower.contains('not found')) {
      return 'Face model did not load. Close and reopen the app, then try again.';
    }
    if (lower.contains('spoof')) {
      return 'Live face required. Do not use a photo, screen, or mask — face the camera directly.';
    }

    return 'We could not use this photo. Face the camera, one person only, bright light, no mask — then try again.';
  }

  static bool _isPlainUserFaceMessage(String s) {
    if (s.isEmpty || s.length > 400) return false;
    if (RegExp(r'https?://').hasMatch(s)) return false;
    if (RegExp(r'stacktrace|stack trace|#[0-9]+\s+', caseSensitive: false).hasMatch(s)) return false;
    if (s.contains('Instance of')) return false;
    if (RegExp(r'\b(500|502|503|504)\b').hasMatch(s)) return false;
    if (RegExp(r'Postgrest|ClientException|Xml|JSON', caseSensitive: false).hasMatch(s)) return false;
    return true;
  }

  /// Show professional warning message
  static void showWarning(
    BuildContext context, {
    required String title,
    required String message,
    int durationSeconds = 3,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.accentOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: Duration(seconds: durationSeconds),
      ),
    );
  }

  /// Show professional info message
  static void showInfo(
    BuildContext context, {
    required String title,
    required String message,
    int durationSeconds = 3,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: Duration(seconds: durationSeconds),
      ),
    );
  }

  /// Get professional error message based on error type
  static String getProfessionalErrorMessage(String error) {
    final errorLower = error.toLowerCase();

    if (errorLower.contains('permission') || errorLower.contains('denied')) {
      return 'You don\'t have permission to perform this action. Please contact your administrator.';
    } else if (errorLower.contains('network') ||
        errorLower.contains('connection') ||
        errorLower.contains('internet') ||
        errorLower.contains('offline')) {
      return 'Network connection error. Please check your internet connection and try again.';
    } else if (errorLower.contains('timeout')) {
      return 'Request timed out. Please check your connection and try again.';
    } else if (errorLower.contains('index') ||
        errorLower.contains('firestore') ||
        errorLower.contains('postgres') ||
        errorLower.contains('supabase')) {
      return 'This action could not be completed. Please try again later or contact your institute administrator.';
    } else if (errorLower.contains('invalid') || errorLower.contains('validation')) {
      return 'Invalid input detected. Please check your entries and try again.';
    } else if (errorLower.contains('not found') || errorLower.contains('missing')) {
      return 'The requested information was not found. Please verify and try again.';
    } else if (errorLower.contains('already exists') || errorLower.contains('duplicate')) {
      return 'This record already exists. Please check for duplicates.';
    } else if (errorLower.contains('location') || errorLower.contains('gps')) {
      return 'Location services are required. Please enable GPS and location permissions.';
    } else if (errorLower.contains('camera') || errorLower.contains('photo')) {
      return 'Camera access is required. Please enable camera permissions in settings.';
    } else if (errorLower.contains('face') || errorLower.contains('recognition')) {
      return 'Photo verification did not succeed. Try again with good lighting and your face clearly visible.';
    }
    return 'Something went wrong. Please try again. If the problem continues, contact your institute administrator.';
  }

  /// Build instruction card widget
  static Widget buildInstructionCard({
    required String title,
    required List<String> steps,
    IconData icon = Icons.info_outline,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...steps.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${entry.key + 1}. ${entry.value}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Build help tooltip
  static Widget buildHelpTooltip(String message) {
    return Tooltip(
      message: message,
      child: Icon(
        Icons.help_outline,
        color: Colors.white.withValues(alpha: 0.7),
        size: 18,
      ),
    );
  }
}
