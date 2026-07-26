import 'package:flutter/material.dart';
import 'dart:async';

// Attendance status enum
enum AttendanceStatus {
  present,
  absent,
  late,
}

// Student model
class Student {
  final String id;
  final String name;
  final String rollNo;
  final String? email;

  Student({
    required this.id,
    required this.name,
    required this.rollNo,
    this.email,
  });
}

// Class Session model for scheduling
class ClassSession {
  final DateTime date;
  String className;
  TimeOfDay start;
  TimeOfDay end;

  ClassSession({
    required this.date,
    required this.className,
    required this.start,
    required this.end,
  });

  ClassSession copyWith({
    DateTime? date,
    String? className,
    TimeOfDay? start,
    TimeOfDay? end,
  }) {
    return ClassSession(
      date: date ?? this.date,
      className: className ?? this.className,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

// Attendance Record model
class AttendanceRecord {
  final DateTime dateTime;
  final String? status;
  final double? latitude;
  final double? longitude;
  final String? selfieUrl;

  AttendanceRecord({
    required this.dateTime,
    this.status,
    this.latitude,
    this.longitude,
    this.selfieUrl,
  });

  String get formattedDate {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    return '$day-$month-$year';
  }

  String get formattedTime {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get displayStatus {
    if (status != null) return status!;
    
    final classStart = AttendanceRepository.classStart;
    final recordTime = TimeOfDay.fromDateTime(dateTime);
    
    final startMinutes = classStart.hour * 60 + classStart.minute;
    final recordMinutes = recordTime.hour * 60 + recordTime.minute;
    
    if (recordMinutes <= startMinutes + 10) {
      return 'Present';
    } else if (recordMinutes <= startMinutes + 30) {
      return 'Late';
    } else {
      return 'Very Late';
    }
  }

  AttendanceRecord copyWith({
    DateTime? dateTime,
    String? status,
    double? latitude,
    double? longitude,
    String? selfieUrl,
  }) {
    return AttendanceRecord(
      dateTime: dateTime ?? this.dateTime,
      status: status ?? this.status,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      selfieUrl: selfieUrl ?? this.selfieUrl,
    );
  }
}

class AttendanceRepository {
  // 🔹 Stream controller for reactive updates
  static final _recordsController = StreamController<List<AttendanceRecord>>.broadcast();
  
  // 🔹 Current logged-in student records
  static final List<AttendanceRecord> _records = [];

  // 🔹 Stream getter for reactive updates
  static Stream<List<AttendanceRecord>> get recordsStream => _recordsController.stream;

  // 🔹 Class time window (teacher can change this)
  static TimeOfDay _classStart = const TimeOfDay(hour: 9, minute: 0);
  static TimeOfDay _classEnd = const TimeOfDay(hour: 9, minute: 30);

  // 🔹 All students in the class (teacher manages this)
  static final List<Student> _students = [];

  // 🔹 Teacher-managed attendance: Map<Date, Map<StudentId, Status>>
  static final Map<String, Map<String, AttendanceStatus>> _teacherAttendance = {};

  // 🔹 Class schedule: Map<Date, ClassSession>
  static final Map<String, ClassSession> _classSessions = {};

  // Getters
  static TimeOfDay get classStart => _classStart;
  static TimeOfDay get classEnd => _classEnd;

  // Update class time (teacher side)
  static void updateClassTime({
    required TimeOfDay start,
    required TimeOfDay end,
  }) {
    _classStart = start;
    _classEnd = end;
  }

  // ==================== STUDENT METHODS ====================
  
  // Get all students
  static List<Student> getStudents() {
    // Return empty list - students should be loaded from Firestore dynamically
    // This repository is for in-memory operations only
    return List.unmodifiable(_students);
  }

  // Add a student
  static void addStudent(Student student) {
    _students.add(student);
  }

  // Clear all students
  static void clearStudents() {
    _students.clear();
  }

  // ==================== TEACHER ATTENDANCE METHODS ====================

  // Get attendance for a specific date (returns map of studentId -> status)
  static Map<String, AttendanceStatus> getAttendanceForDate(DateTime date) {
    final dateKey = _dateKey(date);
    return Map.unmodifiable(_teacherAttendance[dateKey] ?? {});
  }

  // Set attendance for a specific student on a specific date
  static void setAttendanceForStudent({
    required DateTime date,
    required String studentId,
    required AttendanceStatus status,
  }) {
    final dateKey = _dateKey(date);
    
    if (!_teacherAttendance.containsKey(dateKey)) {
      _teacherAttendance[dateKey] = {};
    }
    
    _teacherAttendance[dateKey]![studentId] = status;
  }

  // Remove attendance for a specific student on a specific date
  static void removeAttendanceForStudent({
    required DateTime date,
    required String studentId,
  }) {
    final dateKey = _dateKey(date);
    _teacherAttendance[dateKey]?.remove(studentId);
  }

  // Get attendance statistics for a specific date
  static Map<String, int> getDateStatistics(DateTime date) {
    final dateKey = _dateKey(date);
    final dayAttendance = _teacherAttendance[dateKey] ?? {};
    
    int present = 0;
    int absent = 0;
    int late = 0;
    
    for (var status in dayAttendance.values) {
      switch (status) {
        case AttendanceStatus.present:
          present++;
          break;
        case AttendanceStatus.absent:
          absent++;
          break;
        case AttendanceStatus.late:
          late++;
          break;
      }
    }
    
    final totalStudents = _students.length;
    final notMarked = totalStudents - (present + absent + late);
    
    return {
      'present': present,
      'absent': absent,
      'late': late,
      'notMarked': notMarked,
      'total': totalStudents,
    };
  }

  // Helper to create date key (YYYY-MM-DD format)
  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // Clear all teacher attendance data
  static void clearTeacherAttendance() {
    _teacherAttendance.clear();
  }

  // ==================== CLASS SCHEDULE METHODS ====================

  // Get upcoming class sessions for next N days
  static List<ClassSession> getUpcomingSessions({int days = 30}) {
    final List<ClassSession> sessions = [];
    final now = DateTime.now();
    
    for (int i = 0; i < days; i++) {
      final date = now.add(Duration(days: i));
      
      // Skip weekends
      if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
        continue;
      }
      
      final dateKey = _dateKey(date);
      
      // Check if session already exists, otherwise create default
      if (_classSessions.containsKey(dateKey)) {
        sessions.add(_classSessions[dateKey]!);
      } else {
        // Create default session
        final session = ClassSession(
          date: date,
          className: 'Mathematics',
          start: _classStart,
          end: _classEnd,
        );
        _classSessions[dateKey] = session;
        sessions.add(session);
      }
    }
    
    return sessions;
  }

  // Update a class session
  static void updateSession(ClassSession session) {
    final dateKey = _dateKey(session.date);
    _classSessions[dateKey] = session;
    
    // If updating today's session, also update the global class time
    final now = DateTime.now();
    if (session.date.year == now.year &&
        session.date.month == now.month &&
        session.date.day == now.day) {
      _classStart = session.start;
      _classEnd = session.end;
    }
  }

  // Get session for a specific date
  static ClassSession? getSessionForDate(DateTime date) {
    final dateKey = _dateKey(date);
    return _classSessions[dateKey];
  }

  // Delete a session
  static void deleteSession(DateTime date) {
    final dateKey = _dateKey(date);
    _classSessions.remove(dateKey);
  }

  // Clear all sessions
  static void clearAllSessions() {
    _classSessions.clear();
  }

  // Get all sessions (for export/backup)
  static Map<String, ClassSession> getAllSessions() {
    return Map.unmodifiable(_classSessions);
  }

  // ==================== STUDENT RECORD METHODS (WITH STREAM SUPPORT) ====================

  // 🔥 Add a record for the CURRENT logged-in student (with stream notification)
  static void addRecord(AttendanceRecord record) {
    _records.add(record);
    _notifyListeners(); // Notify all listeners
  }

  // Get all records
  static List<AttendanceRecord> getRecords() {
    return List.unmodifiable(_records);
  }

  // Get records sorted by date (newest first)
  static List<AttendanceRecord> getRecordsSorted() {
    final sorted = List<AttendanceRecord>.from(_records);
    sorted.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return sorted;
  }

  // Get records for a specific month
  static List<AttendanceRecord> getRecordsForMonth(int year, int month) {
    return _records.where((record) {
      return record.dateTime.year == year && record.dateTime.month == month;
    }).toList();
  }

  // Get records for current month
  static List<AttendanceRecord> getCurrentMonthRecords() {
    final now = DateTime.now();
    return getRecordsForMonth(now.year, now.month);
  }

  static bool isTodayMarked() {
    final now = DateTime.now();
    return _records.any((r) =>
        r.dateTime.year == now.year &&
        r.dateTime.month == now.month &&
        r.dateTime.day == now.day);
  }

  static AttendanceRecord? latestToday() {
    final now = DateTime.now();
    final todayRecords = _records.where((r) =>
        r.dateTime.year == now.year &&
        r.dateTime.month == now.month &&
        r.dateTime.day == now.day);

    if (todayRecords.isEmpty) return null;

    return todayRecords.reduce((a, b) =>
        a.dateTime.isAfter(b.dateTime) ? a : b);
  }

  static List<AttendanceRecord> allRecords() => List.unmodifiable(_records);

  // Get monthly statistics
  static Map<String, int> getMonthlyStats() {
    final monthRecords = getCurrentMonthRecords();
    
    int present = 0;
    int late = 0;
    int veryLate = 0;
    
    for (var record in monthRecords) {
      final status = record.displayStatus;
      if (status == 'Present') {
        present++;
      } else if (status == 'Late') {
        late++;
      } else {
        veryLate++;
      }
    }
    
    return {
      'present': present,
      'late': late,
      'veryLate': veryLate,
      'total': monthRecords.length,
    };
  }

  // Get attendance percentage for current month
  static double getMonthlyPercentage() {
    final stats = getMonthlyStats();
    final total = stats['total'] ?? 0;
    
    if (total == 0) return 0.0;
    
    final present = stats['present'] ?? 0;
    return (present / total) * 100;
  }

  // Get total working days in current month
  static int getTotalWorkingDays() {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);
    
    int workingDays = 0;
    for (var day = firstDay; 
         day.isBefore(lastDay.add(const Duration(days: 1))); 
         day = day.add(const Duration(days: 1))) {
      if (day.weekday != DateTime.saturday && day.weekday != DateTime.sunday) {
        workingDays++;
      }
    }
    return workingDays;
  }

  // 🔥 Clear all records (with stream notification)
  static void clearRecords() {
    _records.clear();
    _notifyListeners();
  }

  // 🔥 Delete a specific record (with stream notification)
  static void deleteRecord(AttendanceRecord record) {
    _records.remove(record);
    _notifyListeners();
  }

  // 🔥 Add dummy data for testing (with stream notification)
  static void addDummyData() {
    final now = DateTime.now();
    
    for (int i = 20; i > 0; i--) {
      final date = now.subtract(Duration(days: i));
      
      if (date.weekday == DateTime.saturday || 
          date.weekday == DateTime.sunday) {
        continue;
      }
      
      if (i % 5 == 0) continue;
      
      final hour = i % 3 == 0 ? 9 : (i % 4 == 0 ? 9 : 9);
      final minute = i % 3 == 0 ? 5 : (i % 4 == 0 ? 25 : 45);
      
      _records.add(
        AttendanceRecord(
          dateTime: DateTime(
            date.year,
            date.month,
            date.day,
            hour,
            minute,
          ),
          status: minute <= 10 ? 'Present' : (minute <= 30 ? 'Late' : 'Very Late'),
          latitude: 19.223943,
          longitude: 73.080277,
        ),
      );
    }
    
    _notifyListeners(); // Notify after adding all dummy data
  }

  // Get count of records
  static int getRecordCount() {
    return _records.length;
  }

  // Check if any records exist
  static bool hasRecords() {
    return _records.isNotEmpty;
  }

  // Get last 7 days records
  static List<AttendanceRecord> getLast7DaysRecords() {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    
    return _records.where((record) {
      return record.dateTime.isAfter(sevenDaysAgo);
    }).toList()..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  // Get streak (consecutive days present)
  static int getCurrentStreak() {
    if (_records.isEmpty) return 0;
    
    final sorted = getRecordsSorted();
    final now = DateTime.now();
    int streak = 0;
    
    for (int i = 0; i < 30; i++) {
      final checkDate = now.subtract(Duration(days: i));
      
      if (checkDate.weekday == DateTime.saturday || 
          checkDate.weekday == DateTime.sunday) {
        continue;
      }
      
      final hasRecord = sorted.any((r) =>
          r.dateTime.year == checkDate.year &&
          r.dateTime.month == checkDate.month &&
          r.dateTime.day == checkDate.day);
      
      if (hasRecord) {
        streak++;
      } else {
        break;
      }
    }
    
    return streak;
  }

  // ==================== STREAM MANAGEMENT ====================

  // 🔥 Private method to notify all listeners
  static void _notifyListeners() {
    _recordsController.add(List.unmodifiable(_records));
  }

  // 🔥 Dispose the stream controller (call when app closes)
  static void dispose() {
    _recordsController.close();
  }
}
