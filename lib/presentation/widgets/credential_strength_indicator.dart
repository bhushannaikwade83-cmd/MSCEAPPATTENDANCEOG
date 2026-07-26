import 'package:flutter/material.dart';

import '../../core/credential_strength.dart';
import '../../core/theme/app_theme.dart';

/// Compact strength meter for passwords or PINs.
class CredentialStrengthIndicator extends StatelessWidget {
  const CredentialStrengthIndicator({
    super.key,
    required this.analysis,
    this.dense = false,
    this.forPin = false,
  });

  final CredentialStrengthAnalysis analysis;
  final bool dense;
  final bool forPin;

  @override
  Widget build(BuildContext context) {
    if (analysis.level == CredentialStrengthLevel.empty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color weakColor = AppTheme.accentRed;
    final Color mediumColor = Colors.orange.shade700;
    final Color strongColor = AppTheme.primaryGreen;

    final Color activeColor = switch (analysis.level) {
      CredentialStrengthLevel.weak => weakColor,
      CredentialStrengthLevel.medium => mediumColor,
      CredentialStrengthLevel.strong => strongColor,
      CredentialStrengthLevel.empty => Colors.transparent,
    };

    final fill = switch (analysis.level) {
      CredentialStrengthLevel.weak => 0.33,
      CredentialStrengthLevel.medium => 0.66,
      CredentialStrengthLevel.strong => 1.0,
      CredentialStrengthLevel.empty => 0.0,
    };

    final label = CredentialStrengthAnalysis.label(analysis.level);
    final subtitle = analysis.hint;

    return Padding(
      padding: EdgeInsets.only(top: dense ? 6 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                forPin ? 'PIN strength: ' : 'Password strength: ',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isDark ? Colors.white70 : AppTheme.textGray,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: activeColor,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          SizedBox(height: dense ? 5 : 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fill,
              minHeight: dense ? 4 : 5,
              backgroundColor:
                  isDark ? Colors.white12 : AppTheme.dividerColor.withValues(alpha: 0.6),
              valueColor: AlwaysStoppedAnimation<Color>(activeColor),
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            SizedBox(height: dense ? 5 : 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isDark ? Colors.white60 : AppTheme.textGray,
                    height: 1.25,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
