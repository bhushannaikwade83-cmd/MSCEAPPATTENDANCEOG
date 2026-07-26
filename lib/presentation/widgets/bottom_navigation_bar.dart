import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Reusable Bottom Navigation Bar - Modern design
class AppBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTap;

  const AppBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, selectedIndex == 0, () => onTap(0)),
              _buildNavItem(Icons.help_outline, selectedIndex == 1, () => onTap(1)),
              _buildNavItem(Icons.search, selectedIndex == 2, () => onTap(2), isLarge: true),
              _buildNavItem(Icons.notifications_outlined, selectedIndex == 3, () => onTap(3)),
              _buildNavItem(Icons.person_outline, selectedIndex == 4, () => onTap(4)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isSelected, VoidCallback onTap, {bool isLarge = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isLarge ? 50 : 40,
        height: isLarge ? 50 : 40,
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade600,
          size: isLarge ? 28 : 24,
        ),
      ),
    );
  }
}
