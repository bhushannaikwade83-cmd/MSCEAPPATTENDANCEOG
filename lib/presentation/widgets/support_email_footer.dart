import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';

/// MSCE Attendance App support inbox (shown on login + admin dashboard).
const String kGccTbcSupportEmail = 'gcc-tbcsupport@gmail.com';

Future<void> launchGccTbcSupportEmail() async {
  final uri = Uri.parse(
    'mailto:$kGccTbcSupportEmail?subject=${Uri.encodeComponent('Attendance App — Support')}',
  );
  try {
    await launchUrl(uri);
  } catch (_) {}
}

/// Compact “Issues or support” line with tappable mail link.
class SupportEmailFooter extends StatelessWidget {
  const SupportEmailFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtle = isDark ? Colors.white54 : AppTheme.textGray;
    final linkColor = isDark ? const Color(0xFF90CAF9) : AppTheme.primaryBlue;

    return Semantics(
      button: true,
      label: 'Email support at $kGccTbcSupportEmail',
      child: InkWell(
        onTap: launchGccTbcSupportEmail,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 10,
                height: 1.35,
                color: subtle,
              ),
              children: [
                const TextSpan(text: 'Issues or support: '),
                TextSpan(
                  text: kGccTbcSupportEmail,
                  style: TextStyle(
                    color: linkColor,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: linkColor,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
