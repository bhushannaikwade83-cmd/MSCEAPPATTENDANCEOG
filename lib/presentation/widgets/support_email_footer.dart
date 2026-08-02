import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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

/// Modern “Issues or support” footer with gradient styling
class SupportEmailFooter extends StatefulWidget {
  const SupportEmailFooter({super.key});

  @override
  State<SupportEmailFooter> createState() => _SupportEmailFooterState();
}

class _SupportEmailFooterState extends State<SupportEmailFooter> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: 'Email support at $kGccTbcSupportEmail',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: launchGccTbcSupportEmail,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryBlue.withOpacity(isDark ? 0.12 : 0.08),
                  AppTheme.primaryBlue.withOpacity(isDark ? 0.06 : 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: AppTheme.primaryBlue.withOpacity(_isHovered ? 0.4 : 0.2),
                width: 1.5,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mail_outline_rounded,
                  size: 13.sp,
                  color: AppTheme.primaryBlue,
                ),
                SizedBox(width: 5.w),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 10.sp,
                        height: 1.3,
                        color: isDark ? Colors.white70 : AppTheme.textGray,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        const TextSpan(text: 'Support: '),
                        TextSpan(
                          text: 'gcc-tbc',
                          style: TextStyle(
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 9.5.sp,
                            decoration: TextDecoration.underline,
                            decorationColor: AppTheme.primaryBlue,
                            decorationThickness: 1.5,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
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
