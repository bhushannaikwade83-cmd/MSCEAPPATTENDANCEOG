import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_theme.dart';
import '../../services/institute_status_service.dart';

/// Dialog to mark institute as open/close/holiday
class InstituteStatusDialog extends StatefulWidget {
  final String instituteId;
  final String? currentStatus; // 'open', 'closed', 'holiday', or null

  const InstituteStatusDialog({
    super.key,
    required this.instituteId,
    this.currentStatus,
  });

  @override
  State<InstituteStatusDialog> createState() => _InstituteStatusDialogState();
}

class _InstituteStatusDialogState extends State<InstituteStatusDialog> {
  final InstituteStatusService _statusService = InstituteStatusService();
  bool _isLoading = false;
  String? _selectedAction;
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _handleAction(String action) async {
    setState(() {
      _isLoading = true;
      _selectedAction = action;
    });

    try {
      Map<String, dynamic> result;
      
      if (action == 'open') {
        result = await _statusService.markOpen(widget.instituteId);
      } else if (action == 'close') {
        result = await _statusService.markClosed(widget.instituteId);
      } else if (action == 'holiday') {
        result = await _statusService.markHoliday(
          widget.instituteId,
          reason: _reasonController.text.trim().isEmpty 
              ? null 
              : _reasonController.text.trim(),
        );
      } else {
        result = {'success': false, 'message': 'Invalid action'};
      }

      if (mounted) {
        if (result['success'] == true) {
          Navigator.pop(context, action);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Status updated successfully'),
              backgroundColor: AppTheme.primaryGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to update status'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.business, color: AppTheme.primaryBlue, size: 28.sp),
                SizedBox(width: 12.w),
                Text(
                  'Institute Status',
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                ),
              ],
            ),
            SizedBox(height: 24.h),
            
            // Current status indicator
            if (widget.currentStatus != null)
              Container(
                padding: EdgeInsets.all(12.w),
                margin: EdgeInsets.only(bottom: 16.h),
                decoration: BoxDecoration(
                  color: widget.currentStatus == 'open'
                      ? AppTheme.accentGreen.withOpacity(0.1)
                      : widget.currentStatus == 'holiday'
                          ? AppTheme.accentOrange.withOpacity(0.1)
                          : AppTheme.accentRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(
                    color: widget.currentStatus == 'open'
                        ? AppTheme.accentGreen
                        : widget.currentStatus == 'holiday'
                            ? AppTheme.accentOrange
                            : AppTheme.accentRed,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.currentStatus == 'open'
                          ? Icons.check_circle
                          : widget.currentStatus == 'holiday'
                              ? Icons.event
                              : Icons.close,
                      color: widget.currentStatus == 'open'
                          ? AppTheme.accentGreen
                          : widget.currentStatus == 'holiday'
                              ? AppTheme.accentOrange
                              : AppTheme.accentRed,
                      size: 20.sp,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Current: ${widget.currentStatus?.toUpperCase() ?? 'Not Set'}',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: widget.currentStatus == 'open'
                            ? AppTheme.accentGreen
                            : widget.currentStatus == 'holiday'
                                ? AppTheme.accentOrange
                                : AppTheme.accentRed,
                      ),
                    ),
                  ],
                ),
              ),

            // Action buttons
            if (widget.currentStatus != 'open')
              _buildActionButton(
                context: context,
                icon: Icons.check_circle,
                label: 'Mark as Open',
                color: AppTheme.accentGreen,
                action: 'open',
                isLoading: _isLoading && _selectedAction == 'open',
              ),

            if (widget.currentStatus != 'closed')
              _buildActionButton(
                context: context,
                icon: Icons.close,
                label: 'Mark as Closed',
                color: AppTheme.accentRed,
                action: 'close',
                isLoading: _isLoading && _selectedAction == 'close',
              ),

            if (widget.currentStatus != 'holiday') ...[
              _buildActionButton(
                context: context,
                icon: Icons.event,
                label: 'Mark as Holiday',
                color: AppTheme.accentOrange,
                action: 'holiday',
                isLoading: _isLoading && _selectedAction == 'holiday',
              ),
              
              // Holiday reason input (only show when holiday is selected)
              if (_selectedAction == 'holiday')
                Padding(
                  padding: EdgeInsets.only(top: 12.h),
                  child: TextField(
                    controller: _reasonController,
                    decoration: InputDecoration(
                      labelText: 'Holiday Reason (Optional)',
                      hintText: 'e.g., National Holiday, Festival',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      prefixIcon: Icon(Icons.edit, size: 20.sp),
                    ),
                    maxLines: 2,
                  ),
                ),
            ],

            SizedBox(height: 16.h),
            
            // Cancel button
            TextButton(
              onPressed: _isLoading ? null : () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(fontSize: 14.sp),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required String action,
    required bool isLoading,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : () => _handleAction(action),
        icon: isLoading
            ? SizedBox(
                width: 20.w,
                height: 20.h,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(icon, size: 20.sp),
        label: Text(label, style: TextStyle(fontSize: 14.sp)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 14.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
      ),
    );
  }
}
