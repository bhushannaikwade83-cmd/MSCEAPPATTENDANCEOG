import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import '../core/app_db.dart';
import '../core/supabase_maps.dart';
import '../config/b2b_storage_config.dart';
import 'validation_service.dart';

const _payloadPhotoKeys = <String>{
  'entryPhoto',
  'exitPhoto',
  'entryPhotoPath',
  'exitPhotoPath',
  'entryPhotoFileId',
  'exitPhotoFileId',
  'photoUrl',
  'faceScanPhoto',
  'faceScanPhotoPath',
  'faceScanPhotoFileId',
};

void _removePhotoKeysFromMap(Map<String, dynamic> m) {
  for (final k in _payloadPhotoKeys) {
    m.remove(k);
  }
}

/// Removes embedded attendance photo URLs/paths from teacher_attendance.payload (top-level, subjectSessions, lectures).
Map<String, dynamic> stripTeacherAttendancePayloadPhotos(Map<String, dynamic> raw) {
  final out = Map<String, dynamic>.from(raw);
  _removePhotoKeysFromMap(out);

  final ss = out['subjectSessions'];
  if (ss is Map) {
    final next = <String, dynamic>{};
    for (final e in ss.entries) {
      final v = e.value;
      if (v is Map) {
        final inner = Map<String, dynamic>.from(v.cast<String, dynamic>());
        _removePhotoKeysFromMap(inner);
        next[e.key.toString()] = inner;
      } else {
        next[e.key.toString()] = v;
      }
    }
    out['subjectSessions'] = next;
  }

  final lec = out['lectures'];
  if (lec is Map) {
    final next = <String, dynamic>{};
    for (final e in lec.entries) {
      final v = e.value;
      if (v is Map) {
        final inner = Map<String, dynamic>.from(v.cast<String, dynamic>());
        _removePhotoKeysFromMap(inner);
        next[e.key.toString()] = inner;
      } else {
        next[e.key.toString()] = v;
      }
    }
    out['lectures'] = next;
  }

  return out;
}

Map<String, dynamic>? _stripAttendanceAdditional(dynamic additional) {
  if (additional == null) return null;
  if (additional is! Map) return null;
  final m = Map<String, dynamic>.from(additional.cast<String, dynamic>());
  _removePhotoKeysFromMap(m);
  return m;
}

/// B2 storage service via Supabase Edge proxy.
/// Client never receives B2 account keys.
class B2BStorageService {
  static String get bucketName => B2BStorageConfig.bucketName;
  static String get bucketId => B2BStorageConfig.bucketId;

  // ✅ Database-level caching (shared across all users/devices)
  // In-memory cache for faster access (within same app instance)
  static final Map<String, _CachedUrl> _memoryCache = {};

  // Track cleanup timing to avoid excessive database operations
  static DateTime _lastCleanup = DateTime.now();
  static const Duration _cleanupInterval = Duration(hours: 1);

  /// Clean up expired URLs from database (runs periodically)
  static Future<void> _cleanExpiredDatabaseCache() async {
    try {
      await appDb
          .from('cached_photo_urls')
          .delete()
          .lt('expires_at', DateTime.now().toIso8601String());
      if (kDebugMode) debugPrint('🧹 Cleaned expired URLs from database');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error cleaning database cache: $e');
    }
  }

  static String generatePhotoPath({
    required String instituteId,
    required String folderYear,
    required String rollNumber,
    required String subject,
    required String date,
    String? photoType,
  }) {
    final cleanSubject = subject
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
        .toLowerCase();
    final cleanRollNumber = rollNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final fileName = photoType != null && (photoType == 'entry' || photoType == 'exit')
        ? '$photoType.jpg'
        : 'photo.jpg';
    return '$instituteId/$folderYear/$cleanRollNumber/$cleanSubject/$date/$fileName';
  }

  static Future<Map<String, dynamic>> _edgeInvoke(String action, Map<String, dynamic> body) async {
    final result = await appDb.functions.invoke(
      'b2-storage-proxy',
      body: {
        'action': action,
        ...body,
      },
    );
    final data = result.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry(k.toString(), v));
    throw Exception('Invalid response from b2-storage-proxy');
  }

  /// Upload a generic file to B2 and return its public URL.
  ///
  /// This is used by registration and verification flows that already know
  /// the exact storage path they want to write.
  static Future<String> uploadFile(
    String objectPath,
    List<int> fileBytes, {
    String contentType = 'image/jpeg',
  }) async {
    try {
      final trimmedPath = objectPath.trim();
      if (trimmedPath.isEmpty) {
        throw Exception('Object path is required');
      }
      if (fileBytes.isEmpty) {
        throw Exception('File bytes are empty');
      }

      final uploadToken = await _edgeInvoke('upload_url', {});
      final uploadUrl = (uploadToken['uploadUrl'] ?? '').toString();
      final uploadAuthToken = (uploadToken['uploadAuthToken'] ?? '').toString();
      final downloadUrl = (uploadToken['downloadUrl'] ?? '').toString();
      final edgeBucketName = (uploadToken['bucketName'] ?? bucketName).toString();

      if (uploadUrl.isEmpty || uploadAuthToken.isEmpty || downloadUrl.isEmpty) {
        throw Exception('Failed to obtain secure upload token');
      }

      final sha1Hash = sha1.convert(fileBytes).toString();
      final encodedPath = Uri.encodeComponent(trimmedPath);
      final uploadResponse = await http.post(
        Uri.parse(uploadUrl),
        headers: {
          'Authorization': uploadAuthToken,
          'Content-Type': contentType,
          'X-Bz-File-Name': encodedPath,
          'X-Bz-Content-Type': contentType,
          'X-Bz-Content-Sha1': sha1Hash,
        },
        body: fileBytes,
      );

      if (uploadResponse.statusCode != 200) {
        throw Exception('Upload failed: ${uploadResponse.statusCode} ${uploadResponse.body}');
      }

      return '$downloadUrl/file/$edgeBucketName/$encodedPath';
    } catch (e) {
      if (kDebugMode) debugPrint('❌ uploadFile failed: $e');
      rethrow;
    }
  }

  static Future<Map<String, String>> uploadAttendancePhoto({
    required String instituteId,
    required String folderYear,
    required String rollNumber,
    required String subject,
    required String date,
    required List<int> photoBytes,
    String? photoType,
  }) async {
    try {
      final instituteIdError = ValidationService.validateInstituteId(instituteId);
      if (instituteIdError != null) throw Exception('Invalid institute ID: $instituteIdError');
      final rollNumberError = ValidationService.validateRollNumber(rollNumber);
      if (rollNumberError != null) throw Exception('Invalid roll number: $rollNumberError');
      final subjectError = ValidationService.validateSubject(subject);
      if (subjectError != null) throw Exception('Invalid subject: $subjectError');
      final fileSizeError = ValidationService.validateFileSize(photoBytes.length, maxSizeKB: 100);
      if (fileSizeError != null) throw Exception('File size validation failed: $fileSizeError');
      // Accept both date format (YYYY-MM-DD) and timestamp (milliseconds)
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$|^\d{13,}$').hasMatch(date)) {
        throw Exception('Invalid date format. Expected YYYY-MM-DD or timestamp');
      }
      if (folderYear.isEmpty || folderYear.length > 50) throw Exception('Invalid folder year');

      final storagePath = generatePhotoPath(
        instituteId: instituteId,
        folderYear: folderYear,
        rollNumber: rollNumber,
        subject: subject,
        date: date,
        photoType: photoType,
      );

      final uploadToken = await _edgeInvoke('upload_url', {});
      final uploadUrl = (uploadToken['uploadUrl'] ?? '').toString();
      final uploadAuthToken = (uploadToken['uploadAuthToken'] ?? '').toString();
      final downloadUrl = (uploadToken['downloadUrl'] ?? '').toString();
      final edgeBucketName = (uploadToken['bucketName'] ?? bucketName).toString();

      if (uploadUrl.isEmpty || uploadAuthToken.isEmpty || downloadUrl.isEmpty) {
        throw Exception('Failed to obtain secure upload token');
      }

      final sha1Hash = sha1.convert(photoBytes).toString();
      final encodedPath = Uri.encodeComponent(storagePath);
      final uploadResponse = await http.post(
        Uri.parse(uploadUrl),
        headers: {
          'Authorization': uploadAuthToken,
          'Content-Type': 'image/jpeg',
          'X-Bz-File-Name': encodedPath,
          'X-Bz-Content-Type': 'image/jpeg',
          'X-Bz-Content-Sha1': sha1Hash,
        },
        body: photoBytes,
      );

      if (uploadResponse.statusCode != 200) {
        throw Exception('Upload failed: ${uploadResponse.statusCode} ${uploadResponse.body}');
      }

      final uploadJson = jsonDecode(uploadResponse.body) as Map<String, dynamic>;
      final fileId = (uploadJson['fileId'] ?? '').toString();
      final publicUrl = '$downloadUrl/file/$edgeBucketName/$encodedPath';
      return {
        'url': publicUrl,
        'path': storagePath,
        'bucket': edgeBucketName,
        'fileId': fileId,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ uploadAttendancePhoto failed: $e');
      rethrow;
    }
  }

  static Future<void> deleteAttendancePhoto(String objectPath, {String? fileId}) async {
    final fid = (fileId ?? '').trim();
    if (fid.isEmpty) {
      if (kDebugMode) {
        debugPrint('ℹ️ deleteAttendancePhoto skipped (missing fileId) for $objectPath');
      }
      return;
    }
    await _edgeInvoke('delete_file_version', {
      'fileName': objectPath,
      'fileId': fid,
    });
  }

  static Future<String> getPhotoUrl(String objectPath) async {
    try {
      final now = DateTime.now();

      // ✅ Step 0: Periodically clean up expired entries from database
      if (now.difference(_lastCleanup) > _cleanupInterval) {
        _lastCleanup = now;
        _cleanExpiredDatabaseCache(); // Fire and forget
      }

      // ✅ Step 1: Check in-memory cache first (fastest)
      if (_memoryCache.containsKey(objectPath)) {
        final cached = _memoryCache[objectPath]!;
        if (cached.expiresAt.isAfter(now)) {
          if (kDebugMode) debugPrint('📦 Memory cache HIT for $objectPath');
          return cached.url;
        }
      }

      // ✅ Step 2: Check database cache (shared across all users/devices)
      if (kDebugMode) debugPrint('🔍 Checking database cache for $objectPath');

      final cachedRecord = await appDb
          .from('cached_photo_urls')
          .select('photo_url,authorization_token,expires_at')
          .eq('object_path', objectPath)
          .maybeSingle();

      if (cachedRecord != null) {
        final expiresAt = DateTime.parse(cachedRecord['expires_at'] as String);
        if (expiresAt.isAfter(now)) {
          final photoUrl = cachedRecord['photo_url'] as String;
          // ✅ Restore to memory cache for faster future access
          _memoryCache[objectPath] = _CachedUrl(
            url: photoUrl,
            expiresAt: expiresAt,
          );
          if (kDebugMode) debugPrint('📦 Database cache HIT for $objectPath');
          return photoUrl;
        }
      }

      // ✅ Step 3: API call only if not cached
      if (kDebugMode) debugPrint('🔄 Fetching new URL for $objectPath (API call)');

      final resp = await _edgeInvoke('download_auth', {
        'objectPath': objectPath,
        'validSeconds': 1800,  // 30 minutes validity (increased from 5 min)
      });
      final authToken = (resp['authorizationToken'] ?? '').toString();
      final downloadUrl = (resp['downloadUrl'] ?? '').toString();
      final edgeBucketName = (resp['bucketName'] ?? bucketName).toString();

      if (authToken.isEmpty || downloadUrl.isEmpty) {
        throw Exception('Failed to obtain secure download token');
      }
      final encodedPath = Uri.encodeComponent(objectPath);
      final photoUrl = '$downloadUrl/file/$edgeBucketName/$encodedPath?Authorization=$authToken';
      final expiresAt = now.add(const Duration(minutes: 30));  // Cache for 30 minutes

      // ✅ Step 4: Cache URL in both memory and database (30 minutes validity)
      _memoryCache[objectPath] = _CachedUrl(
        url: photoUrl,
        expiresAt: expiresAt,
      );

      // Store in database for sharing across all users/devices
      try {
        // Delete old entry first to avoid unique constraint violations
        try {
          await appDb
              .from('cached_photo_urls')
              .delete()
              .eq('object_path', objectPath);
        } catch (_) {
          // OK if delete fails (record might not exist)
        }

        // Now insert fresh
        await appDb.from('cached_photo_urls').insert({
          'object_path': objectPath,
          'photo_url': photoUrl,
          'authorization_token': authToken,
          'expires_at': expiresAt.toIso8601String(),
        });
        if (kDebugMode) debugPrint('✅ Cached URL in database for $objectPath');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Failed to save to database cache: $e');
        // Continue anyway - database caching is optional optimization
      }

      return photoUrl;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ getPhotoUrl failed: $e');
      rethrow;
    }
  }

  /// Clear all cached URLs (memory + database)
  static Future<void> clearUrlCache() async {
    _memoryCache.clear();
    try {
      await appDb.from('cached_photo_urls').delete().not('id', 'is', null);
      if (kDebugMode) debugPrint('🧹 Cleared all URL caches (memory + database)');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error clearing database cache: $e');
    }
  }

  /// Clear database cache only (for administrative purposes)
  static Future<void> clearDatabaseCache() async {
    try {
      await appDb.from('cached_photo_urls').delete().not('id', 'is', null);
      if (kDebugMode) debugPrint('🧹 Cleared database URL cache');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error clearing database cache: $e');
    }
  }

  @Deprecated('Use getPhotoUrl() which generates temporary signed URLs')
  static Future<String> getAuthorizationToken() async {
    throw UnsupportedError('Direct B2 authorization token is no longer exposed to client');
  }

  static Future<void> _purgeTeacherAttendancePhotoPayloadsInDb(String? instituteId) async {
    String? lastId;
    while (true) {
      dynamic q = appDb.from('teacher_attendance').select('id,payload').order('id').limit(200);
      if (instituteId != null && instituteId.isNotEmpty) {
        q = q.eq('institute_id', instituteId);
      }
      if (lastId != null && lastId.isNotEmpty) {
        q = q.gt('id', lastId);
      }
      final resp = await q;
      final rows = (resp as List<dynamic>);
      if (rows.isEmpty) break;

      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final payloadRaw = row['payload'];
        final payload = <String, dynamic>{};
        if (payloadRaw is Map) {
          for (final e in payloadRaw.entries) {
            payload[e.key.toString()] = e.value;
          }
        }
        final stripped = stripTeacherAttendancePayloadPhotos(payload);
        await appDb.from('teacher_attendance').update({
          'payload': stripped,
          'verification_selfie': null,
        }).eq('id', id);
      }

      final lastRow = Map<String, dynamic>.from(rows.last as Map);
      lastId = lastRow['id']?.toString();
      if (rows.length < 200) break;
    }
    if (kDebugMode) debugPrint('✅ Stripped photo fields from teacher_attendance payloads');
  }

  static Future<void> _purgeAttendanceInOutPhotosInDb(String? instituteId) async {
    String? code;
    if (instituteId != null && instituteId.isNotEmpty) {
      code = await instituteCodeForId(instituteId);
    }

    String? lastId;
    while (true) {
      dynamic q = appDb.from('attendance_in_out').select('id,additional').order('id').limit(250);
      if (code != null && code.isNotEmpty) {
        q = q.eq('institute_code', code);
      }
      if (lastId != null && lastId.isNotEmpty) {
        q = q.gt('id', lastId);
      }
      final resp = await q;
      final rows = (resp as List<dynamic>);
      if (rows.isEmpty) break;

      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final add = _stripAttendanceAdditional(row['additional']);
        final patch = <String, dynamic>{
          'photo_url': null,
          'photo_path': null,
          'photo_file_id': null,
        };
        if (add != null) patch['additional'] = add;
        await appDb.from('attendance_in_out').update(patch).eq('id', id);
      }

      final lastRow = Map<String, dynamic>.from(rows.last as Map);
      lastId = lastRow['id']?.toString();
      if (rows.length < 250) break;
    }
    if (kDebugMode) debugPrint('✅ Cleared attendance_in_out photo columns + JSON extras');
  }

  /// ⚠️ DANGER: Deletes ALL B2 bucket files (via Edge Function), strips ALL photo references from
  /// Postgres (`students`, `teacher_attendance`, `attendance_in_out`), clears signed-URL caches,
  /// and clears local image caches on this device.
  ///
  /// When [instituteId] is set, only rows for that institute are updated in the DB; **B2 purge is still global**
  /// (the Edge Function deletes the entire bucket).
  static Future<void> clearAllB2Storage({String? instituteId}) async {
    try {
      if (kDebugMode) {
        debugPrint(
          '🗑️ PHOTO PURGE: B2 bucket + DB references + URL caches + device image cache '
          '${instituteId != null ? "(institute $instituteId DB scope)" : "(ALL institutes DB scope)"}',
        );
      }

      _memoryCache.clear();

      await clearUrlCache();

      await _purgeTeacherAttendancePhotoPayloadsInDb(instituteId);
      await _purgeAttendanceInOutPhotosInDb(instituteId);

      final studentPatch = <String, dynamic>{
        'face_photo_url': null,
        'photo_url': null,
        'registration_photo_path': null,
        'face_embedding': null,
      };

      if (instituteId != null && instituteId.isNotEmpty) {
        await appDb.from('students').update(studentPatch).eq('institute_id', instituteId);
      } else {
        await appDb.from('students').update(studentPatch).not('id', 'is', null);
      }
      if (kDebugMode) debugPrint('✅ Cleared student registration / face photo columns');

      try {
        final funcResult = await appDb.functions.invoke('clear-b2-storage');
        if (kDebugMode) {
          debugPrint('✅ clear-b2-storage Edge Function: $funcResult');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ clear-b2-storage Edge Function error: $e');
      }

      try {
        await DefaultCacheManager().emptyCache();
        if (kDebugMode) debugPrint('✅ Cleared DefaultCacheManager disk cache');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ DefaultCacheManager emptyCache: $e');
      }

      try {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        if (kDebugMode) debugPrint('✅ Cleared Flutter in-memory ImageCache');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ ImageCache clear: $e');
      }

      if (kDebugMode) debugPrint('✅✅✅ Photo purge finished ✅✅✅');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Photo purge failed: $e');
      rethrow;
    }
  }
}

/// Cached URL with expiration time
class _CachedUrl {
  final String url;
  final DateTime expiresAt;

  _CachedUrl({
    required this.url,
    required this.expiresAt,
  });
}
