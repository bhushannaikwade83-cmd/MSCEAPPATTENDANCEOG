import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../core/app_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../pdf/attendance_report.dart';
import '../../pdf/models/attendance_data.dart';

class AttendanceReportsScreen extends StatefulWidget {
  static const routeName = '/attendance-reports';
  final String? instituteId;

  const AttendanceReportsScreen({
    super.key,
    this.instituteId,
  });

  @override
  State<AttendanceReportsScreen> createState() => _AttendanceReportsScreenState();
}

class _AttendanceReportsScreenState extends State<AttendanceReportsScreen> {
  String? _instituteId;
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _selectedStudent;
  bool _loadingStudents = true;

  // Date filters
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String _selectedFilter = '1month'; // 1month, 3month, 6month, custom

  @override
  void initState() {
    super.initState();
    _instituteId = widget.instituteId;
    print('📚 Reports Screen Init - instituteId: $_instituteId');
    _loadStudents();
  }

  /// Load all students from institute
  Future<void> _loadStudents() async {
    if (_instituteId == null || _instituteId!.isEmpty) {
      print('❌ No instituteId provided');
      return;
    }

    try {
      print('🔄 Loading students for institute: $_instituteId');
      final response = await appDb
          .from('students')
          .select('id,sr_no,fname,lname,sub1,sub2,sub3,sub4,sub5,sub6,sub7,sub8,face_photo_url')
          .eq('institute_id', _instituteId!)
          .order('sr_no');

      print('✅ Loaded ${response.length} students');
      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(response);
          _loadingStudents = false;
        });
      }
    } catch (e) {
      print('❌ Error loading students: $e');
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  /// Get student's subjects
  List<String> _getStudentSubjects(Map<String, dynamic> student) {
    final subjects = <String>[];
    for (int i = 1; i <= 8; i++) {
      final sub = student['sub$i'] as String?;
      if (sub != null && sub.isNotEmpty) subjects.add(sub);
    }
    return subjects;
  }

  /// Parse HH:MM:SS string to total seconds
  int _timeStringToSeconds(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 0;
    try {
      final parts = timeStr.split(':');
      if (parts.length != 3) return 0;
      final hours = int.tryParse(parts[0]) ?? 0;
      final minutes = int.tryParse(parts[1]) ?? 0;
      final seconds = int.tryParse(parts[2]) ?? 0;
      return (hours * 3600) + (minutes * 60) + seconds;
    } catch (e) {
      return 0;
    }
  }

  /// Convert total seconds to HH:MM:SS string
  String _secondsToTimeString(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Set date range based on filter
  void _setDateFilter(String filter) {
    final now = DateTime.now();
    setState(() {
      _selectedFilter = filter;
      if (filter == '1month') {
        _filterStartDate = now.subtract(const Duration(days: 30));
        _filterEndDate = now;
      } else if (filter == '3month') {
        _filterStartDate = now.subtract(const Duration(days: 90));
        _filterEndDate = now;
      } else if (filter == '6month') {
        _filterStartDate = now.subtract(const Duration(days: 180));
        _filterEndDate = now;
      }
    });
  }

  /// Show custom date range picker
  Future<void> _showCustomDatePicker() async {
    final startDate = await showDatePicker(
      context: context,
      initialDate: _filterStartDate ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );

    if (startDate != null) {
      final endDate = await showDatePicker(
        context: context,
        initialDate: _filterEndDate ?? DateTime.now(),
        firstDate: startDate,
        lastDate: DateTime.now(),
      );

      if (endDate != null) {
        setState(() {
          _selectedFilter = 'custom';
          _filterStartDate = startDate;
          _filterEndDate = endDate;
        });
      }
    }
  }

  /// Build filter button
  Widget _buildFilterButton(String label, String filter, bool isDark) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () {
        if (filter == 'custom') {
          _showCustomDatePicker();
        } else {
          _setDateFilter(filter);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF0F2F7)),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : AppTheme.textGray),
          ),
        ),
      ),
    );
  }

  /// Generate PDF Report using clean template system
  Future<void> _generatePDFReport() async {
    if (_selectedStudent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a student first')),
      );
      return;
    }

    try {
      final student = _selectedStudent!;
      final studentName = '${student['fname']} ${student['lname']}';
      final srNo = student['sr_no'] as String;
      final subjects = _getStudentSubjects(student);

      // Fetch registration date (use old_face_registered_at if face was reset)
      String? faceRegisteredAtFormatted;
      DateTime? effectiveStartDate = _filterStartDate;
      try {
        final studentData = await appDb
            .from('students')
            .select('face_registered_at, old_face_registered_at')
            .eq('sr_no', srNo)
            .maybeSingle();

        if (studentData != null) {
          final oldRegisteredAt = studentData['old_face_registered_at'] as String?;
          final currentRegisteredAt = studentData['face_registered_at'] as String?;

          DateTime? regDate;
          if (oldRegisteredAt != null && oldRegisteredAt.isNotEmpty) {
            // Face was reset - use old date for attendance counting
            regDate = DateTime.parse(oldRegisteredAt);
            final oldDate = DateFormat('dd MMM yyyy').format(regDate);
            if (currentRegisteredAt != null && currentRegisteredAt.isNotEmpty) {
              final newDate = DateFormat('dd MMM yyyy').format(DateTime.parse(currentRegisteredAt));
              faceRegisteredAtFormatted = '$oldDate (Reset: $newDate)';
            } else {
              faceRegisteredAtFormatted = oldDate;
            }
          } else if (currentRegisteredAt != null && currentRegisteredAt.isNotEmpty) {
            // First registration
            regDate = DateTime.parse(currentRegisteredAt);
            faceRegisteredAtFormatted = DateFormat('dd MMM yyyy').format(regDate);
          }

          if (regDate != null) {
            // Adjust effective start date to registration date if needed
            if (effectiveStartDate == null || regDate.isAfter(effectiveStartDate)) {
              effectiveStartDate = regDate;
            }
            print('📅 Student registered: $faceRegisteredAtFormatted');
          }
        }
      } catch (e) {
        print('⚠️ Could not fetch registration date: $e');
      }

      // Fetch attendance data
      final records = await appDb
          .from('attendance')
          .select()
          .eq('sr_no', srNo)
          .order('attendance_date, marked_time');

      print('📄 Generating PDF with ${records.length} records');

      // Filter by effective date range
      List<Map<String, dynamic>> filteredRecords = records.cast<Map<String, dynamic>>();
      if (effectiveStartDate != null && _filterEndDate != null) {
        filteredRecords = filteredRecords.where((r) {
          try {
            final date = DateTime.parse(r['attendance_date'] as String);
            return !date.isBefore(effectiveStartDate!) && !date.isAfter(_filterEndDate!);
          } catch (e) {
            return false;
          }
        }).toList();
      }

      // Group by date
      Map<String, List<Map<String, dynamic>>> byDate = {};
      for (final rec in filteredRecords) {
        final date = rec['attendance_date'] as String?;
        if (date == null) continue;
        byDate.putIfAbsent(date, () => []);
        byDate[date]!.add(rec);
      }

      // Build attendance records for PDF
      List<AttendanceRecord> pdfRecords = [];
      int presentDays = 0, absentDays = 0;

      byDate.forEach((dateStr, dayRecs) {
        final entryRec = dayRecs.firstWhere((r) => (r['record_type'] as String?) == 'entry', orElse: () => <String, dynamic>{});
        final exitRec = dayRecs.firstWhere((r) => (r['record_type'] as String?) == 'exit', orElse: () => <String, dynamic>{});

        String entryTime = '-', exitTime = '-', status = 'Absent', hours = '0.0', reason = 'Absent';

        if (entryRec.isNotEmpty) {
          status = 'Present';
          presentDays++;
          try {
            final dt = DateTime.parse((entryRec['marked_time'] as String) + 'Z').toLocal();
            entryTime = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          } catch (e) {}

          if (exitRec.isNotEmpty) {
            try {
              final dt = DateTime.parse((exitRec['marked_time'] as String) + 'Z').toLocal();
              exitTime = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            } catch (e) {}
            reason = '-';
            hours = exitRec['attendance_alloted_hr'] as String? ?? '0.0';
          } else {
            reason = entryRec['remark'] as String? ?? '-';
            hours = entryRec['attendance_alloted_hr'] as String? ?? '0.0';
          }
        } else {
          absentDays++;
        }

        // Format date as DD-MM-YYYY
        final dateObj = DateTime.parse(dateStr);
        final formattedDate = DateFormat('dd-MM-yyyy').format(dateObj);

        pdfRecords.add(AttendanceRecord(
          date: formattedDate,
          entryTime: entryTime,
          exitTime: exitTime,
          status: status,
          hours: hours,
          reason: reason,
        ));
      });

      // Load MSCE logo
      Uint8List? logoBytes;
      try {
        logoBytes = (await rootBundle.load('assets/pdf_images/msce_logo.png'))
            .buffer
            .asUint8List();
        print('✅ [PDF] Logo loaded successfully');
      } catch (e) {
        print('⚠️ [PDF] Logo not found: $e');
        logoBytes = null;
      }

      // Load institute name
      String instituteName = '';
      try {
        final instResp = await appDb
            .from('institutes')
            .select('name')
            .eq('id', _instituteId!)
            .single();
        instituteName = instResp['name'] as String? ?? '';
        print('✅ [PDF] Institute name loaded: $instituteName');
      } catch (e) {
        print('⚠️ [PDF] Institute name not found: $e');
      }

      // Load student's registered photo
      Uint8List? photoBytes;
      try {
        final photoUrl = student['face_photo_url'] as String?;
        print('📸 [PDF] face_photo_url value: "$photoUrl"');

        // Try 1: Load face_photo_url (registered photo)
        if (photoUrl != null && photoUrl.isNotEmpty) {
          print('📸 [PDF] Trying face_photo_url...');
          try {
            final photoResponse = await http.get(Uri.parse(photoUrl)).timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw Exception('Timeout'),
            );
            if (photoResponse.statusCode == 200) {
              photoBytes = photoResponse.bodyBytes;
              print('✅ [PDF] Loaded from face_photo_url (${photoBytes.length} bytes)');
            }
          } catch (e) {
            print('⚠️ [PDF] face_photo_url failed: $e');
          }
        }

        // Try 2: If no face photo, load latest attendance photo
        if (photoBytes == null) {
          print('📸 [PDF] Trying attendance photos...');
          try {
            final attendancePhotos = await appDb
                .from('attendance_in_out')
                .select('photo_url')
                .eq('student_id', student['id'])
                .neq('photo_url', '')
                .order('created_at', ascending: false)
                .limit(1);

            if (attendancePhotos.isNotEmpty && attendancePhotos[0]['photo_url'] != null) {
              final attendancePhotoUrl = attendancePhotos[0]['photo_url'] as String?;
              if (attendancePhotoUrl != null && attendancePhotoUrl.isNotEmpty) {
                print('📸 [PDF] Found attendance photo: $attendancePhotoUrl');
                final photoResponse = await http.get(Uri.parse(attendancePhotoUrl)).timeout(
                  const Duration(seconds: 10),
                  onTimeout: () => throw Exception('Timeout'),
                );
                if (photoResponse.statusCode == 200) {
                  photoBytes = photoResponse.bodyBytes;
                  print('✅ [PDF] Loaded from attendance (${photoBytes.length} bytes)');
                }
              }
            }
          } catch (e) {
            print('⚠️ [PDF] Attendance photo failed: $e');
          }
        }

        // Try 3: If still no photo, use placeholder
        if (photoBytes == null) {
          print('📸 [PDF] No photo found, using placeholder');
          try {
            photoBytes = (await rootBundle.load('assets/msce_attendance_app_logo.png'))
                .buffer
                .asUint8List();
            print('📸 [PDF] Using MSCE logo placeholder (${photoBytes.length} bytes)');
          } catch (e) {
            print('⚠️ [PDF] Placeholder failed: $e');
          }
        }
      } catch (e) {
        print('⚠️ [PDF] Photo load error: $e');
      }

      // Build student info
      final studentInfo = StudentInfo(
        instituteId: _instituteId ?? '',
        instituteName: instituteName,
        studentName: studentName,
        srNo: srNo,
        subjects: subjects,
        photoBytes: photoBytes,
        faceRegisteredAt: faceRegisteredAtFormatted,
      );

      // Build summary
      final summary = AttendanceSummary(
        totalPresent: presentDays,
        totalAbsent: absentDays,
        totalLate: 0,
      );

      // Create report data
      final reportData = AttendanceReportData(
        student: studentInfo,
        records: pdfRecords,
        summary: summary,
        logoBytes: logoBytes,
        generatedOn: DateTime.now(),
      );

      // Generate PDF
      print('📊 Building PDF document...');
      final pdfBytes = await generatePdfReport(data: reportData);

      // Display
      print('✅ PDF generated successfully (${pdfBytes.length} bytes)');
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } catch (e) {
      print('❌ PDF Error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Fetch today's attendance for selected student
  /// TODAY'S ATTENDANCE
  /// Logic:
  /// 1. Entry + Exit both → Check EXIT record's attendance_alloted_hr NOT NULL → PRESENT
  /// 2. Entry only (no exit) → Check ENTRY record's attendance_alloted_hr NOT NULL → PRESENT
  /// 3. No Entry → ABSENT
  Future<Map<String, dynamic>> _fetchTodayAttendance() async {
    if (_selectedStudent == null) {
      print('❌ No student selected');
      return {};
    }

    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final srNo = _selectedStudent!['sr_no'] as String;

      final records = await appDb
          .from('attendance')
          .select()
          .eq('sr_no', srNo)
          .eq('attendance_date', today)
          .order('marked_time');

      print('✅ Got ${records.length} records for today');

      // Check if entry and exit exist
      final entryRec = records.firstWhere(
        (r) => (r['record_type'] as String?) == 'entry',
        orElse: () => <String, dynamic>{},
      );
      final exitRec = records.firstWhere(
        (r) => (r['record_type'] as String?) == 'exit',
        orElse: () => <String, dynamic>{},
      );

      // No entry = ABSENT
      if (entryRec.isEmpty) {
        print('❌ ABSENT - No entry');
        return {
          'status': 'ABSENT',
          'entry_time': null,
          'exit_time': null,
          'credited_hours': '00:00:00',
          'allocated_hours': '00:00:00',
        };
      }

      final markedTimeStr = entryRec['marked_time'] as String?;
      print('🔍 Entry marked_time from DB: $markedTimeStr');
      DateTime? entryTime = markedTimeStr != null ? DateTime.parse(markedTimeStr) : null;
      DateTime? exitTime;

      if (exitRec.isNotEmpty) {
        // Entry + Exit both → check EXIT record's attendance_alloted_hr
        final hrsStr = exitRec['attendance_alloted_hr'] as String?;
        if (hrsStr != null && hrsStr.isNotEmpty) {
          exitTime = DateTime.parse(exitRec['marked_time'] as String);
          print('✅ PRESENT (Entry+Exit) - Hours: $hrsStr');
          return {
            'status': 'PRESENT',
            'entry_time': entryTime?.toIso8601String(),
            'exit_time': exitTime.toIso8601String(),
            'credited_hours': hrsStr,
            'allocated_hours': hrsStr,
          };
        }
      } else {
        // Entry only (no exit) → check ENTRY record's attendance_alloted_hr
        final hrsStr = entryRec['attendance_alloted_hr'] as String?;
        if (hrsStr != null && hrsStr.isNotEmpty) {
          print('✅ PRESENT (Entry only) - Hours: $hrsStr');
          return {
            'status': 'PRESENT',
            'entry_time': entryTime?.toIso8601String(),
            'exit_time': null,
            'credited_hours': hrsStr,
            'allocated_hours': hrsStr,
          };
        }
      }

      // Fallback if no allocated hours found
      return {
        'status': 'PRESENT',
        'entry_time': entryTime?.toIso8601String(),
        'exit_time': exitTime?.toIso8601String(),
        'credited_hours': '00:00:00',
        'allocated_hours': '00:00:00',
      };
    } catch (e) {
      print('❌ Error: $e');
      return {
        'status': 'ERROR',
        'credited_hours': '00:00:00',
        'allocated_hours': '00:00:00',
      };
    }
  }

  /// Fetch attendance history
  /// Logic:
  /// 1. Entry + Exit both → Check EXIT record's attendance_alloted_hr NOT NULL → PRESENT
  /// 2. Entry only (no exit) → Check ENTRY record's attendance_alloted_hr NOT NULL → PRESENT
  /// 3. No Entry on weekday → ABSENT
  /// 4. No Entry on Sunday → SKIP (don't count)
  /// 5. If Sunday has entry → apply same logic as step 1-2 → PRESENT
  Future<Map<String, dynamic>> _fetchAttendanceHistory() async {
    if (_selectedStudent == null) {
      print('❌ No student selected for history');
      return {};
    }

    try {
      final srNo = _selectedStudent!['sr_no'] as String;
      print('🔄 Fetching history for: $srNo');

      // Fetch registration date (use old_face_registered_at if face was reset)
      DateTime? registrationDate;
      String? formattedCurrentRegDate;
      try {
        final studentData = await appDb
            .from('students')
            .select('face_registered_at, old_face_registered_at')
            .eq('sr_no', srNo)
            .maybeSingle();

        if (studentData != null) {
          final oldRegisteredAt = studentData['old_face_registered_at'] as String?;
          final currentRegisteredAt = studentData['face_registered_at'] as String?;

          if (oldRegisteredAt != null && oldRegisteredAt.isNotEmpty) {
            // Face was reset - use old date for attendance counting
            registrationDate = DateTime.parse(oldRegisteredAt);
            if (currentRegisteredAt != null && currentRegisteredAt.isNotEmpty) {
              formattedCurrentRegDate = DateFormat('dd MMM yyyy').format(DateTime.parse(currentRegisteredAt));
            }
            print('📅 Student first registered: $registrationDate (Reset: $formattedCurrentRegDate)');
          } else if (currentRegisteredAt != null && currentRegisteredAt.isNotEmpty) {
            // First registration
            registrationDate = DateTime.parse(currentRegisteredAt);
            print('📅 Student registered: $registrationDate');
          }
        }
      } catch (e) {
        print('⚠️ Could not fetch registration date: $e');
      }

      // Get all records ordered by date and time
      final records = await appDb
          .from('attendance')
          .select()
          .eq('sr_no', srNo)
          .order('attendance_date, marked_time');

      print('✅ Got ${records.length} records');

      // Group by date
      Map<String, List<Map<String, dynamic>>> byDate = {};
      for (final rec in records) {
        final date = rec['attendance_date'] as String?;
        if (date == null) continue;
        byDate.putIfAbsent(date, () => []);
        byDate[date]!.add(rec as Map<String, dynamic>);
      }

      int present = 0, absent = 0;
      int totalSeconds = 0;

      // Process each day
      for (final MapEntry(key: dateStr, value: dayRecs) in byDate.entries) {
        try {
          final dateObj = DateTime.parse(dateStr);

          // Filter by registration date - only count attendance from registration date onwards
          if (registrationDate != null && dateObj.isBefore(registrationDate)) {
            print('⏭️ Skipping (before registration): $dateStr');
            continue;
          }

          // Apply date filter
          if (_filterStartDate != null && _filterEndDate != null) {
            if (dateObj.isBefore(_filterStartDate!) || dateObj.isAfter(_filterEndDate!)) {
              continue; // Skip records outside date range
            }
          }

          final isSunday = dateObj.weekday == DateTime.sunday;

          // Check if entry and exit exist
          final entryRec = dayRecs.firstWhere(
            (r) => (r['record_type'] as String?) == 'entry',
            orElse: () => <String, dynamic>{},
          );
          final exitRec = dayRecs.firstWhere(
            (r) => (r['record_type'] as String?) == 'exit',
            orElse: () => <String, dynamic>{},
          );

          // CASE 1: No entry at all
          if (entryRec.isEmpty) {
            if (isSunday) {
              // Sunday with no entry = SKIP
              print('⏸️ SKIP: $dateStr [Sunday, no entry]');
            } else {
              // Weekday with no entry = ABSENT
              print('❌ ABSENT: $dateStr');
              absent++;
            }
            continue;
          }

          // CASE 2: Entry exists
          double? hrs;

          if (exitRec.isNotEmpty) {
            // Entry + Exit both → check EXIT record's attendance_alloted_hr
            final hrsStr = exitRec['attendance_alloted_hr'] as String?;
            if (hrsStr != null && hrsStr.isNotEmpty) {
              print('✅ PRESENT (Entry+Exit): $dateStr → $hrsStr${isSunday ? ' [Sunday]' : ''}');
              present++;
              totalSeconds += _timeStringToSeconds(hrsStr);
            }
          } else {
            // Entry only (no exit) → check ENTRY record's attendance_alloted_hr
            final hrsStr = entryRec['attendance_alloted_hr'] as String?;
            if (hrsStr != null && hrsStr.isNotEmpty) {
              print('✅ PRESENT (Entry only): $dateStr → $hrsStr${isSunday ? ' [Sunday]' : ''}');
              present++;
              totalSeconds += _timeStringToSeconds(hrsStr);
            }
          }
        } catch (e) {
          print('⚠️ Error processing $dateStr: $e');
        }
      }

      final total = present + absent;
      final totalTimeStr = _secondsToTimeString(totalSeconds);

      print('📊 Summary - Present: $present, Absent: $absent, Total: $total, Total Hours: $totalTimeStr');

      // Format registration date if available
      String formattedRegDate = '-';
      if (registrationDate != null) {
        formattedRegDate = DateFormat('dd MMM yyyy').format(registrationDate);
        if (formattedCurrentRegDate != null) {
          formattedRegDate = '$formattedRegDate (Reset: $formattedCurrentRegDate)';
        }
      }

      return {
        'present': present,
        'absent': absent,
        'total': total,
        'hours': totalTimeStr,
        'registered': formattedRegDate,
      };
    } catch (e) {
      print('❌ Error: $e');
      return {'present': 0, 'absent': 0, 'total': 0, 'hours': 0.0};
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1B2E) : AppTheme.backgroundGrey,
      body: _loadingStudents
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 16.h),

                    // 👥 Student Selector
                    Text(
                      'Select Student',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryBlue.withOpacity(isDark ? 0.12 : 0.06),
                            AppTheme.primaryBlue.withOpacity(isDark ? 0.06 : 0.02),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.15),
                          width: 1.5,
                        ),
                      ),
                      child: DropdownButton<Map<String, dynamic>>(
                        value: _selectedStudent,
                        hint: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.w),
                          child: Text(
                            'Choose a student...',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : AppTheme.textGray,
                              fontSize: 13.sp,
                            ),
                          ),
                        ),
                        isExpanded: true,
                        underline: SizedBox.shrink(),
                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                        items: _students.map((student) {
                          final fname = student['fname'] as String? ?? '';
                          final lname = student['lname'] as String? ?? '';
                          final srNo = student['sr_no'] as String? ?? '';
                          final label = '$srNo - $fname $lname'.trim();

                          return DropdownMenuItem(
                            value: student,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12.w),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: isDark ? Colors.white : AppTheme.textDark,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (student) {
                          setState(() => _selectedStudent = student);
                        },
                      ),
                    ),

                    if (_selectedStudent != null) ...[
                      SizedBox(height: 32.h),

                      // 📅 TODAY'S ATTENDANCE
                      Text(
                        "TODAY'S ATTENDANCE",
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      FutureBuilder<Map<String, dynamic>>(
                        future: _fetchTodayAttendance(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.h),
                                child: CircularProgressIndicator(color: AppTheme.primaryBlue),
                              ),
                            );
                          }

                          final data = snapshot.data ?? {};
                          final status = data['status'] as String? ?? 'ERROR';
                          final entryTime = data['entry_time'] as String?;
                          final exitTime = data['exit_time'] as String?;
                          final allocatedHours = data['allocated_hours'] as String? ?? '00:00:00';

                          Color statusColor = AppTheme.accentRed;
                          IconData statusIcon = Icons.cancel;

                          if (status == 'PRESENT') {
                            statusColor = AppTheme.primaryGreen;
                            statusIcon = Icons.check_circle;
                          } else if (status == 'NOT EXITED') {
                            statusColor = AppTheme.accentOrange;
                            statusIcon = Icons.schedule;
                          }

                          // Format time from ISO8601 to HH:MM:SS (convert UTC to local timezone)
                          String formatTime(String? isoTime) {
                            if (isoTime == null) return '--:--:--';
                            try {
                              // Treat as UTC first, then convert to local
                              final dt = DateTime.parse(isoTime + 'Z').toLocal();
                              return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
                            } catch (e) {
                              print('❌ Error parsing time: $isoTime, error: $e');
                              return '--:--:--';
                            }
                          }

                          return Container(
                            padding: EdgeInsets.all(16.w),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  statusColor.withOpacity(isDark ? 0.12 : 0.06),
                                  statusColor.withOpacity(isDark ? 0.06 : 0.02),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: statusColor.withOpacity(isDark ? 0.3 : 0.15),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(statusIcon, color: statusColor, size: 24.sp),
                                    SizedBox(width: 12.w),
                                    Text(
                                      status,
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16.h),
                                // Entry Time
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Entry Time',
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            color: isDark ? Colors.white70 : AppTheme.textGray,
                                          ),
                                        ),
                                        Text(
                                          formatTime(entryTime),
                                          style: TextStyle(
                                            fontSize: 14.sp,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? Colors.white : AppTheme.textDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Exit Time
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Exit Time',
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            color: isDark ? Colors.white70 : AppTheme.textGray,
                                          ),
                                        ),
                                        Text(
                                          formatTime(exitTime),
                                          style: TextStyle(
                                            fontSize: 14.sp,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? Colors.white : AppTheme.textDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16.h),
                                // Allocated Hours
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Seated Hours',
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            color: isDark ? Colors.white70 : AppTheme.textGray,
                                          ),
                                        ),
                                        Text(
                                          allocatedHours,
                                          style: TextStyle(
                                            fontSize: 18.sp,
                                            fontWeight: FontWeight.w800,
                                            color: statusColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      SizedBox(height: 32.h),

                      // 📅 DATE FILTERS
                      Text(
                        "FILTER BY DATE",
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : AppTheme.textGray,
                        ),
                      ),
                      SizedBox(height: 10.h),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterButton('1 Month', '1month', isDark),
                            SizedBox(width: 10.w),
                            _buildFilterButton('3 Months', '3month', isDark),
                            SizedBox(width: 10.w),
                            _buildFilterButton('6 Months', '6month', isDark),
                            SizedBox(width: 10.w),
                            _buildFilterButton('Custom', 'custom', isDark),
                          ],
                        ),
                      ),
                      SizedBox(height: 20.h),

                      // 📊 ATTENDANCE HISTORY
                      Text(
                        "ATTENDANCE HISTORY",
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      FutureBuilder<Map<String, dynamic>>(
                        future: _fetchAttendanceHistory(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.h),
                                child: CircularProgressIndicator(color: AppTheme.primaryBlue),
                              ),
                            );
                          }

                          final data = snapshot.data ?? {};
                          final present = data['present'] as int? ?? 0;
                          final absent = data['absent'] as int? ?? 0;
                          final total = data['total'] as int? ?? 0;
                          final hours = data['hours'] as String? ?? '00:00:00';
                          final registered = data['registered'] as String? ?? '-';

                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.primaryBlue.withOpacity(isDark ? 0.12 : 0.06),
                                  AppTheme.primaryBlue.withOpacity(isDark ? 0.06 : 0.02),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.15),
                                width: 1.5,
                              ),
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                dataRowMinHeight: 48.h,
                                dataRowMaxHeight: 56.h,
                                headingRowColor: MaterialStateColor.resolveWith(
                                  (_) => AppTheme.primaryBlue.withOpacity(isDark ? 0.15 : 0.08),
                                ),
                                columns: [
                                  DataColumn(
                                    label: Text(
                                      'Subjects',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Registered',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Present',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryGreen,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Absent',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.accentRed,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Total',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Hours',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ),
                                ],
                                rows: [
                                  DataRow(
                                    cells: [
                                      DataCell(
                                        _selectedStudent != null
                                            ? Wrap(
                                                spacing: 4.w,
                                                runSpacing: 4.h,
                                                children: _getStudentSubjects(_selectedStudent!).isNotEmpty
                                                    ? _getStudentSubjects(_selectedStudent!)
                                                        .map(
                                                          (sub) => Container(
                                                            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                                            decoration: BoxDecoration(
                                                              color: AppTheme.primaryBlue.withOpacity(0.1),
                                                              borderRadius: BorderRadius.circular(4.r),
                                                            ),
                                                            child: Text(
                                                              sub,
                                                              style: TextStyle(
                                                                fontSize: 10.sp,
                                                                color: AppTheme.primaryBlue,
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                        .toList()
                                                    : [
                                                        Text(
                                                          '-',
                                                          style: TextStyle(fontSize: 12.sp, color: isDark ? Colors.white70 : AppTheme.textGray),
                                                        ),
                                                      ],
                                              )
                                            : Text(
                                                '-',
                                                style: TextStyle(fontSize: 12.sp, color: isDark ? Colors.white70 : AppTheme.textGray),
                                              ),
                                      ),
                                      DataCell(
                                        Text(
                                          registered,
                                          style: TextStyle(
                                            fontSize: 11.sp,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primaryBlue,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryGreen.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6.r),
                                          ),
                                          child: Text(
                                            '$present',
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primaryGreen,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                          decoration: BoxDecoration(
                                            color: AppTheme.accentRed.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6.r),
                                          ),
                                          child: Text(
                                            '$absent',
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.accentRed,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '$total',
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? Colors.white : AppTheme.textDark,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          hours,
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.primaryBlue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      SizedBox(height: 20.h),

                      // 📄 PDF DOWNLOAD BUTTON
                      if (_selectedStudent != null)
                        Container(
                          width: double.infinity,
                          height: 48.h,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.primaryBlue,
                                AppTheme.primaryBlue.withOpacity(0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12.r),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryBlue.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _generatePDFReport,
                              borderRadius: BorderRadius.circular(12.r),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.download_rounded, color: Colors.white, size: 20.sp),
                                  SizedBox(width: 8.w),
                                  Text(
                                    'Download Attendance Report',
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      SizedBox(height: 32.h),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
