import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_theme.dart';

/// Student Daily Attendance Report Table
class StudentReportTable extends StatelessWidget {
  final String studentName;
  final String srNo;
  final List<Map<String, dynamic>> dailyRecords;
  final String totalHours;
  final int totalDaysAttended;

  const StudentReportTable({
    super.key,
    required this.studentName,
    required this.srNo,
    required this.dailyRecords,
    required this.totalHours,
    required this.totalDaysAttended,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STUDENT ATTENDANCE REPORT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  '$studentName (SR $srNo)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),

          // Table Header
          Container(
            padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border(
                bottom: BorderSide(color: Colors.grey[400]!),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildHeaderCell('Date'),
                ),
                Expanded(
                  flex: 3,
                  child: _buildHeaderCell('In/Out Time'),
                ),
                Expanded(
                  flex: 2,
                  child: _buildHeaderCell('Scenario'),
                ),
                Expanded(
                  flex: 2,
                  child: _buildHeaderCell('Total Hours'),
                ),
              ],
            ),
          ),

          // Table Rows
          ...dailyRecords.asMap().entries.map((entry) {
            final index = entry.key;
            final record = entry.value;
            final isLast = index == dailyRecords.length - 1;

            return Container(
              padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isLast ? Colors.grey[400]! : Colors.grey[300]!,
                  ),
                ),
                color: index % 2 == 0 ? Colors.white : Colors.grey[50],
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      record['date'] ?? '',
                      style: TextStyle(fontSize: 12.sp),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      record['timeRange'] ?? '—',
                      style: TextStyle(fontSize: 11.sp),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      record['scenario'] ?? '—',
                      style: TextStyle(fontSize: 11.sp),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      record['hours'] ?? '—',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),

          SizedBox(height: 16.h),

          // Total Section
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              border: Border.all(color: AppTheme.primaryBlue),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Days Attended',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey[700],
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '$totalDaysAttended days',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total Hours',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey[700],
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      totalHours,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey[700],
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '✅',
                      style: TextStyle(fontSize: 18.sp),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: 16.h),

          // ALLOCATION RULES FOOTER
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border.all(color: Colors.blue[300]!),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎯 ALLOCATION POLICY - HOURS CALCULATION',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[900],
                  ),
                ),
                SizedBox(height: 12.h),
                _buildFooterRow('Scenario', 'Hours Credited', 'Description'),
                SizedBox(height: 8.h),
                _buildFooterRow('✅ Within Window', 'Full actual hours', 'Student marks entry & exit on time'),
                _buildFooterRow('⚠️ After Window', 'Fixed reduced amount', 'Student marks exit after deadline'),
                _buildFooterRow('❌ No Exit', '1.0h fixed', 'Student marks entry but no exit'),
                _buildFooterRow('❌ Absent', '0h', 'No entry marked'),
                SizedBox(height: 8.h),
                Text(
                  'Format: All hours shown as "Xh Ym Zs" (hours, minutes, seconds)',
                  style: TextStyle(fontSize: 10.sp, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterRow(String scenario, String hours, String description) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              scenario,
              style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              hours,
              style: TextStyle(fontSize: 10.sp),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              description,
              style: TextStyle(fontSize: 10.sp),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.sp,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }
}
