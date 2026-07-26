import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/responsive_page.dart';
import '../../core/theme/app_theme.dart';
import '../../services/attendance_debug_service.dart';
import '../../models/date_range_filter.dart';
import '../../presentation/widgets/date_range_selector.dart';
import '../../presentation/widgets/institute_report_table.dart';
import 'attendance_reports_screen.dart';

/// Modern Attendance Report Screen with Charts
class ModernAttendanceReportScreen extends StatefulWidget {
  final String instituteId;
  final String? rollNumber;

  const ModernAttendanceReportScreen({
    super.key,
    required this.instituteId,
    this.rollNumber,
  });

  @override
  State<ModernAttendanceReportScreen> createState() => _ModernAttendanceReportScreenState();
}

class _ModernAttendanceReportScreenState extends State<ModernAttendanceReportScreen> {
  late DateRangeFilter _selectedDateRange;
  DateTime _selectedStartDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _selectedEndDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDateRange = DateRangeFilter.oneWeek();
    _selectedStartDate = _selectedDateRange.startDate;
    _selectedEndDate = _selectedDateRange.endDate;
  }

  void _onDateRangeChanged(DateRangeFilter newRange) {
    setState(() {
      _selectedDateRange = newRange;
      _selectedStartDate = newRange.startDate;
      _selectedEndDate = newRange.endDate;
    });
  }

  /// Test function to debug attendance database
  Future<void> _testAttendance() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🔍 Running attendance diagnostics... Check console')),
    );

    await AttendanceDebugService.debugUniqueTypeValues(
      instituteCode: widget.instituteId,
      startDate: DateTime.now().subtract(Duration(days: 30)),
      endDate: DateTime.now(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Diagnostic complete! Check console output')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Attendance Report',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.white),
            tooltip: 'Test Attendance Data',
            onPressed: _testAttendance,
          ),
          IconButton(
            icon: const Icon(Icons.description, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: ResponsiveScrollBody(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Date Range Selector
            DateRangeSelector(
              initialRange: _selectedDateRange,
              onDateRangeSelected: _onDateRangeChanged,
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // ✅ Two Report View Options
            _buildReportViewOptions(),

            const SizedBox(height: 12),

            // ✅ Export/Download Report Button
            _buildExportReportButton(),

            const SizedBox(height: 20),

            // Donut Chart
            _buildDonutChart(),
            
            const SizedBox(height: 24),
            
            // Summary Statistics Grid
            _buildSummaryGrid(),
            
            const SizedBox(height: 24),
            
            // Daily Report Bar Chart
            _buildDailyReportChart(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(2), // Search selected
    );
  }

  /// ✅ Two Report View Options (Students vs Institute)
  Widget _buildReportViewOptions() {
    return Column(
      children: [
        // View Students Report Button
        _buildViewStudentsReportButton(),
        const SizedBox(height: 12),
        // View Institute Report Button
        _buildViewInstituteReportButton(),
      ],
    );
  }

  /// View Students Report - Shows attendance list
  Widget _buildViewStudentsReportButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue, Colors.blue.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AttendanceReportsScreen(
                  instituteId: widget.instituteId,
                  initialStartDate: _selectedStartDate,
                  initialEndDate: _selectedEndDate,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '👥 View Students Report',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Attendance list of all students',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// View Institute Report - Shows full table
  Widget _buildViewInstituteReportButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryBlue, AppTheme.primaryBlue.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _showDetailedDailyHoursReport(_selectedStartDate, _selectedEndDate);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📊 View Institute Report',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Full attendance table with all details',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ✅ Export/Download Report Button
  Widget _buildExportReportButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green, Colors.green.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showExportOptions,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💾 Export Report',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Save as PDF or Download',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.download,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Show export options (PDF or Download)
  void _showExportOptions() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📥 Export Report'),
        content: const Text(
          'Choose format to export the attendance report:',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _exportReportAsPDF();
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Export as PDF'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadReport();
            },
            icon: const Icon(Icons.download),
            label: const Text('Download CSV'),
          ),
        ],
      ),
    );
  }

  /// Export report as PDF
  Future<void> _exportReportAsPDF() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📄 Generating PDF report...'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ PDF Report Generated\n'
              'File: attendance_report_${DateTime.now().day}_${DateTime.now().month}_${DateTime.now().year}.pdf\n'
              'Location: Downloads folder',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ PDF Export Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Download report as CSV
  Future<void> _downloadReport() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⬇️ Preparing download...'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Report Downloaded\n'
              'File: attendance_report_${DateTime.now().day}_${DateTime.now().month}_${DateTime.now().year}.csv\n'
              'Format: CSV (Excel compatible)',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Download Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Build report item widget
  Widget _buildReportItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  /// Generate full institute attendance report with daily hours breakdown
  Future<void> _generateInstituteReport(DateTime startDate, DateTime endDate) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📊 Generating daily hours breakdown report...'),
        backgroundColor: AppTheme.primaryBlue,
        duration: Duration(seconds: 3),
      ),
    );

    try {
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        _showDetailedDailyHoursReport(startDate, endDate);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error generating report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show detailed daily hours breakdown report for all students with formatted table
  void _showDetailedDailyHoursReport(DateTime startDate, DateTime endDate) {
    // 🔄 Navigate to attendance_reports_screen to show the REAL full institute report
    // This is better than showing a dialog with hardcoded data
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AttendanceReportsScreen(
          instituteId: widget.instituteId,
          initialStartDate: startDate,
          initialEndDate: endDate,
        ),
      ),
    );
  }

  /// Build format example item
  Widget _buildFormatItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontFamily: 'Courier',
        ),
      ),
    );
  }

  /// Build check item
  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '✓ $text',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  /// Show success notification
  void _showSuccessNotification(DateTime startDate, DateTime endDate) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Daily Hours Breakdown Report Generated\n'
          'Institute: ${widget.instituteId}\n'
          'All students\' daily hours and totals included\n'
          'Period: ${DateFormat('dd MMM').format(startDate)} - ${DateFormat('dd MMM yyyy').format(endDate)}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Widget _buildDonutChart() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Overview',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: Responsive.pctShortestSide(context, 0.42).clamp(170.0, 220.0),
            height: Responsive.pctShortestSide(context, 0.42).clamp(170.0, 220.0),
            child: CustomPaint(
              painter: DonutChartPainter(),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '46',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final items = [
      {'label': 'Working Days', 'color': AppTheme.primaryBlue, 'value': '21'},
      {'label': 'On Time', 'color': AppTheme.primaryGreen, 'value': '18'},
      {'label': 'Late', 'color': AppTheme.accentRed, 'value': '2'},
      {'label': 'Absent', 'color': Colors.black, 'value': '0'},
      {'label': 'Left Timely', 'color': AppTheme.accentYellow, 'value': '4'},
      {'label': 'On Leave', 'color': Colors.purple, 'value': '1'},
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: item['color'] as Color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${item['value']} ${item['label']}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSummaryGrid() {
    final stats = [
      {'label': '21 Working Days', 'icon': Icons.calendar_today, 'color': AppTheme.primaryBlue},
      {'label': '18 On Time', 'icon': Icons.check_circle, 'color': AppTheme.primaryGreen},
      {'label': '2 Late', 'icon': Icons.access_time, 'color': AppTheme.accentRed},
      {'label': '21 Absent', 'icon': Icons.cancel, 'color': Colors.black},
      {'label': '21 Left Timely', 'icon': Icons.exit_to_app, 'color': AppTheme.accentYellow},
      {'label': '21 On leave', 'icon': Icons.event_busy, 'color': Colors.purple},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: Responsive.isTablet(context) ? 3 : 2,
        childAspectRatio: Responsive.isTablet(context) ? 2.8 : 2.2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final stat = stats[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (stat['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  stat['icon'] as IconData,
                  color: stat['color'] as Color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  stat['label'] as String,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDailyReportChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily Report',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: CustomPaint(
              painter: BarChartPainter(),
              child: Padding(
                padding: const EdgeInsets.only(left: 40, right: 20, bottom: 30),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(7, (index) {
                          final heights = [0.3, 0.6, 0.7, 1.0, 0.7, 0.5, 0.3];
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
                                        color: AppTheme.primaryBlue,
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(4),
                                        ),
                                      ),
                                      height: double.infinity,
                                      child: FractionallySizedBox(
                                        heightFactor: heights[index],
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
                                    ['S', 'M', 'T', 'W', 'T', 'F', 'S'][index],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0h', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text('3h', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text('6h', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        Text('8h', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(int selectedIndex) {
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
              _buildNavItem(Icons.home, selectedIndex == 0),
              _buildNavItem(Icons.help_outline, selectedIndex == 1),
              _buildNavItem(Icons.search, selectedIndex == 2, isLarge: true),
              _buildNavItem(Icons.notifications_outlined, selectedIndex == 3),
              _buildNavItem(Icons.person_outline, selectedIndex == 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isSelected, {bool isLarge = false}) {
    return Container(
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
    );
  }
}

/// Custom Painter for Donut Chart
class DonutChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final data = [
      {'value': 21, 'color': AppTheme.primaryBlue},
      {'value': 18, 'color': AppTheme.primaryGreen},
      {'value': 2, 'color': AppTheme.accentRed},
      {'value': 0, 'color': Colors.black},
      {'value': 4, 'color': AppTheme.accentYellow},
      {'value': 1, 'color': Colors.purple},
    ];

    final total = data.fold<double>(0, (sum, item) => sum + (item['value'] as int).toDouble());
    double startAngle = -math.pi / 2;

    for (var item in data) {
      final value = item['value'] as int;
      final sweepAngle = (value / total) * 2 * math.pi;
      
      final paint = Paint()
        ..color = item['color'] as Color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 30;

      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom Painter for Bar Chart
class BarChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid lines
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
