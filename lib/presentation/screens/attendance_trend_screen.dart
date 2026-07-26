import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/app_db.dart';
import '../../core/supabase_maps.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/responsive_page.dart';
import '../widgets/attendance_chart_widget.dart';
import '../../core/theme/app_theme.dart';

/// Attendance Trend Screen - Shows attendance trends and analytics
class AttendanceTrendScreen extends StatefulWidget {
  final String instituteId;

  const AttendanceTrendScreen({
    super.key,
    required this.instituteId,
  });

  @override
  State<AttendanceTrendScreen> createState() => _AttendanceTrendScreenState();
}

class _AttendanceTrendScreenState extends State<AttendanceTrendScreen> {
  int _selectedDays = 7;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Trend'),
      ),
      body: ResponsiveScrollBody(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time period selector
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark 
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark 
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Time Period',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildPeriodButton(7, '7 Days'),
                      _buildPeriodButton(14, '14 Days'),
                      _buildPeriodButton(30, '30 Days'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Attendance Chart
            AttendanceChartWidget(
              instituteId: widget.instituteId,
              days: _selectedDays,
            ),
            const SizedBox(height: 24),
            // Additional Statistics
            _buildStatisticsSection(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodButton(int days, String label) {
    final isSelected = _selectedDays == days;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDays = days;
        });
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 88),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryBlue
              : isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryBlue
                : isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : isDark
                    ? Colors.white
                    : AppTheme.textDark,
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadAttendanceRowsForPeriod() async {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: _selectedDays - 1));
    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(endDate);
    final code = await instituteCodeForId(widget.instituteId);
    final rows = await appDb
        .from('attendance_in_out')
        .select('attendance_date')
        .eq('institute_code', code)
        .gte('attendance_date', startStr)
        .lte('attendance_date', endStr);
    return rows.cast<Map<String, dynamic>>();
  }

  Widget _buildStatisticsSection(bool isDark) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(_selectedDays),
      future: _loadAttendanceRowsForPeriod(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data!;
        final totalAttendance = docs.length;
        final avgPerDay = _selectedDays > 0 ? (totalAttendance / _selectedDays) : 0.0;

        // Group by date to find best and worst days
        final Map<String, int> dateCounts = {};
        for (final row in docs) {
          final date = row['attendance_date']?.toString();
          if (date != null) {
            dateCounts[date] = (dateCounts[date] ?? 0) + 1;
          }
        }

        int maxCount = 0;
        int minCount = 0;
        String? bestDay;
        String? worstDay;

        if (dateCounts.isNotEmpty) {
          maxCount = dateCounts.values.reduce((a, b) => a > b ? a : b);
          minCount = dateCounts.values.reduce((a, b) => a < b ? a : b);
          
          bestDay = dateCounts.entries.firstWhere((e) => e.value == maxCount).key;
          worstDay = dateCounts.entries.firstWhere((e) => e.value == minCount).key;
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark 
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.shade300,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.analytics,
                    color: AppTheme.primaryBlue,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Statistics',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Total Attendance',
                      '$totalAttendance',
                      Icons.check_circle,
                      AppTheme.primaryGreen,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Avg/Day',
                      avgPerDay.toStringAsFixed(1),
                      Icons.trending_up,
                      AppTheme.primaryBlue,
                      isDark,
                    ),
                  ),
                ],
              ),
              if (bestDay != null && worstDay != null) ...[
                const SizedBox(height: 16),
                _buildDayStat(
                  'Best Day',
                  bestDay,
                  '$maxCount',
                  AppTheme.primaryGreen,
                  isDark,
                ),
                const SizedBox(height: 12),
                _buildDayStat(
                  'Worst Day',
                  worstDay,
                  '$minCount',
                  AppTheme.accentRed,
                  isDark,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark 
                  ? Colors.white.withValues(alpha: 0.7)
                  : AppTheme.textGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayStat(String label, String date, String count, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark 
                        ? Colors.white.withValues(alpha: 0.7)
                        : AppTheme.textGray,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(date),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$count students',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dateStr);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }
}
