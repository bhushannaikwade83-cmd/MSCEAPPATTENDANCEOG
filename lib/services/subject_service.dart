import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../core/app_db.dart';
import 'database_init_service.dart';

// ─── Subject list cache (per-institute, 10 min TTL) ───────────────────────────
final _subjectCache   = <String, List<Map<String, dynamic>>>{};
final _subjectCacheAt = <String, DateTime>{};
const _kSubjectCacheTtl = Duration(minutes: 10);

void invalidateSubjectCache([String? instituteId]) {
  if (instituteId == null) {
    _subjectCache.clear();
    _subjectCacheAt.clear();
  } else {
    _subjectCache.remove(instituteId);
    _subjectCacheAt.remove(instituteId);
  }
}

/// Predefined subjects in `institute_subjects`.
class SubjectService {
  /// Initialize default subjects for an institute
  Future<Map<String, dynamic>> initializeDefaultSubjects(String instituteId) async {
    try {
      await DatabaseInitService.ensureInitialized();

      final defaultSubjects = getPredefinedSubjects();
      final rows =
          await appDb.from('institute_subjects').select('id, name').eq('institute_id', instituteId);

      for (final r in rows) {
        final name = r['name'] as String? ?? '';
        if (!defaultSubjects.contains(name)) {
          await appDb.from('institute_subjects').delete().eq('id', r['id']);
        }
      }

      final after =
          await appDb.from('institute_subjects').select('name').eq('institute_id', instituteId);
      final existingNames = after.map((e) => e['name'] as String).toSet();

      for (final subject in defaultSubjects) {
        if (!existingNames.contains(subject)) {
          await appDb.from('institute_subjects').insert({
            'institute_id': instituteId,
            'name': subject,
            'code': _generateSubjectCode(subject),
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }

      if (kDebugMode) {
        debugPrint('✅ Initialized ${defaultSubjects.length} predefined subjects');
      }

      return {
        'success': true,
        'message': 'Subjects initialized successfully',
        'count': defaultSubjects.length,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error initializing subjects: $e');
      return {
        'success': false,
        'message': 'Error initializing subjects: ${e.toString()}',
      };
    }
  }

  String _generateSubjectCode(String subjectName) {
    return subjectName
        .toUpperCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^A-Z0-9_]'), '');
  }

  List<String> getPredefinedSubjects() {
    return [
      'GCC-TBC ENGLISH 30 WPM',
      'GCC-TBC ENGLISH 40 WPM',
      'GCC-TBC ENGLISH 50 WPM',
      'GCC-TBC ENGLISH 60 WPM',
      'GCC-TBC MARATHI 30 WPM',
      'GCC-TBC MARATHI 40 WPM',
      'GCC-TBC HINDI 30 WPM',
      'GCC-TBC HINDI 40 WPM',
    ];
  }

  Future<Map<String, dynamic>> addSubject({
    required String instituteId,
    required String subjectName,
  }) async {
    try {
      await DatabaseInitService.ensureInitialized();

      if (subjectName.isEmpty) {
        return {'success': false, 'message': 'Subject name is required'};
      }

      final predefinedSubjects = getPredefinedSubjects();
      if (!predefinedSubjects.contains(subjectName)) {
        return {
          'success': false,
          'message': 'Only predefined subjects are allowed. Please select from the available subjects.',
        };
      }

      final existing = await appDb
          .from('institute_subjects')
          .select('id')
          .eq('institute_id', instituteId)
          .eq('name', subjectName)
          .maybeSingle();

      if (existing != null) {
        return {
          'success': false,
          'message': 'Subject "$subjectName" already exists',
        };
      }

      await appDb.from('institute_subjects').insert({
        'institute_id': instituteId,
        'name': subjectName,
        'code': _generateSubjectCode(subjectName),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      invalidateSubjectCache(instituteId);

      if (kDebugMode) {
        debugPrint('✅ Subject added: $subjectName');
      }

      return {'success': true, 'message': 'Subject added successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error adding subject: $e');
      return {
        'success': false,
        'message': 'Error adding subject: ${e.toString()}',
      };
    }
  }

  Future<List<Map<String, dynamic>>> getSubjects(String instituteId) async {
    try {
      // Return cached list if fresh (subjects rarely change).
      final cachedAt = _subjectCacheAt[instituteId];
      if (cachedAt != null &&
          DateTime.now().difference(cachedAt) < _kSubjectCacheTtl &&
          _subjectCache.containsKey(instituteId)) {
        if (kDebugMode) debugPrint('💾 getSubjects: cache hit for $instituteId');
        return _subjectCache[instituteId]!;
      }

      final predefinedSubjects = getPredefinedSubjects();

      final rows = await appDb
          .from('institute_subjects')
          .select('id, name, code')
          .eq('institute_id', instituteId)
          .order('name');

      final result = rows
          .map((data) {
            return {
              'id': data['id']?.toString() ?? '',
              'name': data['name'] ?? '',
              'code': data['code'] ?? '',
              'isActive': true,
            };
          })
          .where((subject) => predefinedSubjects.contains(subject['name']))
          .toList();

      _subjectCache[instituteId]   = result;
      _subjectCacheAt[instituteId] = DateTime.now();
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting subjects: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> updateSubject({
    required String instituteId,
    required String subjectId,
    String? subjectName,
    bool? isActive,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (subjectName != null) {
        final predefinedSubjects = getPredefinedSubjects();
        if (!predefinedSubjects.contains(subjectName)) {
          return {
            'success': false,
            'message': 'Only predefined subjects are allowed. Cannot change to a non-predefined subject.',
          };
        }
        updateData['name'] = subjectName;
        updateData['code'] = _generateSubjectCode(subjectName);
      }
      if (updateData.isEmpty && isActive == null) {
        return {'success': false, 'message': 'No fields to update'};
      }

      await appDb.from('institute_subjects').update(updateData).eq('id', subjectId).eq('institute_id', instituteId);
      invalidateSubjectCache(instituteId);
      return {'success': true, 'message': 'Subject updated successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error updating subject: $e');
      return {
        'success': false,
        'message': 'Error updating subject: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> deleteSubject(String instituteId, String subjectId) async {
    try {
      await appDb.from('institute_subjects').delete().eq('id', subjectId).eq('institute_id', instituteId);
      invalidateSubjectCache(instituteId);
      return {'success': true, 'message': 'Subject deleted successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error deleting subject: $e');
      return {
        'success': false,
        'message': 'Error deleting subject: ${e.toString()}',
      };
    }
  }
}
