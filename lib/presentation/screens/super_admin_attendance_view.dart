import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../../core/app_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time_parse.dart';
import '../../services/hierarchical_attendance_service.dart';

/// Super Admin Attendance View
///
/// Displays attendance data organized by:
/// Year → Institute Code → Students → Date → In/Out
class SuperAdminAttendanceView extends StatefulWidget {
  static const routeName = '/super-admin-attendance-view';
  const SuperAdminAttendanceView({super.key});

  @override
  State<SuperAdminAttendanceView> createState() => _SuperAdminAttendanceViewState();
}

class _SuperAdminAttendanceViewState extends State<SuperAdminAttendanceView> {
  final HierarchicalAttendanceService _attendanceService = HierarchicalAttendanceService();
  
  bool _isLoading = true;
  Map<String, dynamic> _attendanceData = {};

  @override
  void initState() {
    super.initState();
    _loadAttendanceData();
  }

  Future<void> _loadAttendanceData() async {
    setState(() => _isLoading = true);
    try {
      final summary = await _attendanceService.getAttendanceSummary();
      setState(() {
        _attendanceData = summary;
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading attendance data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Attendance Database View'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAttendanceData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _attendanceData.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: AppTheme.textGray),
                      const SizedBox(height: 16),
                      Text(
                        'No attendance data found',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppTheme.textGray,
                        ),
                      ),
                    ],
                  ),
                )
              : _buildHierarchicalView(),
    );
  }

  Widget _buildHierarchicalView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._attendanceData.entries.map((yearEntry) {
          final year = yearEntry.key;
          final instituteData = yearEntry.value as Map<String, dynamic>;

          return ExpansionTile(
            leading: const Icon(Icons.calendar_today, color: AppTheme.primaryBlue),
            title: Text(
              'Year $year',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text('${instituteData.length} institute(s)'),
            children: [
              ...instituteData.entries.map((instituteEntry) {
                final instituteCode = instituteEntry.key;
                final stats = instituteEntry.value as Map<String, dynamic>;
                final totalStudents = stats['totalStudents'] as int? ?? 0;
                final totalAttendance = stats['totalAttendance'] as int? ?? 0;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.business, color: AppTheme.primaryBlue),
                    ),
                    title: Text(
                      'Institute: $instituteCode',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('Students: $totalStudents'),
                        Text('Attendance Records: $totalAttendance'),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, size: 16),
                      onPressed: () {
                        _showInstituteDetails(year, instituteCode);
                      },
                    ),
                  ),
                );
              }).toList(),
            ],
          );
        }).toList(),
      ],
    );
  }

  Future<void> _showInstituteDetails(String year, String instituteCode) async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Institute Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Text('Year: $year'),
              Text('Inst ID: $instituteCode'),
              const SizedBox(height: 16),
              const Text(
                'Students & Attendance:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadStudentsForInstitute(instituteCode),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final students = snapshot.data!;
                    if (students.isEmpty) {
                      return const Center(
                        child: Text('No students found'),
                      );
                    }

                    return ListView.builder(
                      itemCount: students.length,
                      itemBuilder: (context, index) {
                        final student = students[index];
                        final sid = student['id'] as String? ?? '';
                        return FutureBuilder<int>(
                          future: _countAttendanceForStudent(
                            instituteCode: instituteCode,
                            studentId: sid,
                            year: year,
                          ),
                          builder: (context, attendanceSnapshot) {
                            final attendanceCount = attendanceSnapshot.data ?? 0;

                            return ListTile(
                              title: Text('Student: $sid'),
                              subtitle: Text('Attendance Records: $attendanceCount'),
                              trailing: IconButton(
                                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                                onPressed: () {
                                  _showStudentDetails(
                                    year,
                                    instituteCode,
                                    sid,
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadStudentsForInstitute(String instituteCode) async {
    final inst = await appDb.from('institutes').select('id').eq('institute_code', instituteCode).maybeSingle();
    final iid = inst?['id'] as String?;
    if (iid == null) return [];
    final rows = await appDb.from('students').select('id, name, sr_no').eq('institute_id', iid);
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<int> _countAttendanceForStudent({
    required String instituteCode,
    required String studentId,
    required String year,
  }) async {
    final yearInt = int.tryParse(year) ?? 0;
    final rows = await appDb
        .from('attendance_in_out')
        .select('id')
        .eq('institute_code', instituteCode)
        .eq('student_id', studentId)
        .eq('year', yearInt);
    return rows.length;
  }

  Future<List<Map<String, dynamic>>> _loadStudentAttendanceRows({
    required String year,
    required String instituteCode,
    required String studentId,
  }) async {
    final yearInt = int.tryParse(year) ?? 0;
    final rows = await appDb
        .from('attendance_in_out')
        .select()
        .eq('institute_code', instituteCode)
        .eq('student_id', studentId)
        .eq('year', yearInt)
        .order('attendance_date', ascending: false);
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _showStudentDetails(
    String year,
    String instituteCode,
    String studentId,
  ) async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Student Attendance',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Text('Student ID: $studentId'),
              const SizedBox(height: 16),
              const Text(
                'Attendance Records:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadStudentAttendanceRows(
                    year: year,
                    instituteCode: instituteCode,
                    studentId: studentId,
                  ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final rows = snapshot.data!;
                    if (rows.isEmpty) {
                      return const Center(child: Text('No attendance records'));
                    }

                    final byDate = <String, List<Map<String, dynamic>>>{};
                    for (final r in rows) {
                      final d = r['attendance_date']?.toString() ?? '';
                      byDate.putIfAbsent(d, () => []).add(r);
                    }
                    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

                    return ListView.builder(
                      itemCount: dates.length,
                      itemBuilder: (context, index) {
                        final date = dates[index];
                        final dayRows = byDate[date] ?? [];
                        Map<String, dynamic>? entryRow;
                        Map<String, dynamic>? exitRow;
                        for (final r in dayRows) {
                          final t = r['type'] as String? ?? '';
                          if (t == 'entry') entryRow = r;
                          if (t == 'exit') exitRow = r;
                        }
                        final entryTs = entryRow != null ? parseAnyTimestamp(entryRow['created_at']) : null;
                        final exitTs = exitRow != null ? parseAnyTimestamp(exitRow['created_at']) : null;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text('Date: $date'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (entryTs != null) Text('Entry: $entryTs'),
                                if (exitTs != null) Text('Exit: $exitTs'),
                              ],
                            ),
                            trailing: const Icon(Icons.check_circle, color: Colors.green),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
