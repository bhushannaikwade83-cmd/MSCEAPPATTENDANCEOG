import 'package:flutter/material.dart';
import '../core/root_navigator.dart';
import '../presentation/widgets/institute_status_dialog.dart';
import '../presentation/screens/admin_home_screen.dart';
import '../presentation/screens/student_management_screen.dart';
import 'institute_status_service.dart';

/// Global notification handler for processing notification taps (uses [rootNavigatorKey]).
class NotificationHandler {
  /// Handle notification tap based on payload (expects `action|...` segments).
  static Future<void> handleNotificationTap(String? payload) async {
    if (payload == null) return;

    final parts = payload.split('|');
    if (parts.length < 2) return;

    final action = parts[0];

    if (action == 'pending_exit' && parts.length >= 5) {
      final rollKey = parts[2];
      final subjectTag = parts[4];
      final subjectHint = subjectTag == 'all' ? '' : ' — $subjectTag';
      rootNavigatorKey.currentState?.pushNamed(StudentManagementScreen.routeName);
      await Future.delayed(const Duration(milliseconds: 450));
      final ctxSnack = rootNavigatorKey.currentContext;
      if (ctxSnack != null && ctxSnack.mounted) {
        ScaffoldMessenger.of(ctxSnack).showSnackBar(
          SnackBar(
            content: Text('Finish exit attendance for roll $rollKey$subjectHint'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    final instituteId = parts[1];

    final nav = rootNavigatorKey.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil(
        AdminHomeScreen.routeName,
        (route) => false,
      );

      await Future.delayed(const Duration(milliseconds: 500));

      final statusService = InstituteStatusService();
      final status = await statusService.getTodayStatus(instituteId);
      final currentStatus = status?['status'] as String?;

      final ctxDialog = rootNavigatorKey.currentContext;
      if (ctxDialog != null && ctxDialog.mounted) {
        showDialog(
          context: ctxDialog,
          builder: (context) => InstituteStatusDialog(
            instituteId: instituteId,
            currentStatus: currentStatus,
          ),
        );
      }
    }
  }
}
