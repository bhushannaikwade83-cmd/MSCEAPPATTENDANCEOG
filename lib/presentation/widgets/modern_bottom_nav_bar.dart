import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';

/// Modern Bottom Navigation Bar - Matches the reference design
/// Features a prominent central search button
class ModernBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTap;

  const ModernBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.pctWidth(context, 0.04).clamp(12.0, 24.0);
    final vPad = Responsive.pctHeight(context, 0.01).clamp(6.0, 12.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const GovTricolorStrip(),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                mainAxisSize: MainAxisSize.max,
                children: [
                  _buildNavItem(
                    context,
                    icon: Icons.home,
                    isSelected: selectedIndex == 0,
                    onTap: () => onTap(0),
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.person_add_alt_1_outlined,
                    isSelected: selectedIndex == 1,
                    onTap: () => onTap(1),
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.people_outlined,
                    isSelected: selectedIndex == 2,
                    onTap: () => onTap(2),
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.location_on_outlined,
                    isSelected: selectedIndex == 3,
                    onTap: () => onTap(3),
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.bar_chart_outlined,
                    isSelected: selectedIndex == 4,
                    onTap: () => onTap(4),
                  ),
                  _buildNavItem(
                    context,
                    icon: Icons.assessment_outlined,
                    isSelected: selectedIndex == 5,
                    onTap: () => onTap(5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final side = Responsive.pctShortestSide(context, 0.105).clamp(36.0, 48.0);
    final iconSize = Responsive.pctShortestSide(context, 0.062).clamp(20.0, 26.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade600,
          size: iconSize,
        ),
      ),
    );
  }

  Widget _buildSearchButton({
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Builder(
        builder: (context) {
          final side = Responsive.pctShortestSide(context, 0.14).clamp(48.0, 60.0);
          return Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryBlue.withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.search,
              color: Colors.white,
              size: side * 0.48,
            ),
          );
        },
      ),
    );
  }
}
