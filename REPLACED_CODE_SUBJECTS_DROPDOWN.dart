// FILE: lib/presentation/screens/student_management_screen.dart

// ========================================
// REPLACEMENT 1: Replace _mapStudentRow() function
// Location: Line 712-744
// ========================================

Map<String, dynamic> _mapStudentRow(Map<String, dynamic> row) {
  String subject = row['subject']?.toString().trim() ?? '';
  final subs = row['subjects'];

  if (subject.isEmpty && subs is List && subs.isNotEmpty) {
    subject = subs.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList().join(', ');
  } else if (subject.isEmpty && subs is String) {
    subject = subs.replaceAll('{', '').replaceAll('}', '').replaceAll('[', '').replaceAll(']', '').trim();
  }

  final srRaw = row['sr_no']?.toString().trim() ?? '';
  final regUrl = (row['face_photo_url'] as String?)?.trim();
  final url = regUrl ?? '';

  if (kDebugMode) {
    debugPrint('📚 ${row['name']} → Subjects: ${_parseSubjectsList(row)}');
  }

  return {
    'id': row['id'],
    'name': row['name'],
    'userId': row['user_id'] ?? row['sr_no'] ?? '',
    'srNo': srRaw.isNotEmpty ? srRaw : (row['user_id']?.toString() ?? ''),
    'subject': subject,
    'subjectsList': _parseSubjectsList(row),
    'year': row['year'],
    'photoUrl': url,
    'hasFaceEmbedding': studentHasNonEmptyFaceEmbedding(row['face_embedding']),
  };
}

// ========================================
// REPLACEMENT 2: Replace _parseSubjectsList() function
// Location: Line 988-1002
// ========================================

List<String> _parseSubjectsList(Map<String, dynamic> row) {
  final subs = row['subjects'];
  final out = <String>[];

  if (subs is List) {
    for (final e in subs) {
      final s = e.toString().trim();
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }
  } else if (subs is String) {
    final cleaned = subs.replaceAll('{', '').replaceAll('}', '').replaceAll('[', '').replaceAll(']', '');
    if (cleaned.isNotEmpty) {
      final parts = cleaned.split(',');
      for (final p in parts) {
        final s = p.trim();
        if (s.isNotEmpty && !out.contains(s)) out.add(s);
      }
    }
  }

  if (out.isEmpty) {
    final single = row['subject']?.toString().trim() ?? '';
    if (single.isNotEmpty) out.add(single);
  }

  return out;
}

// ========================================
// ADD THIS: New function (add anywhere in class)
// ========================================

Future<void> forceRefreshStudentList() async {
  if (_instituteId == null) return;
  setState(() {
    _isLoadingStudents = true;
    _page = 0;
    _students.clear();
    _hasMore = true;
  });
  try {
    await _loadStudents(reset: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Refreshed - ${_students.length} students'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
