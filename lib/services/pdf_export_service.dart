import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';

import '../core/app_db.dart';
import '../core/supabase_maps.dart';
import '../core/time_parse.dart';
import '../core/attendance_hours_db_reader.dart';
import '../core/attendance_presence_rules.dart';
// Institute holiday/open/close system removed.

class PdfExportService {
  static final DateFormat _pdfTimeFmt = DateFormat('HH:mm');
  static final DateFormat _pdfDateFmt = DateFormat('MMM dd, yyyy');

  /// Parse a DB date key (`yyyy-MM-dd`) as local calendar date (no timezone shift).
  static DateTime _parseDateKeyLocal(String dateKey) {
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(dateKey);
    } catch (_) {
      // Fallback for unexpected formats
      return DateTime.tryParse(dateKey)?.toLocal() ?? DateTime.now();
    }
  }

  static String _formatPdfLocalTime(DateTime dt) => _pdfTimeFmt.format(dt.toLocal());
  static String _formatPdfLocalDateFromKey(String dateKey) =>
      _pdfDateFmt.format(_parseDateKeyLocal(dateKey));

  /// Format decimal hours to HH:MM:SS string
  /// Example: 1.73 hours → "1h 43m 48s"
  static String _formatHoursAsDuration(double hours) {
    final totalSeconds = (hours * 3600).toInt();
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h}h ${m}m ${s}s';
  }

  static Future<Map<String, String>> _holidayReasons({
    required String instituteId,
    required String startDate,
    required String endDate,
  }) async {
    // Holiday system removed.
    return <String, String>{};
  }

  static String _srNoKey(Map<String, dynamic> s) {
    final u = s['user_id'] as String?;
    final sr = s['sr_no'] as String?;
    return (u != null && u.isNotEmpty) ? u : (sr ?? '');
  }

  static Map<String, dynamic> _additional(dynamic a) {
    if (a is Map<String, dynamic>) return Map<String, dynamic>.from(a);
    if (a is Map) {
      return a.map((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  static String _statusFromRow(Map<String, dynamic> r) {
    final add = _additional(r['additional']);
    final st = add['status']?.toString();
    if (st != null && st.isNotEmpty) return st;
    return 'present';
  }

  static String? _subjectFromRow(Map<String, dynamic> r) {
    final add = _additional(r['additional']);
    return add['subject']?.toString();
  }

  /// Groups rows that share the same calendar day and subject (case-insensitive).
  /// Rows with no subject use a shared `'General'` bucket for that date.
  static String _subjectMergeKey(Map<String, dynamic> r) {
    final s = _subjectFromRow(r)?.trim() ?? '';
    if (s.isEmpty) return '__general__';
    return s.toLowerCase();
  }

  static String _subjectDisplayFromGroup(List<Map<String, dynamic>> list) {
    for (final r in list) {
      final s = _subjectFromRow(r)?.trim() ?? '';
      if (s.isNotEmpty) return s;
    }
    return 'General';
  }

  static Map<String, dynamic> _mergeInOutRowsForDateSubject(
    String date,
    List<Map<String, dynamic>> list,
    String subjectDisplay,
  ) {
    DateTime? entryTime;
    DateTime? exitTime;
    var status = 'absent';
    double? hours;
    double? creditedHours; // Read from database credited_hours field
    String? creditedHoursNote; // Why the hours were credited this way
    var lectures = <String, dynamic>{};
    DateTime? latestTs;
    var autoClosedMissingExit = false;
    String? autoClosedNote;
    String? attendanceReason;

    for (final data in list) {
      final add = _additional(data['additional']);
      final et = parseAnyTimestamp(add['entryTime']);
      final xt = parseAnyTimestamp(add['exitTime']);
      if (et != null) {
        entryTime = entryTime == null || et.isBefore(entryTime!) ? et : entryTime;
      }
      if (xt != null) {
        exitTime = exitTime == null || xt.isAfter(exitTime!) ? xt : exitTime;
      }
    }

    void pickLectures(Map<String, dynamic> m) {
      if (m.isEmpty) return;
      lectures = Map<String, dynamic>.from(m);
    }

    for (final data in list) {
      final add = _additional(data['additional']);
      final typ = (data['type'] as String?)?.toLowerCase() ?? 'entry';
      final created = parseAnyTimestamp(data['created_at']);
      final st = _statusFromRow(data);
      if (st == 'present') status = 'present';

      // Read credited_hours and reason from database
      // ONLY read from exit records to avoid double-counting entry records
      if (typ == 'exit' && data['credited_hours'] != null) {
        final dbCredited = (data['credited_hours'] as num?)?.toDouble() ?? 0.0;
        if (dbCredited > 0) {
          creditedHours = dbCredited; // Use exit record value (takes precedence)
        }
      }
      if (creditedHours == null && add['hours'] != null) {
        hours = (add['hours'] as num).toDouble();
      }

      // Get the reason why hours were credited this way
      // Take the first non-empty note found from exit records
      if (creditedHoursNote == null && typ == 'exit' && data['hours_calculation_note'] != null) {
        final note = data['hours_calculation_note'] as String?;
        if (note != null && note.isNotEmpty) {
          creditedHoursNote = note;
        }
      }
      if (add['lectures'] is Map) {
        pickLectures(
          Map<String, dynamic>.from((add['lectures'] as Map).cast<String, dynamic>()),
        );
      }

      if (add['autoClosedMissingExit'] == true) {
        autoClosedMissingExit = true;
        final n = add['autoClosedNote']?.toString().trim();
        if (n != null && n.isNotEmpty) autoClosedNote = n;
      }
      final reasonText = add['attendanceReason']?.toString().trim();
      if (reasonText != null && reasonText.isNotEmpty) {
        attendanceReason = reasonText;
      }

      final etAdd = parseAnyTimestamp(add['entryTime']);
      final xtAdd = parseAnyTimestamp(add['exitTime']);

      if (created != null) {
        latestTs = latestTs == null || created.isAfter(latestTs!) ? created : latestTs;
      }

      if (typ == 'exit') {
        if (created != null) {
          exitTime = exitTime == null || created.isAfter(exitTime!) ? created : exitTime;
        }
        if (xtAdd != null) {
          exitTime = exitTime == null || xtAdd.isAfter(exitTime!) ? xtAdd : exitTime;
        }
      } else {
        if (created != null) {
          entryTime = entryTime == null || created.isBefore(entryTime!) ? created : entryTime;
        }
        if (etAdd != null) {
          entryTime = entryTime == null || etAdd.isBefore(entryTime!) ? etAdd : entryTime;
        }
      }
    }

    for (final data in list) {
      final add = _additional(data['additional']);
      final et = parseAnyTimestamp(add['entryTime']);
      final xt = parseAnyTimestamp(add['exitTime']);
      if (et != null) {
        entryTime = entryTime == null || et.isBefore(entryTime!) ? et : entryTime;
      }
      if (xt != null) {
        exitTime = exitTime == null || xt.isAfter(exitTime!) ? xt : exitTime;
      }
    }

    if (entryTime == null) {
      for (final data in list) {
        final typ = (data['type'] as String?)?.toLowerCase() ?? 'entry';
        if (typ != 'entry') continue;
        final c = parseAnyTimestamp(data['created_at']);
        if (c != null) {
          entryTime = entryTime == null || c.isBefore(entryTime!) ? c : entryTime;
        }
      }
    }
    if (exitTime == null) {
      for (final data in list) {
        final typ = (data['type'] as String?)?.toLowerCase() ?? 'entry';
        if (typ != 'exit') continue;
        final c = parseAnyTimestamp(data['created_at']);
        if (c != null) {
          exitTime = exitTime == null || c.isAfter(exitTime!) ? c : exitTime;
        }
      }
    }

    final typeEntry =
        list.any((d) => (d['type']?.toString().toLowerCase().trim() == 'entry'));
    final hasEntrySignal = entryTime != null || typeEntry;
    final credited = (creditedHours != null && creditedHours > 0) || (hours != null && hours > 0);
    if (hasEntrySignal ||
        autoClosedMissingExit ||
        credited ||
        (exitTime != null && status == 'present')) {
      status = 'present';
    } else {
      status = 'absent';
    }

    return {
      'date': date,
      'status': status,
      'subject': subjectDisplay,
      'timestamp': latestTs,
      'entryTime': entryTime,
      'exitTime': exitTime,
      'hours': creditedHours ?? hours, // Use credited_hours if available, otherwise use hours
      'lectures': lectures,
      'type': 'session',
      'autoClosedMissingExit': autoClosedMissingExit,
      if (autoClosedNote != null && autoClosedNote.isNotEmpty) 'autoClosedNote': autoClosedNote,
      if (attendanceReason != null && attendanceReason.isNotEmpty) 'attendanceReason': attendanceReason,
      if (creditedHoursNote != null && creditedHoursNote.isNotEmpty) 'creditedHoursNote': creditedHoursNote,
    };
  }

  /// True if [r] should be included when filtering reports/PDF by a single subject name.
  static bool rowMatchesSubjectFilter(Map<String, dynamic> r, String? selectedSubject) {
    if (selectedSubject == null ||
        selectedSubject.isEmpty ||
        selectedSubject == 'All Subjects') {
      return true;
    }
    final subj = _subjectFromRow(r) ?? '';
    if (subj.isEmpty) return false;
    if (subj == selectedSubject) return true;
    for (final part in subj.split(',')) {
      if (part.trim() == selectedSubject) return true;
    }
    return false;
  }

  /// One row per calendar day **per subject**: merges separate `type: entry` / `type: exit`
  /// rows from [attendance_in_out] within the same date and subject bucket.
  static List<Map<String, dynamic>> mergeAttendanceInOutRowsByDate(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return [];
    const sep = '|';
    final byComposite = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final d = r['attendance_date']?.toString() ?? '';
      if (d.isEmpty) continue;
      final mk = _subjectMergeKey(r);
      byComposite.putIfAbsent('$d$sep$mk', () => []).add(r);
    }
    final sortedKeys = byComposite.keys.toList()..sort((a, b) {
      final ia = a.indexOf(sep);
      final ib = b.indexOf(sep);
      final da = a.substring(0, ia);
      final db = b.substring(0, ib);
      final byDate = da.compareTo(db);
      if (byDate != 0) return byDate;
      final ka = a.substring(ia + sep.length);
      final kb = b.substring(ib + sep.length);
      if (ka == '__general__' && kb != '__general__') return 1;
      if (ka != '__general__' && kb == '__general__') return -1;
      return ka.compareTo(kb);
    });

    final out = <Map<String, dynamic>>[];
    for (final key in sortedKeys) {
      final i = key.indexOf(sep);
      final date = key.substring(0, i);
      final list = byComposite[key]!;
      final display = _subjectDisplayFromGroup(list);
      out.add(_mergeInOutRowsForDateSubject(date, list, display));
    }
    return out;
  }

  /// Generate PDF report for all students with daily attendance
  static Future<Uint8List> generateStudentsReport({
    required String instituteId,
    String? instituteName,
    required DateTime startDate,
    required DateTime endDate,
    String? subject,
  }) async {
    final pdf = pw.Document();
    final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);

    // Cap end date at yesterday (only show complete days, not today's incomplete data)
    var cappedEndDate = endDate;
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    if (cappedEndDate.isAfter(yesterday)) {
      cappedEndDate = yesterday;
    }
    final endDateStr = DateFormat('yyyy-MM-dd').format(cappedEndDate);
    final holidays = await _holidayReasons(
      instituteId: instituteId,
      startDate: startDateStr,
      endDate: endDateStr,
    );

    final code = await instituteCodeForId(instituteId);
    var attRows = await appDb
        .from('attendance_in_out')
        .select()
        .eq('institute_code', code)
        .gte('attendance_date', startDateStr)
        .lte('attendance_date', endDateStr);

    if (subject != null && subject != 'All Subjects') {
      attRows = attRows.where((raw) {
        final r = raw as Map<String, dynamic>;
        return rowMatchesSubjectFilter(r, subject);
      }).toList();
    }

    final studentsSnap = (await appDb.from('students').select().eq('institute_id', instituteId)).cast<Map<String, dynamic>>();

    // Sort students by SR No serially (numeric-aware)
    studentsSnap.sort((a, b) {
      final srA = _srNoKey(a);
      final srB = _srNoKey(b);
      final numA = int.tryParse(srA);
      final numB = int.tryParse(srB);
      if (numA != null && numB != null) return numA.compareTo(numB);
      return srA.compareTo(srB);
    });

    // Auto-detect holidays: if < 10% of students have attendance on a day, mark as holiday
    final studentCount = studentsSnap.length;
    final attendanceByDate = <String, Set<String>>{};
    for (final raw in attRows) {
      final data = raw as Map<String, dynamic>;
      final date = data['attendance_date'] as String? ?? '';
      final sid = data['student_id'] as String? ?? '';
      if (date.isNotEmpty && sid.isNotEmpty) {
        attendanceByDate.putIfAbsent(date, () => {}).add(sid);
      }
    }

    final autoDetectedHolidays = <String>{};
    for (final entry in attendanceByDate.entries) {
      final attendancePercent = (entry.value.length / (studentCount > 0 ? studentCount : 1)) * 100;
      if (attendancePercent < 10) {
        autoDetectedHolidays.add(entry.key);
      }
    }

    final Map<String, Map<String, dynamic>> studentData = {};
    final Map<String, List<Map<String, dynamic>>> studentAttendance = {};

    for (final s in studentsSnap) {
      final row = s as Map<String, dynamic>;
      final srNo = _srNoKey(row);
      if (srNo.isEmpty) continue;
      studentData[srNo] = {
        'name': row['name'] as String? ?? 'Unknown',
        'srNo': srNo,
        'photoUrl': row['photo_url'] as String? ?? row['face_photo_url'] as String? ?? '',
      };
      studentAttendance[srNo] = [];
    }

    final idToSrNo = <String, String>{};
    for (final s in studentsSnap) {
      final m = s as Map<String, dynamic>;
      final id = m['id'] as String?;
      if (id == null) continue;
      final rk = _srNoKey(m);
      if (rk.isNotEmpty) idToSrNo[id] = rk;
    }

    final Map<String, List<Map<String, dynamic>>> rawBySrNo = {};
    for (final raw in attRows) {
      final data = raw as Map<String, dynamic>;
      final sid = data['student_id'] as String? ?? '';
      final sr = data['sr_no'] as String? ?? '';
      var srNo = idToSrNo[sid] ?? '';
      if (srNo.isEmpty) {
        for (final s in studentsSnap) {
          final m = s as Map<String, dynamic>;
          if (m['id'] == sid || m['sr_no'] == sr || m['user_id'] == sr) {
            srNo = _srNoKey(m);
            break;
          }
        }
      }
      if (srNo.isEmpty) srNo = sr;
      if (srNo.isEmpty) continue;
      rawBySrNo.putIfAbsent(srNo, () => []).add(data);
    }

    // Build a map of credited hours per student per date
    // ONLY count exit records to avoid double-counting entry records
    final creditedHoursByStudentDate = <String, Map<String, double>>{};
    for (final raw in attRows) {
      final data = raw as Map<String, dynamic>;
      final typ = (data['type'] as String?)?.toLowerCase() ?? 'entry';

      // Skip entry records - only process exit records
      if (typ != 'exit') continue;

      final sid = data['student_id'] as String? ?? '';
      final sr = data['sr_no'] as String? ?? '';
      final date = data['attendance_date'] as String? ?? '';
      var srNo = idToSrNo[sid] ?? '';
      if (srNo.isEmpty) {
        for (final s in studentsSnap) {
          final m = s as Map<String, dynamic>;
          if (m['id'] == sid || m['sr_no'] == sr || m['user_id'] == sr) {
            srNo = _srNoKey(m);
            break;
          }
        }
      }
      if (srNo.isEmpty) srNo = sr;
      if (srNo.isEmpty || date.isEmpty) continue;

      final creditedHours = (data['credited_hours'] as num?)?.toDouble() ?? 0.0;
      creditedHoursByStudentDate.putIfAbsent(srNo, () => {});
      creditedHoursByStudentDate[srNo]![date] =
          (creditedHoursByStudentDate[srNo]![date] ?? 0.0) + creditedHours;
    }

    for (final e in rawBySrNo.entries) {
      final merged = mergeAttendanceInOutRowsByDate(e.value);
      studentAttendance.putIfAbsent(e.key, () => []);
      studentAttendance[e.key]!.addAll(merged);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      instituteName ?? 'Attendance Report',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (instituteName != null)
                      pw.Text(
                        'Institute ID: $instituteId',
                        style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '${_pdfDateFmt.format(startDate)} - ${_pdfDateFmt.format(endDate)}',
                      style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                    ),
                    if (subject != null && subject != 'All Subjects')
                      pw.Text(
                        'Subject: $subject',
                        style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                      ),
                  ],
                ),
                pw.Text(
                  _pdfDateFmt.format(DateTime.now()),
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Students Attendance Summary',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Roll No', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Present', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Absent', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Percentage', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Total credited hours',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                    ),
                  ),
                ],
              ),
              ...studentData.entries.map((entry) {
                final rollNumber = entry.key;
                final student = entry.value;
                final attendance = studentAttendance[rollNumber] ?? [];
                final presentCount = attendance.where((a) => a['status'] == 'present').length;

                // Calculate total days in date range (excluding auto-detected holidays)
                int totalDaysInRange = 0;
                var current = DateTime(startDate.year, startDate.month, startDate.day);
                final endDateObj = DateTime(endDate.year, endDate.month, endDate.day);
                while (current.isBefore(endDateObj) || current.isAtSameMomentAs(endDateObj)) {
                  final dateKey = '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';
                  if (!autoDetectedHolidays.contains(dateKey)) {
                    totalDaysInRange++;
                  }
                  current = current.add(const Duration(days: 1));
                }

                final absentCount = totalDaysInRange - presentCount;
                final total = totalDaysInRange;
                final percentage = total > 0 ? (presentCount / total * 100) : 0.0;
                // Read credited hours from database for this student
                var creditedTotal = 0.0;
                final studentCreditedMap = creditedHoursByStudentDate[rollNumber] ?? {};
                for (final hours in studentCreditedMap.values) {
                  creditedTotal += hours;
                }
                // Format as HH:mm:ss for consistency
                final duration = Duration(seconds: (creditedTotal * 3600).toInt());
                final creditedStr = creditedTotal > 0.0
                    ? '${duration.inHours}h ${duration.inMinutes % 60}m ${duration.inSeconds % 60}s'
                    : '—';

                return pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(rollNumber, style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        student['name'] as String? ?? 'Unknown',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('$presentCount', style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('$absentCount', style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('$total', style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: percentage >= 75 ? PdfColors.green : PdfColors.red,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(creditedStr, style: const pw.TextStyle(fontSize: 9)),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Generate individual student PDF report with photo, percentage, subject-wise attendance
  static Future<Uint8List> generateStudentReport({
    required String instituteId,
    String? instituteName,
    required String srNo,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final pdf = pw.Document();
    final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);
    final holidays = await _holidayReasons(
      instituteId: instituteId,
      startDate: startDateStr,
      endDate: endDateStr,
    );

    final allStudents = await appDb.from('students').select().eq('institute_id', instituteId);
    Map<String, dynamic>? studentData;
    for (final s in allStudents) {
      final m = s as Map<String, dynamic>;
      if (m['user_id'] == srNo || m['sr_no'] == srNo) {
        studentData = m;
        break;
      }
    }

    if (studentData == null) {
      if (kDebugMode) debugPrint('Student not found with srNo: $srNo');
      throw Exception('Student not found with sr_no: $srNo');
    }
    final studentId = studentData['id'] as String;
    final studentName = studentData['name'] as String? ?? 'Unknown';
    final photoUrl = studentData['photo_url'] as String? ?? studentData['face_photo_url'] as String?;

    final code = await instituteCodeForId(instituteId);

    // Auto-detect holidays: if < 10% of students have attendance on a day, mark as holiday
    final allStudentsCount = allStudents.length;
    final allAttRows = await appDb
        .from('attendance_in_out')
        .select()
        .eq('institute_code', code)
        .gte('attendance_date', startDateStr)
        .lte('attendance_date', endDateStr);

    final attendanceByDate = <String, Set<String>>{};
    for (final raw in allAttRows) {
      final data = raw as Map<String, dynamic>;
      final date = data['attendance_date'] as String? ?? '';
      final sid = data['student_id'] as String? ?? '';
      if (date.isNotEmpty && sid.isNotEmpty) {
        attendanceByDate.putIfAbsent(date, () => {}).add(sid);
      }
    }

    final autoDetectedHolidays = <String>{};
    for (final entry in attendanceByDate.entries) {
      final attendancePercent = (entry.value.length / (allStudentsCount > 0 ? allStudentsCount : 1)) * 100;
      if (attendancePercent < 10) {
        autoDetectedHolidays.add(entry.key);
      }
    }

    final rawAtt = await appDb
        .from('attendance_in_out')
        .select()
        .eq('institute_code', code)
        .eq('student_id', studentId)
        .gte('attendance_date', startDateStr)
        .lte('attendance_date', endDateStr)
        .order('attendance_date');

    final attendanceDocs = rawAtt.map((e) => e as Map<String, dynamic>).toList();
    final dailyAttendance = mergeAttendanceInOutRowsByDate(attendanceDocs);

    // Get dates from attendance records
    final attendanceDates = <String>{};
    for (final record in dailyAttendance) {
      final date = record['date'] as String? ?? '';
      if (date.isNotEmpty) attendanceDates.add(date);
    }

    // Generate all days in range and mark missing ones as absent
    final allDailyDetails = <Map<String, dynamic>>[];
    var current = DateTime(startDate.year, startDate.month, startDate.day);
    var endDateObj = DateTime(endDate.year, endDate.month, endDate.day);

    // Cap end date at yesterday (only show complete days, not today's incomplete data)
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayObj = DateTime(yesterday.year, yesterday.month, yesterday.day);
    if (endDateObj.isAfter(yesterdayObj)) {
      endDateObj = yesterdayObj;
    }

    while (current.isBefore(endDateObj) || current.isAtSameMomentAs(endDateObj)) {
      final dateKey = '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';

      if (attendanceDates.contains(dateKey)) {
        // Day with attendance - already in dailyAttendance
        final record = dailyAttendance.firstWhere(
          (r) => (r['date'] as String?)?.contains(dateKey) ?? false,
          orElse: () => {},
        );
        if (record.isNotEmpty) allDailyDetails.add(record);
      } else if (autoDetectedHolidays.contains(dateKey)) {
        // Auto-detected holiday
        allDailyDetails.add({
          'date': dateKey,
          'status': 'holiday',
          'reason': 'Auto-detected (< 10% attendance)',
        });
      } else {
        // Absent day - no attendance and not a holiday
        allDailyDetails.add({
          'date': dateKey,
          'status': 'absent',
          'subject': '-',
        });
      }

      current = current.add(const Duration(days: 1));
    }

    final dailyDetails = allDailyDetails..sort((a, b) {
      final da = a['date'] as String;
      final db = b['date'] as String;
      final byDate = da.compareTo(db);
      if (byDate != 0) return byDate;
      final ha = a['status'] == 'holiday';
      final hb = b['status'] == 'holiday';
      if (ha != hb) return ha ? 1 : -1;
      final sa = (a['subject'] as String? ?? '').toLowerCase();
      final sb = (b['subject'] as String? ?? '').toLowerCase();
      return sa.compareTo(sb);
    });

    // Count total days in date range (including auto-detected holidays)
    // Note: current and endDateObj already declared above
    var totalDaysInRange = 0;
    var tempCurrent = DateTime(startDate.year, startDate.month, startDate.day);
    while (tempCurrent.isBefore(endDateObj) || tempCurrent.isAtSameMomentAs(endDateObj)) {
      totalDaysInRange++;
      tempCurrent = tempCurrent.add(const Duration(days: 1));
    }

    // Count present days using same logic as web report: studentDayPresentFromInOutRows
    // A student is present if they have ANY entry or credited hours (not just status=='present')
    int presentCount = 0;
    for (final detail in allDailyDetails) {
      final status = detail['status'] as String?;
      // Count as present if: status is 'present' (has entry/hours) or not a holiday/absent
      if (status == 'present') {
        presentCount++;
      }
    }

    final totalLectures = dailyAttendance.length;
    final absentCount = totalDaysInRange - presentCount;
    final percentage = totalDaysInRange > 0 ? (presentCount / totalDaysInRange * 100) : 0.0;

    // Calculate total credited hours from merged records (one per day/subject)
    // NOT from raw records (which include both entry and exit)
    var periodCreditedTotal = 0.0;
    for (final record in dailyAttendance) {
      final creditedHours = (record['hours'] as num?)?.toDouble() ?? 0.0;
      if (creditedHours > 0) {
        periodCreditedTotal += creditedHours;
      }
    }
    final periodDuration = Duration(seconds: (periodCreditedTotal * 3600).toInt());

    pw.ImageProvider? photoProvider;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(photoUrl));
        if (response.statusCode == 200) {
          photoProvider = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error loading photo: $e');
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (photoProvider != null)
                pw.Container(
                  width: 80,
                  height: 80,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: PdfColors.grey400, width: 2),
                  ),
                  child: pw.ClipOval(
                    child: pw.Image(photoProvider, fit: pw.BoxFit.cover),
                  ),
                )
              else
                pw.Container(
                  width: 80,
                  height: 80,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    color: PdfColors.grey300,
                    border: pw.Border.all(color: PdfColors.grey400, width: 2),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      'STUDENT',
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      studentName,
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (instituteName != null)
                      pw.Text(
                        instituteName,
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue700),
                      ),
                    pw.Text(
                      'Institute ID: $instituteId',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Sr No: $srNo',
                      style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '${_pdfDateFmt.format(startDate)} - ${_pdfDateFmt.format(endDate)}',
                      style: pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  children: [
                    pw.Text(
                      '$totalDaysInRange',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue700,
                      ),
                    ),
                    pw.Text(
                      'Total sessions',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      '$presentCount',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green700,
                      ),
                    ),
                    pw.Text(
                      'Present',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      '$absentCount',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red700,
                      ),
                    ),
                    pw.Text(
                      'Absent',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: percentage >= 75 ? PdfColors.green700 : PdfColors.red700,
                      ),
                    ),
                    pw.Text(
                      'Attendance %',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      periodCreditedTotal > 0.0
                          ? '${periodDuration.inHours}h ${periodDuration.inMinutes % 60}m ${periodDuration.inSeconds % 60}s'
                          : '—',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo700,
                      ),
                    ),
                    pw.Text(
                      'Total credited hours',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Daily Attendance Details',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (dailyDetails.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Text(
                'No attendance records found for the selected date range.',
                style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                textAlign: pw.TextAlign.center,
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Subject', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Entry Time', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Exit Time', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Credited Hours',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                  ],
                ),
                ...dailyDetails.map((record) {
                  final date = record['date'] as String;
                  final status = record['status'] as String;
                  final reason = record['reason'] as String?;
                  final subjectLabel =
                      status == 'holiday' ? '—' : (record['subject'] as String? ?? 'General');
                  final entryTime = record['entryTime'] as DateTime?;
                  final exitTime = record['exitTime'] as DateTime?;
                  var entryTimeStr = '-';
                  if (entryTime != null) {
                    entryTimeStr = _formatPdfLocalTime(entryTime);
                  }

                  var exitTimeStr = '-';
                  final autoClosed = record['autoClosedMissingExit'] == true;
                  final policyNote = record['autoClosedNote'] as String?;
                  if (exitTime != null) {
                    exitTimeStr = _formatPdfLocalTime(exitTime);
                  } else if (autoClosed) {
                    exitTimeStr = 'No Exit';
                  } else if (status == 'absent') {
                    exitTimeStr = 'No Exit';
                  } else if (status == 'holiday') {
                    exitTimeStr = reason == null || reason.isEmpty ? 'Holiday' : reason;
                  }

                  final hc = record['hours'] as num?;
                  final attendanceReason = record['attendanceReason'] as String?;
                  final creditedHoursNote = record['creditedHoursNote'] as String?;
                  final String creditedStr;

                  if (autoClosed) {
                    final h = record['hours'];
                    final hStr = h is num
                        ? _formatHoursAsDuration(h as double)
                        : '';
                    final tail = h is num ? ' ($hStr credited)' : '';
                    final reason = creditedHoursNote ?? policyNote ?? 'Student did not exit';
                    creditedStr = '$reason$tail';
                  } else if (hc != null && hc > 0) {
                    final hoursFormatted = _formatHoursAsDuration(hc.toDouble());
                    final reason = creditedHoursNote ?? '';
                    creditedStr = reason.isNotEmpty
                        ? '$hoursFormatted - $reason'
                        : hoursFormatted;
                  } else {
                    creditedStr = '—';
                  }

                  var statusCell = status == 'holiday'
                      ? 'Holiday'
                      : status == 'absent'
                          ? 'Absent'
                          : (status == 'pending' ? 'Pending' : 'Present');
                  if (autoClosed && status == 'present') {
                    statusCell = 'Present (policy)';
                  }

                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          _formatPdfLocalDateFromKey(date),
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(subjectLabel, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(entryTimeStr, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(exitTimeStr, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(creditedStr, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          statusCell,
                          style: pw.TextStyle(
                            fontSize: 9,
                            color: status == 'holiday'
                                ? PdfColors.orange700
                                : status == 'absent'
                                ? PdfColors.red700
                                : (status == 'pending' ? PdfColors.orange700 : PdfColors.green700),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Total (period)',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('—', style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('—', style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('—', style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        periodCreditedTotal > 0.0
                            ? '${periodDuration.inHours}h ${periodDuration.inMinutes % 60}m ${periodDuration.inSeconds % 60}s'
                            : '—',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        '$presentCount / $totalLectures sessions',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Save PDF to device and return file path.
  /// Tries to save to the Downloads folder if possible.
  static Future<String> savePdfToDevice(Uint8List pdfBytes, String fileName) async {
    Directory? directory;
    try {
      if (Platform.isAndroid) {
        // Try the standard Android Downloads folder first
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          directory = downloadDir;
        } else {
          // Fallback to app-specific external storage Downloads directory
          final externalDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
          if (externalDirs != null && externalDirs.isNotEmpty) {
            directory = externalDirs.first;
          } else {
            directory = await getExternalStorageDirectory();
          }
        }
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        // Desktop platforms
        directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }
    } catch (e) {
      debugPrint('Error finding save directory: $e');
    }

    directory ??= await getApplicationDocumentsDirectory();

    // Ensure filename is safe and unique
    final safeFileName = fileName.replaceAll(RegExp(r'[^\w\s\.-]'), '_');
    var file = File('${directory.path}/$safeFileName');

    // If file exists, append timestamp to avoid overwriting
    if (await file.exists()) {
      final nameWithoutExt = safeFileName.contains('.')
          ? safeFileName.substring(0, safeFileName.lastIndexOf('.'))
          : safeFileName;
      final ext = safeFileName.contains('.')
          ? safeFileName.substring(safeFileName.lastIndexOf('.'))
          : '.pdf';
      final timestamp = DateFormat('HHmmss').format(DateTime.now());
      file = File('${directory.path}/${nameWithoutExt}_$timestamp$ext');
    }

    await file.writeAsBytes(pdfBytes);
    return file.path;
  }

  /// Share/Print PDF
  static Future<void> sharePdf(Uint8List pdfBytes, String fileName) async {
    await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
    );
  }
}
