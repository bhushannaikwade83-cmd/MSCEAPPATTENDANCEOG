import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/app_db.dart';
import '../../core/time_parse.dart';

class StudentLeavesScreen extends StatefulWidget {
  const StudentLeavesScreen({super.key});

  @override
  State<StudentLeavesScreen> createState() => _StudentLeavesScreenState();
}

class _StudentLeavesScreenState extends State<StudentLeavesScreen> {
  Timer? _timer;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final user = appDb.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final prof = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      final instituteId = prof?['institute_id'] as String?;
      if (instituteId == null || instituteId.isEmpty) {
        if (mounted) setState(() {
          _rows = [];
          _loading = false;
        });
        return;
      }

      var stud = await appDb.from('students').select('id').eq('institute_id', instituteId).eq('user_id', user.id).maybeSingle();
      stud ??= await appDb.from('students').select('id').eq('institute_id', instituteId).eq('sr_no', user.id).maybeSingle();

      final sid = stud?['id'] as String?;
      if (sid == null) {
        if (mounted) setState(() {
          _rows = [];
          _loading = false;
        });
        return;
      }

      final list = await appDb
          .from('student_leaves')
          .select()
          .eq('institute_id', instituteId)
          .eq('student_id', sid)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _rows = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Leave Requests"),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text("No leave requests found."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rows.length,
                  itemBuilder: (context, index) {
                    final row = _rows[index];
                    final payload = (row['payload'] as Map?)?.cast<String, dynamic>() ?? {};
                    final status = payload['status'] as String? ?? 'pending';
                    final reason = payload['reason'] as String? ?? 'No reason';
                    final applied = parseAnyTimestamp(payload['appliedAt'] ?? row['created_at']);

                    Color color = Colors.orange;
                    if (status == 'approved') color = Colors.green;
                    if (status == 'rejected') color = Colors.red;

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.1),
                          child: Icon(Icons.description, color: color),
                        ),
                        title: Text(
                          status.toUpperCase(),
                          style: TextStyle(color: color, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text("Reason: $reason${applied != null ? '\nApplied: $applied' : ''}"),
                      ),
                    );
                  },
                ),
    );
  }
}
