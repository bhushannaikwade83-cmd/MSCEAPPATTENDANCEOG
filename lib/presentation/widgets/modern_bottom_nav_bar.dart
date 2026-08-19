import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:ui' as ui;
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';

/// 🔥 Ultra-Modern Bottom Navigation Bar with Glassmorphism & Animations
class ModernBottomNavBar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onTap;
  final String? instituteId;

  const ModernBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    this.instituteId,
  });

  @override
  State<ModernBottomNavBar> createState() => _ModernBottomNavBarState();
}

class _ModernBottomNavBarState extends State<ModernBottomNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const GovTricolorStrip(),
        // Modern bottom nav with glassmorphism effect
        ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28.r),
            topRight: Radius.circular(28.r),
          ),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.grey.shade900.withOpacity(0.9)
                    : Colors.white.withOpacity(0.95),
                border: Border(
                  top: BorderSide(
                    color: AppTheme.primaryBlue.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -8),
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildAnimatedNavItem(
                        context,
                        icon: Icons.home_rounded,
                        label: 'Home',
                        index: 0,
                        isDark: isDark,
                      ),
                      // Hide ADD button for institute 90999 (employees)
                      if (widget.instituteId != '90999')
                        _buildAnimatedNavItem(
                          context,
                          icon: Icons.person_add_rounded,
                          label: 'Add',
                          index: 1,
                          isDark: isDark,
                        ),
                      _buildAnimatedNavItem(
                        context,
                        icon: Icons.people_rounded,
                        label: widget.instituteId == '90999' ? 'Employees' : 'Students',
                        index: 2,
                        isDark: isDark,
                      ),
                      _buildAnimatedNavItem(
                        context,
                        icon: Icons.location_on_rounded,
                        label: 'GPS',
                        index: 3,
                        isDark: isDark,
                      ),
                      _buildAnimatedNavItem(
                        context,
                        icon: Icons.bar_chart_rounded,
                        label: widget.instituteId == '90999' ? 'Employee Reports' : 'Reports',
                        index: 4,
                        isDark: isDark,
                      ),
                      _buildAnimatedNavItem(
                        context,
                        icon: Icons.assessment_rounded,
                        label: 'Institute',
                        index: 5,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int index,
    required bool isDark,
  }) {
    final isSelected = widget.selectedIndex == index;

    return GestureDetector(
      onTap: () {
        _animController.forward(from: 0);
        widget.onTap(index);
      },
      child: ScaleTransition(
        scale: isSelected
            ? Tween<double>(begin: 1, end: 1.15).animate(
                CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
              )
            : AlwaysStoppedAnimation(1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon container with gradient
            Container(
              width: 52.w,
              height: 52.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isSelected
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primaryBlue.withOpacity(0.2),
                          AppTheme.primaryBlue.withOpacity(0.08),
                        ],
                      )
                    : null,
                border: isSelected
                    ? Border.all(
                        color: AppTheme.primaryBlue.withOpacity(0.5),
                        width: 2,
                      )
                    : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppTheme.primaryBlue.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade400,
                size: 26.sp,
              ),
            ),
            SizedBox(height: 4.h),
            // Label with smooth text color transition
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: TextStyle(
                fontSize: isSelected ? 11.sp : 9.sp,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? AppTheme.primaryBlue
                    : (isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                letterSpacing: 0.3,
              ),
              child: Text(label),
            ),
            if (isSelected) ...[
              SizedBox(height: 3.h),
              // Animated dot indicator
              ScaleTransition(
                scale: CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
                child: Container(
                  width: 6.w,
                  height: 6.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primaryGreen,
                        AppTheme.primaryBlue,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withOpacity(0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
