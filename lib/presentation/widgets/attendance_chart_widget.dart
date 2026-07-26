import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/app_db.dart';
import '../../core/supabase_maps.dart';
import '../../core/theme/app_theme.dart';

/// Basic Attendance Chart Widget - Shows attendance trends
class AttendanceChartWidget extends StatefulWidget {
  final String instituteId;
  final int days; // Number of days to show

  const AttendanceChartWidget({
    super.key,
    required this.instituteId,
    this.days = 7,
  });

  @override
  State<AttendanceChartWidget> createState() => _AttendanceChartWidgetState();
}

class _AttendanceChartWidgetState extends State<AttendanceChartWidget> {
  Timer? _timer;
  Map<String, int> _dateCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: widget.days - 1));
    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(endDate);
    try {
      final code = await instituteCodeForId(widget.instituteId);
      final rows = await appDb
          .from('attendance_in_out')
          .select('attendance_date')
          .eq('institute_code', code)
          .gte('attendance_date', startStr)
          .lte('attendance_date', endStr);

      final Map<String, int> dateCounts = {};
      for (final r in rows) {
        final m = r as Map<String, dynamic>;
        final date = m['attendance_date']?.toString();
        if (date != null) {
          dateCounts[date] = (dateCounts[date] ?? 0) + 1;
        }
      }
      if (mounted) {
        setState(() {
          _dateCounts = dateCounts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: widget.days - 1));

    if (_loading) {
      return Container(
        height: 200,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final dateCounts = _dateCounts;

    final maxCount = dateCounts.values.isEmpty
        ? 1
        : dateCounts.values.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.show_chart,
                color: AppTheme.primaryBlue,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Attendance Trend (Last ${widget.days} Days)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(widget.days, (index) {
                final date = startDate.add(Duration(days: index));
                final dateStr = DateFormat('yyyy-MM-dd').format(date);
                final count = dateCounts[dateStr] ?? 0;
                final height = maxCount > 0 ? (count / maxCount) : 0.0;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: count > 0 ? AppTheme.primaryBlue : Colors.grey.shade300,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                            height: double.infinity,
                            child: FractionallySizedBox(
                              heightFactor: height,
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryBlue,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d').format(date),
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white.withValues(alpha: 0.6) : AppTheme.textGray,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
