import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_db.dart';

/// Batching + Queue System for Attendance Processing
/// Prevents 3000 institutes from crashing backend
class AttendanceBatchService {
  static const int BATCH_SIZE = 100; // Process 100 at a time
  static const Duration BATCH_DELAY = Duration(milliseconds: 500); // Wait between batches
  static const int MAX_RETRIES = 3;
  static const Duration RETRY_DELAY = Duration(seconds: 2);

  static final AttendanceBatchService _instance = AttendanceBatchService._internal();

  factory AttendanceBatchService() {
    return _instance;
  }

  AttendanceBatchService._internal();

  // Queue management
  final List<AttendanceTask> _queue = [];
  bool _isProcessing = false;
  int _processedCount = 0;
  int _failedCount = 0;

  /// Task to be queued
  class AttendanceTask {
    final String srNo;
    final String instituteId;
    final String recordType; // 'entry' or 'exit'
    final String markedTime;
    final String? remark;
    final String? photoUrl;
    final int retryCount;

    AttendanceTask({
      required this.srNo,
      required this.instituteId,
      required this.recordType,
      required this.markedTime,
      this.remark,
      this.photoUrl,
      this.retryCount = 0,
    });
  }

  /// Add attendance to queue (NON-BLOCKING)
  void queueAttendance({
    required String srNo,
    required String instituteId,
    required String recordType,
    required String markedTime,
    String? remark,
    String? photoUrl,
  }) {
    _queue.add(AttendanceTask(
      srNo: srNo,
      instituteId: instituteId,
      recordType: recordType,
      markedTime: markedTime,
      remark: remark,
      photoUrl: photoUrl,
    ));

    print('📋 [QUEUE] Task added. Queue size: ${_queue.length}');

    // Start processing if not already running
    if (!_isProcessing) {
      _processQueue();
    }
  }

  /// Process entire queue in batches
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;
    _processedCount = 0;
    _failedCount = 0;

    print('🚀 [BATCH] Starting batch processing... Queue size: ${_queue.length}');

    while (_queue.isNotEmpty) {
      // Get next batch
      final batchSize = _queue.length > BATCH_SIZE ? BATCH_SIZE : _queue.length;
      final batch = _queue.sublist(0, batchSize);

      print('📦 [BATCH] Processing batch of $batchSize tasks...');

      // Process this batch in parallel (but controlled)
      final results = await Future.wait(
        batch.map((task) => _processTask(task)),
        eagerError: false, // Continue even if some fail
      );

      // Remove completed tasks
      for (int i = 0; i < batchSize; i++) {
        _queue.removeAt(0);
      }

      // Count successes/failures
      int successCount = results.where((r) => r == true).length;
      _processedCount += successCount;
      _failedCount += (batchSize - successCount);

      print('✅ [BATCH] Batch complete. Success: $successCount, Failed: ${batchSize - successCount}');
      print('   Total Progress: $_processedCount processed, $_failedCount failed');

      // Wait before next batch to avoid overwhelming backend
      if (_queue.isNotEmpty) {
        print('⏳ [BATCH] Waiting ${BATCH_DELAY.inMilliseconds}ms before next batch...');
        await Future.delayed(BATCH_DELAY);
      }
    }

    print('🎉 [BATCH] Queue processing complete!');
    print('   Total: $_processedCount success, $_failedCount failed');
    _isProcessing = false;
  }

  /// Process single task with retry logic
  Future<bool> _processTask(AttendanceTask task) async {
    try {
      print('   📝 Processing: ${task.srNo} (${task.recordType})');

      // Call Supabase to save attendance
      await appDb.from('attendance').insert({
        'sr_no': task.srNo,
        'institute_id': task.instituteId,
        'record_type': task.recordType,
        'attendance_date': task.markedTime.split('T')[0],
        'marked_time': task.markedTime,
        'remark': task.remark ?? '-',
        'photo_url': task.photoUrl,
        'status': 'PRESENT',
        'is_verified': false,
      });

      print('   ✅ Success: ${task.srNo}');
      return true;
    } catch (e) {
      print('   ❌ Error: ${task.srNo} - $e');

      // Retry logic
      if (task.retryCount < MAX_RETRIES) {
        print('   🔄 Retrying... (Attempt ${task.retryCount + 1}/$MAX_RETRIES)');
        await Future.delayed(RETRY_DELAY);

        return _processTask(AttendanceTask(
          srNo: task.srNo,
          instituteId: task.instituteId,
          recordType: task.recordType,
          markedTime: task.markedTime,
          remark: task.remark,
          photoUrl: task.photoUrl,
          retryCount: task.retryCount + 1,
        ));
      }

      return false;
    }
  }

  /// Get current queue status
  Map<String, dynamic> getStatus() {
    return {
      'queueSize': _queue.length,
      'isProcessing': _isProcessing,
      'processedCount': _processedCount,
      'failedCount': _failedCount,
      'totalProcessed': _processedCount + _failedCount,
    };
  }

  /// Clear queue
  void clearQueue() {
    _queue.clear();
    print('🗑️ [QUEUE] Queue cleared');
  }

  /// Force process queue immediately
  Future<void> forceProcess() async {
    print('⚡ [BATCH] Force processing queue...');
    await _processQueue();
  }
}

/// Singleton instance
final attendanceBatchService = AttendanceBatchService();
