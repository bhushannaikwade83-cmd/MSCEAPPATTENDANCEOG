import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../config/b2b_storage_config.dart';
import 'b2b_storage_service.dart';

/// Storage Service for organizing attendance photos
/// Uses B2B Storage (Backblaze B2) for file storage
/// 
/// Folder Structure:
///   institute_id/
///     folder_year/
///       rollNumber/
///         subject/
///           YYYY-MM-DD/
///             photo.jpg
class StorageService {
  /// Generate storage path for attendance photo
  /// 
  /// Structure: institute_id/folder_year/srNo/subject/YYYY-MM-DD/photo.jpg
  static String generatePhotoPath({
    required String instituteId,
    required String folderYear,
    required String srNo,
    required String subject,
    required String date, // Format: YYYY-MM-DD
  }) {
    return B2BStorageService.generatePhotoPath(
      instituteId: instituteId,
      folderYear: folderYear,
      rollNumber: srNo,
      subject: subject,
      date: date,
    );
  }

  /// Upload attendance photo to B2B Storage
  /// 
  /// Returns the file URL and storage path
  /// photoType: 'entry' or 'exit' (optional, defaults to 'entry' for backward compatibility)
  static Future<Map<String, String>> uploadAttendancePhoto({
    required String instituteId,
    required String folderYear,
    required String srNo,
    required String subject,
    required String date,
    required List<int> photoBytes,
    String? photoType, // 'entry' or 'exit'
  }) async {
    try {
      final result = await B2BStorageService.uploadAttendancePhoto(
        instituteId: instituteId,
        folderYear: folderYear,
        rollNumber: srNo,
        subject: subject,
        date: date,
        photoBytes: photoBytes,
        photoType: photoType,
      );

      return {
        'url': result['url']!,
        'path': result['path']!,
        if (result['fileId'] != null) 'fileId': result['fileId']!,
      };
    } catch (e) {
      throw Exception('Failed to upload photo: $e');
    }
  }

  /// Delete attendance photo from B2B Storage
  static Future<void> deleteAttendancePhoto(String objectPath, {String? fileId}) async {
    try {
      await B2BStorageService.deleteAttendancePhoto(objectPath, fileId: fileId);
    } catch (e) {
      throw Exception('Failed to delete photo: $e');
    }
  }

  /// Delete photo by path or URL and optional fileId (preferred).
  static Future<void> deletePhotoReference(String pathOrUrl, {String? fileId}) async {
    final raw = pathOrUrl.trim();
    if (raw.isEmpty) return;
    final objectPath = raw.startsWith('http') ? (b2ObjectPathFromPhotoUrl(raw) ?? '') : raw;
    if (objectPath.isEmpty) return;
    await deleteAttendancePhoto(objectPath, fileId: fileId);
  }

  /// Get photo URL from object path
  /// Always returns a signed URL (valid for 30 minutes)
  /// Automatically retries with fresh authorization if needed
  static Future<String> getPhotoUrl(String objectPath) async {
    try {
      return await B2BStorageService.getPhotoUrl(objectPath);
    } catch (e) {
      // Retry once with fresh authorization
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        return await B2BStorageService.getPhotoUrl(objectPath);
      } catch (retryError) {
        rethrow; // Re-throw if retry also fails
      }
    }
  }

  /// Extract B2 object key from a friendly file URL (path is `/file/{bucket}/{key}`; key may be URI-encoded).
  static String? b2ObjectPathFromPhotoUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return null;
    final lower = u.toLowerCase();
    if (!lower.contains('backblazeb2.com')) return null;
    try {
      final uri = Uri.parse(u);
      final p = uri.path;
      const marker = '/file/';
      final idx = p.indexOf(marker);
      if (idx < 0) return null;
      final after = p.substring(idx + marker.length);
      final slash = after.indexOf('/');
      if (slash < 0 || slash >= after.length - 1) return null;
      final encodedObject = after.substring(slash + 1);
      if (encodedObject.isEmpty) return null;
      return Uri.decodeComponent(encodedObject);
    } catch (e) {
      return null;
    }
  }

  /// Returns a **fresh** temporary signed URL for B2 objects whenever possible.
  /// Old logic kept expired `Authorization=` query params, which broke [CachedNetworkImage].
  static Future<String> ensureSignedUrl(String url) async {
    final u = url.trim();
    if (u.isEmpty) return u;

    final b2Path = b2ObjectPathFromPhotoUrl(u);
    if (b2Path != null && b2Path.isNotEmpty && B2BStorageConfig.isConfigured) {
      try {
        return await getPhotoUrl(b2Path);
      } catch (e) {
        if (kDebugMode) debugPrint('ensureSignedUrl(getPhotoUrl): $e');
        if (u.contains('backblazeb2.com')) {
          rethrow;
        }
      }
    }

    // Non-B2 or B2 without extractable path (e.g. wrong host shape): return as-is
    return u;
  }
  
  /// Get authorization token for private bucket access
  static Future<String> getAuthorizationToken() async {
    return await B2BStorageService.getAuthorizationToken();
  }

  /// Clear all cached photo URLs (memory + database)
  /// Use when signed URLs expire (401 errors) to force fresh generation
  static Future<void> clearUrlCache() async {
    await B2BStorageService.clearUrlCache();
  }

  /// Extract metadata from file path/ID
  static Map<String, String>? parsePhotoPath(String pathOrId) {
    try {
      // Handle both path format and file ID format
      final parts = pathOrId.contains('/') 
          ? pathOrId.split('/')
          : pathOrId.split('_');

      if (parts.length >= 5) {
        return {
          'instituteId': parts[0],
          'folderYear': parts[1],
          'rollNumber': parts[2],
          'subject': parts[3].replaceAll('_', ' '),
          'date': parts[4],
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Automatically convert photo data to temporary signed URL
  ///
  /// This method handles all cases:
  /// - If storagePath is provided, generates URL from it
  /// - If photoUrl is provided but not signed, signs it
  /// - If photoUrl is already signed, returns as-is
  /// - If photoUrl is a storage path (not starting with http), converts it
  ///
  /// Use this method to automatically get temporary URLs for all student photos
  static Future<String?> getTemporaryPhotoUrl({
    String? photoUrl,
    String? storagePath,
  }) async {
    try {
      // Priority 1: Use storagePath if available (most reliable)
      if (storagePath != null && storagePath.isNotEmpty) {
        return await getPhotoUrl(storagePath);
      }

      // Priority 2: Process photoUrl
      if (photoUrl != null && photoUrl.isNotEmpty) {
        final p = photoUrl.trim();
        // Raw object path stored in DB (no scheme)
        if (!p.startsWith('http')) {
          return await getPhotoUrl(p);
        }

        // B2: always mint a new temp URL from object path when possible
        final fromUrl = b2ObjectPathFromPhotoUrl(p);
        if (fromUrl != null && fromUrl.isNotEmpty && B2BStorageConfig.isConfigured) {
          return await getPhotoUrl(fromUrl);
        }

        return await ensureSignedUrl(p);
      }

      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ getTemporaryPhotoUrl exception: $e');
      return null;
    }
  }

  /// Convert multiple photos to temporary URLs (parallel)
  /// Useful for displaying multiple student photos at once
  static Future<List<Map<String, dynamic>>> convertPhotosToTemporaryUrls(
    List<Map<String, dynamic>> photos,
  ) async {
    final results = await Future.wait(
      photos.map((photo) async {
        final photoUrl = photo['photoUrl'] as String?;
        final storagePath = photo['storagePath'] as String?;
        
        try {
          final temporaryUrl = await getTemporaryPhotoUrl(
            photoUrl: photoUrl,
            storagePath: storagePath,
          );
          
          return {
            ...photo,
            'photoUrl': temporaryUrl ?? '',
            'hasValidUrl': temporaryUrl != null && temporaryUrl.isNotEmpty,
          };
        } catch (e) {
          return {
            ...photo,
            'photoUrl': '',
            'hasValidUrl': false,
            'error': e.toString(),
          };
        }
      }),
    );
    
    return results;
  }
}
