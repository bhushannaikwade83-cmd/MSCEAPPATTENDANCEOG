import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_attendance_app/l10n/app_localizations.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SINGLE UI FILE — change [AppTheme] (colors/themes) and [AppUI] (shell/branding)
// to restyle the whole app. Elsewhere: import '.../core/theme/app_theme.dart'.
// ═══════════════════════════════════════════════════════════════════════════════

/// Branding copy, shell layout, and tricolor (portal header / bottom bar).
abstract final class AppUI {
  static const String portalPrimaryLine =
      'MSCE Attendance App  |  एमएससीई उपस्थिती अॅप';
  static const String portalSecondaryLineDefault =
      'MSCE Smart Attendance Management System';
  static const String officialBadgeLabel = 'OFFICIAL';
  static const String footerOfficialUse = 'OFFICIAL USE ONLY';
  static const String footerCredit =
      'Powered by MSCE - Maharashtra State Council of Education';

  /// In-app and launcher branding (assets/msce_attendance_app_logo.png).
  static const String appLogoAsset = 'assets/msce_attendance_app_logo.png';

  /// Width ÷ height of [appLogoAsset] in pixels (avoids cropping in square boxes).
  static const double appLogoAspectRatio = 1.0;

  /// Splash / login: app logo.
  static Widget dualBrandLogos({
    required double mainHeight,
    double partnerScale = 0.55,
  }) {
    return Image.asset(appLogoAsset, height: mainHeight, fit: BoxFit.contain);
  }

  /// Caps logo width using viewport **fractions** so the logo block (with [appLogoAspectRatio])
  /// does not overflow short or landscape screens. [contentWidth] = horizontal space for the logo.
  static double bodyLogoMaxWidth(double contentWidth, double viewportHeight) {
    final w = contentWidth.isFinite && contentWidth > 0
        ? contentWidth
        : viewportHeight > 0 && viewportHeight.isFinite
            ? viewportHeight * 0.85
            : 320.0;
    final h = viewportHeight.isFinite && viewportHeight > 0
        ? viewportHeight
        : 600.0;
    final capByWidth = w * 0.92;
    final capByHeight = h * 0.26 * appLogoAspectRatio;
    return capByWidth < capByHeight ? capByWidth : capByHeight;
  }

  static const IconData portalLeadingIcon = Icons.account_balance_rounded;

  static const double govCardBorderRadius = 14;
  static const double govCardInnerClipRadius = 13;
  static const double govCardAccentStripWidth = 4;
  static const double tricolorStripHeight = 5;
  static const double officialBadgeCornerRadius = 6;

  static const Color tricolorSaffronStart = Color(0xFFFF6600);
  static const Color tricolorSaffronEnd = Color(0xFFFF9933);
  static const Color tricolorGreenStart = Color(0xFF006600);
  static const Color tricolorGreenEnd = Color(0xFF138808);
  static const Color officialBadgeColor = Color(0xFFE8871A);

  static const Color headerShadowColor = Color(0x44000000);

  /// Subtitle under the portal header for each main bottom-nav tab (order matches bar).
  static const List<String> mainNavSecondaryLines = <String>[
    'Admin dashboard  |  प्रशासक डॅशबोर्ड',
    'Instructor accounts  |  प्रशिक्षक खाती',
    'Student records  |  विद्यार्थी नोंदी',
    'GPS geofence  |  स्थान सीमा सेटिंग्ज',
    'Attendance reports  |  उपस्थिती अहवाल',
  ];
}

class AppTheme {
  // ─── INDIAN GOVERNMENT DESIGN SYSTEM ───────────────────────────────────────
  // Inspired by NIC, DigiLocker, UMANG, eGov portals

  // Primary – Deep Government Navy Blue
  static const Color primaryBlue      = Color(0xFF1A3C6E);
  static const Color primaryBlueDark  = Color(0xFF0F2547);
  static const Color primaryBlueLight = Color(0xFF2B5BA0);

  // Accent – Government Saffron / Orange (Indian tricolor)
  static const Color accentSaffron    = Color(0xFFE8871A);
  static const Color saffronLight     = Color(0xFFFFF3E0);

  // Success – Government Green (Indian tricolor)
  static const Color primaryGreen     = Color(0xFF1B5E20);
  static const Color accentGreen      = Color(0xFF388E3C);
  static const Color greenLight       = Color(0xFFE8F5E9);

  // Warning / Amber
  static const Color accentOrange     = Color(0xFFF57F17);
  static const Color orangeLight      = Color(0xFFFFF8E1);
  static const Color orangeBackground = Color(0xFFFFF3E0);

  // Error / Red
  static const Color accentRed        = Color(0xFFB71C1C);
  static const Color redLight         = Color(0xFFFFEBEE);
  static const Color redBackground    = Color(0xFFFFCDD2);

  // Yellow (pending/status)
  static const Color accentYellow     = Color(0xFFF9A825);
  static const Color yellowLight      = Color(0xFFFFF9C4);
  static const Color yellowBackground = Color(0xFFFFFDE7);

  // Neutrals
  static const Color darkCharcoal     = Color(0xFF1A1A2E);
  static const Color backgroundOffWhite = Color(0xFFF0F2F7);
  static const Color backgroundGrey   = Color(0xFFEEF2F7);
  static const Color cardWhite        = Color(0xFFFFFFFF);
  static const Color textDark         = Color(0xFF1A1A2E);
  static const Color textGray         = Color(0xFF5A6475);
  static const Color textLightGray    = Color(0xFF9EA8B8);
  static const Color dividerColor     = Color(0xFFDDE3EE);

  // Government Header/Banner Colors
  static const Color govHeaderBlue    = Color(0xFF0D2E5F);
  static const Color govBannerSaffron = Color(0xFFFF8C00);
  static const Color govGreen         = Color(0xFF006400);

  // NEW: Supporting Colors for Enhanced Design
  static const Color primaryBlueLighter = Color(0xFFE3F2FD);
  static const Color borderLight        = Color(0xFFD5E8F7);
  static const Color disabledGray       = Color(0xFFE8EAED);
  static const Color focusRing          = Color(0xFF2B5BA0);

  // Legacy aliases for compatibility
  static const Color accentMint       = greenLight;
  static const Color secondaryBlue    = primaryBlueLight;
  static const Color backgroundLight  = backgroundOffWhite;

  // ─── LIGHT THEME ────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData.light(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentSaffron,
        surface: cardWhite,
        error: accentRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textDark,
      ),
      scaffoldBackgroundColor: backgroundGrey,
      textTheme: GoogleFonts.notoSansTextTheme(
        ThemeData.light(useMaterial3: true).textTheme,
      ).copyWith(
        displayLarge: GoogleFonts.notoSans(
          fontSize: 36, fontWeight: FontWeight.bold,
          color: textDark, letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.notoSans(
          fontSize: 28, fontWeight: FontWeight.bold,
          color: textDark, letterSpacing: -0.3,
        ),
        headlineMedium: GoogleFonts.notoSans(
          fontSize: 22, fontWeight: FontWeight.w700,
          color: primaryBlue, letterSpacing: -0.2,
        ),
        titleLarge: GoogleFonts.notoSans(
          fontSize: 18, fontWeight: FontWeight.w600,
          color: textDark,
        ),
        bodyLarge: GoogleFonts.notoSans(
          fontSize: 15, color: textDark, fontWeight: FontWeight.w400,
        ),
        bodyMedium: GoogleFonts.notoSans(
          fontSize: 13, color: textGray, fontWeight: FontWeight.w400,
        ),
        labelLarge: GoogleFonts.notoSans(
          fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 2,
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        titleTextStyle: GoogleFonts.notoSans(
          fontSize: 18, fontWeight: FontWeight.w700,
          color: Colors.white, letterSpacing: 0.2,
        ),
        iconTheme: const IconThemeData(color: Colors.white, size: 24),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: primaryBlue.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.notoSans(
            fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.8,
          ),
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith<double>(
            (states) {
              if (states.contains(WidgetState.pressed)) return 1;
              if (states.contains(WidgetState.hovered)) return 4;
              return 2;
            },
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryBlue,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          side: const BorderSide(color: primaryBlue, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.notoSans(
            fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryBlue,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: GoogleFonts.notoSans(
            fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: cardWhite,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: dividerColor, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: dividerColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryBlue, width: 2.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accentRed, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accentRed, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: GoogleFonts.notoSans(
          fontSize: 13, fontWeight: FontWeight.w500, color: textGray,
        ),
        hintStyle: GoogleFonts.notoSans(
          fontSize: 13, color: textLightGray,
        ),
        prefixIconColor: textGray,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: primaryBlue.withValues(alpha: 0.08),
        labelStyle: GoogleFonts.notoSans(
          fontSize: 12, fontWeight: FontWeight.w500, color: primaryBlue,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 0,
      ),
    );
  }

  // ─── DARK THEME ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlueLight,
        secondary: accentSaffron,
        surface: const Color(0xFF1E293B),
        error: accentRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0D1B2E),
      textTheme: GoogleFonts.notoSansTextTheme(
        ThemeData.dark(useMaterial3: true).textTheme,
      ).copyWith(
        displayLarge: GoogleFonts.notoSans(
          fontSize: 36, fontWeight: FontWeight.bold,
          color: Colors.white, letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.notoSans(
          fontSize: 28, fontWeight: FontWeight.bold,
          color: Colors.white, letterSpacing: -0.3,
        ),
        headlineMedium: GoogleFonts.notoSans(
          fontSize: 22, fontWeight: FontWeight.w700,
          color: const Color(0xFF93B4E0), letterSpacing: -0.2,
        ),
        titleLarge: GoogleFonts.notoSans(
          fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white,
        ),
        bodyLarge: GoogleFonts.notoSans(
          fontSize: 15, color: Colors.white.withValues(alpha: 0.9),
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: GoogleFonts.notoSans(
          fontSize: 13, color: Colors.white.withValues(alpha: 0.7),
          fontWeight: FontWeight.w400,
        ),
        labelLarge: GoogleFonts.notoSans(
          fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.5,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: const Color(0xFF0F2547),
        foregroundColor: Colors.white,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        titleTextStyle: GoogleFonts.notoSans(
          fontSize: 18, fontWeight: FontWeight.w700,
          color: Colors.white, letterSpacing: 0.2,
        ),
        iconTheme: const IconThemeData(color: Colors.white, size: 24),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlueLight,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.notoSans(
            fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.8,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF93B4E0),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          side: const BorderSide(color: Color(0xFF93B4E0), width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.notoSans(
            fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF93B4E0),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: GoogleFonts.notoSans(
            fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF1E293B),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade700, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade700, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryBlueLight, width: 2.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accentRed, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accentRed, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: GoogleFonts.notoSans(
          fontSize: 13, fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: 0.7),
        ),
        hintStyle: GoogleFonts.notoSans(
          fontSize: 13, color: Colors.white.withValues(alpha: 0.4),
        ),
        prefixIconColor: Colors.white54,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: primaryBlueLight.withValues(alpha: 0.2),
        labelStyle: GoogleFonts.notoSans(
          fontSize: 12, fontWeight: FontWeight.w500,
          color: primaryBlueLight,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────────

  /// Government-style solid button gradient (subtle)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryBlueDark, primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Saffron accent gradient for badges
  static const LinearGradient saffronGradient = LinearGradient(
    colors: [Color(0xFFE8871A), Color(0xFFF4A830)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Card decoration with uniform border (use ClipRRect + inner Row for left accent)
  static BoxDecoration get govCardDecoration => BoxDecoration(
    color: cardWhite,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: dividerColor, width: 1),
    boxShadow: cardShadow,
  );

  /// Subtle card shadow
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.07),
      blurRadius: 12,
      offset: const Offset(0, 3),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static BoxDecoration get primaryGradientDecoration => BoxDecoration(
    gradient: primaryGradient,
    borderRadius: BorderRadius.circular(8),
    boxShadow: [
      BoxShadow(
        color: primaryBlue.withValues(alpha: 0.35),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

// ─── SHARED SHELL WIDGETS (driven by [AppUI] + [AppTheme]) ───────────────────

class GovTricolorStrip extends StatelessWidget {
  const GovTricolorStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: AppUI.tricolorStripHeight,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppUI.tricolorSaffronStart, AppUI.tricolorSaffronEnd],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: AppUI.tricolorStripHeight,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
        Expanded(
          child: Container(
            height: AppUI.tricolorStripHeight,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppUI.tricolorGreenStart, AppUI.tricolorGreenEnd],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class GovPortalHeader extends StatefulWidget {
  /// When null, uses [AppLocalizations] for the active locale (en / mr).
  final String? primaryLine;
  final String? secondaryLine;

  const GovPortalHeader({
    super.key,
    this.primaryLine,
    this.secondaryLine,
  });

  @override
  State<GovPortalHeader> createState() => _GovPortalHeaderState();
}

class _GovPortalHeaderState extends State<GovPortalHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _logoAnimController;
  late Animation<double> _logoScale;
  late Animation<double> _logoPulse;

  @override
  void initState() {
    super.initState();
    _logoAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _logoScale =
        CurvedAnimation(parent: _logoAnimController, curve: Curves.elasticOut);
    _logoPulse = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _logoAnimController, curve: Curves.easeInOut),
    );
    // Run animation once only, not continuously (saves battery)
    _logoAnimController.forward();
  }

  @override
  void dispose() {
    _logoAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = widget.primaryLine ?? l10n.portalPrimaryLine;
    final s = widget.secondaryLine ?? l10n.portalSecondaryLineDefault;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.primaryBlueDark : AppTheme.primaryBlueDark,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GovTricolorStrip(),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                child: Row(
                  children: [
                    // 🎯 Animated Logo with enhanced glow
                    ScaleTransition(
                      scale: _logoPulse,
                      child: Container(
                        width: 56.r,
                        height: 56.r,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.95),
                              Colors.white.withValues(alpha: 0.80),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.6),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.5),
                              blurRadius: 16,
                              offset: const Offset(0, 2),
                              spreadRadius: 3,
                            ),
                            BoxShadow(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.4),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: AppTheme.accentSaffron.withValues(alpha: 0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        padding: EdgeInsets.all(4.r),
                        child: Image.asset(
                          AppUI.appLogoAsset,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    SizedBox(width: 14.w),

                    // 📱 Name Section with improved typography
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // English line
                          Text(
                            p.split('|').first.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5.sp,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              height: 1.2,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.3),
                                  offset: const Offset(0, 2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 2.h),
                          // Marathi line
                          Text(
                            p.split('|').length > 1 ? p.split('|').last.trim() : '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.2),
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 2.h),
                          // Secondary line English
                          Text(
                            s.split('|').first.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.70),
                              fontSize: 9.5.sp,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.1,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.2),
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          // Secondary line Marathi (if exists)
                          if (s.split('|').length > 1)
                            Text(
                              s.split('|').last.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.60),
                                fontSize: 9.sp,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.1,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.2),
                                    offset: const Offset(0, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: 10.w),

                    // 🏆 Ultra-premium Official Badge with glassmorphism
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 7.h),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppUI.officialBadgeColor.withOpacity(0.9),
                            AppUI.officialBadgeColor.withOpacity(0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppUI.officialBadgeColor.withValues(alpha: 0.6),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.95, end: 1.05),
                        duration: const Duration(milliseconds: 1500),
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: child,
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_user_rounded,
                              color: Colors.white,
                              size: 11.sp,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.3),
                                  offset: const Offset(0, 2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            SizedBox(width: 5.w),
                            Text(
                              l10n.officialBadge,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}

class GovElevatedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GovElevatedCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppUI.govCardBorderRadius),
        border: Border.all(color: AppTheme.dividerColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppUI.govCardInnerClipRadius),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: AppTheme.primaryBlue,
                width: AppUI.govCardAccentStripWidth,
              ),
            ),
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class GovPortalFooter extends StatelessWidget {
  const GovPortalFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: AppTheme.dividerColor)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              child: Text(
                l10n.footerOfficialUse,
                style: TextStyle(
                  fontSize: 10.sp,
                  color: AppTheme.textLightGray,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const Expanded(child: Divider(color: AppTheme.dividerColor)),
          ],
        ),
        SizedBox(height: 10.h),
        Text(
          l10n.footerCredit,
          style: TextStyle(
            fontSize: 11.sp,
            color: AppTheme.textLightGray,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8.h),
        const GovTricolorStrip(),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPACING SYSTEM — Use this for all margins, padding, gaps (consistency)
// ═══════════════════════════════════════════════════════════════════════════════
abstract final class AppSpacing {
  static const double xs = 4;    // Extra small
  static const double sm = 8;    // Small
  static const double md = 12;   // Medium
  static const double lg = 16;   // Large
  static const double xl = 24;   // Extra large
  static const double xxl = 32;  // Extra extra large

  // Commonly used combinations
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);

  static const EdgeInsets paddingHorizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingHorizontalLg = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets paddingVerticalMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingVerticalLg = EdgeInsets.symmetric(vertical: lg);

  // Card and component spacing
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(horizontal: lg, vertical: md);
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(horizontal: lg, vertical: md);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANIMATION DURATIONS — Consistent micro-interaction timings
// ═══════════════════════════════════════════════════════════════════════════════
abstract final class AppAnimations {
  static const Duration quickFeedback = Duration(milliseconds: 100);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration standardPlus = Duration(milliseconds: 250);
  static const Duration transition = Duration(milliseconds: 300);
  static const Duration delayed = Duration(milliseconds: 500);

  static const Curve easeOut = Curves.easeOut;
  static const Curve easeInOut = Curves.easeInOut;
}

