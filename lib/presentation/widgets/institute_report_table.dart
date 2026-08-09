import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_theme.dart';

/// Institute Attendance Report Table with all students
class InstituteReportTable extends StatelessWidget {
  final List<Map<String, dynamic>> studentRecords;
  final Map<String, dynamic> totals;
  final Map<String, dynamic> averages;
  final String periodText;
  final Function(Map<String, dynamic> student)? onStudentTap;

  const InstituteReportTable({
    super.key,
    required this.studentRecords,
    required this.totals,
    required this.averages,
    required this.periodText,
    this.onStudentTap,
  });

  String _getStatusEmoji(double attendancePercent) {
    if (attendancePercent >= 100) return '✅';
    if (attendancePercent >= 70) return '⚠️';
    return '❌';
  }

  String _getStatusText(double attendancePercent) {
    if (attendancePercent >= 100) return 'Perfect';
    if (attendancePercent >= 80) return 'Good';
    if (attendancePercent >= 70) return 'Average';
    return 'Poor';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header (Full Width - Spread to edges)
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 16.w),
          decoration: const BoxDecoration(
            color: AppTheme.primaryBlue,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'INSTITUTE ATTENDANCE REPORT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 6.h),
              Row(
                children: [
                  Icon(Icons.calendar_month, color: Colors.white70, size: 14.sp),
                  SizedBox(width: 6.w),
                  Text(
                    'Period: $periodText',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13.sp,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Horizontal scroll for table (Edge to Edge)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Table Header
                Container(
                  color: Colors.grey[100],
                  child: IntrinsicHeight(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCell('Sr No', flex: 0.8, isHeader: true),
                        _buildCell('Student Name', flex: 1.8, isHeader: true),
                        _buildCell('Registered', flex: 1.2, isHeader: true),
                        _buildCell('Present', flex: 0.8, isHeader: true),
                        _buildCell('Absent', flex: 0.8, isHeader: true),
                        _buildCell('Total Hours', flex: 1.5, isHeader: true),
                        _buildCell('Attendance %', flex: 1.2, isHeader: true),
                        _buildCell('Status', flex: 1, isHeader: true),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 1),

                // Table Rows
                ...studentRecords.asMap().entries.map((entry) {
                  final index = entry.key;
                  final student = entry.value;
                  final attendancePercent = student['attendancePercent'] as double;
                  final statusEmoji = _getStatusEmoji(attendancePercent);
                  final statusText = _getStatusText(attendancePercent);

                  return InkWell(
                    onTap: onStudentTap != null ? () => onStudentTap!(student) : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: index % 2 == 0 ? Colors.white : Colors.grey[50],
                        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 0.5)),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildCell('${index + 1}', flex: 0.8),
                            _buildCell(student['name'] ?? '', flex: 1.8),
                            _buildCell(student['registered'] ?? '-', flex: 1.2, textAlign: TextAlign.center),
                            _buildCell('${student['present'] ?? 0}', flex: 0.8, textAlign: TextAlign.center),
                            _buildCell('${student['absent'] ?? 0}', flex: 0.8, textAlign: TextAlign.center),
                            _buildCell(student['totalHours'] ?? '0h 0m 0s', flex: 1.5),
                            _buildCell('${attendancePercent.toStringAsFixed(0)}% $statusEmoji', flex: 1.2),
                            _buildCell(statusText, flex: 1, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),

                // TOTALS Row
                Container(
                  color: AppTheme.primaryBlue.withOpacity(0.08),
                  child: IntrinsicHeight(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCell('', flex: 0.8),
                        _buildCell('TOTAL', flex: 1.8, isBold: true),
                        _buildCell('', flex: 1.2),
                        _buildCell('${totals['totalPresent'] ?? 0}', flex: 0.8, isBold: true, textAlign: TextAlign.center),
                        _buildCell('${totals['totalAbsent'] ?? 0}', flex: 0.8, isBold: true, textAlign: TextAlign.center),
                        _buildCell(totals['totalHours'] ?? '0h 0m 0s', flex: 1.5, isBold: true),
                        _buildCell('${totals['totalAttendancePercent']?.toStringAsFixed(1) ?? '0'}%', flex: 1.2, isBold: true),
                        _buildCell('', flex: 1),
                      ],
                    ),
                  ),
                ),

                // AVERAGE Row
                Container(
                  color: Colors.grey[100],
                  child: IntrinsicHeight(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCell('', flex: 0.8),
                        _buildCell('AVERAGE', flex: 1.8, isBold: true),
                        _buildCell('', flex: 1.2),
                        _buildCell('${(averages['avgPresent'] as num?)?.toStringAsFixed(2) ?? '0'}', flex: 0.8, isBold: true, textAlign: TextAlign.center),
                        _buildCell('${(averages['avgAbsent'] as num?)?.toStringAsFixed(2) ?? '0'}', flex: 0.8, isBold: true, textAlign: TextAlign.center),
                        _buildCell(averages['avgHours'] ?? '0h 0m 0s', flex: 1.5, isBold: true),
                        _buildCell('${(averages['avgAttendancePercent'] as num?)?.toStringAsFixed(1) ?? '0'}%', flex: 1.2, isBold: true),
                        _buildCell('', flex: 1),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom Content (With Padding)
        Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Stats
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  border: Border.all(color: Colors.amber[200]!),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.summarize, color: Colors.amber[900], size: 20.sp),
                        SizedBox(width: 8.w),
                        Text(
                          'Summary',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[900],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      'Total Students: ${studentRecords.length}',
                      style: TextStyle(fontSize: 14.sp, color: Colors.black87),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Total Days Data: ${totals['totalPresent'] ?? 0} present + ${totals['totalAbsent'] ?? 0} absent',
                      style: TextStyle(fontSize: 14.sp, color: Colors.black87),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24.h),

              // ALLOCATION RULES FOOTER
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  border: Border.all(color: Colors.blue[100]!),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Text(
                            '🎯 HOURS ALLOCATION POLICY',
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                          const SizedBox(width: 12),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            'SYSTEM VERIFIED',
                            style: TextStyle(
                              fontSize: 9.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                        ),
                      ],
                      ),
                    ),
                    SizedBox(height: 12.h),
                    _buildSimplifiedPolicyRow('Within Window', '✅ Full credit for actual hours present'),
                    _buildSimplifiedPolicyRow('After Window', '⚠️ Reduced fixed hours based on subjects'),
                    _buildSimplifiedPolicyRow('No Exit / Late', '❌ 1.0h minimum credit / Marked absent'),
                  ],
                ),
              ),
              SizedBox(height: 40.h),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSimplifiedPolicyRow(String label, String description) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildCell(
    String text, {
    required double flex,
    bool isHeader = false,
    bool isBold = false,
    TextAlign textAlign = TextAlign.left,
    Color? color,
  }) {
    // ✅ Use fixed width instead of Expanded to avoid layout issues in scrollable context
    // Width per flex unit: 80 pixels (flex 1 = 80px, flex 2 = 160px, etc.)
    final cellWidth = flex * 80.0;

    return SizedBox(
      width: cellWidth,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
        child: Text(
          text,
          textAlign: textAlign,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isHeader ? 11.sp : 11.sp,
            fontWeight: isHeader || isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? (isHeader ? Colors.black87 : Colors.black),
          ),
        ),
      ),
    );
  }
}
