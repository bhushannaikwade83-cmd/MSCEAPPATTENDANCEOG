import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import '../core/gps_attendance_constants.dart';
import 'gps_fence_sample.dart';

/// Geofence / GPS settings (Supabase `gps_settings` + `institute_geofence`).
class GeofenceService {
  SupabaseClient get _db => appDb;

  Stream<List<Map<String, dynamic>>> getLockedGeofences() {
    late StreamController<List<Map<String, dynamic>>> controller;
    Timer? timer;

    Future<List<Map<String, dynamic>>> load() async {
      final rows = await _db.from('gps_settings').select().eq('is_locked', true);
      return rows
          .map(
            (r) => {
              'instituteId': r['institute_id'],
              'adminId': r['admin_id'],
              'latitude': r['latitude'],
              'longitude': r['longitude'],
              'radius': r['radius'],
            },
          )
          .toList();
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () async {
        controller.add(await load());
        timer = Timer.periodic(const Duration(seconds: 4), (_) async {
          if (!controller.isClosed) {
            controller.add(await load());
          }
        });
      },
      onCancel: () => timer?.cancel(),
    );

    return controller.stream;
  }

  Stream<List<Map<String, dynamic>>> getLockedGeofencesByInstitute(String instituteId) {
    return getLockedGeofences().map(
      (list) => list.where((e) => e['instituteId'] == instituteId).toList(),
    );
  }

  Future<Map<String, dynamic>> unlockGeofence({
    required String instituteId,
    required String adminId,
  }) async {
    try {
      final currentUser = _db.auth.currentUser;
      if (currentUser == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final row = await _db
          .from('gps_settings')
          .select()
          .eq('institute_id', instituteId)
          .eq('admin_id', adminId)
          .maybeSingle();

      if (row == null) {
        return {'success': false, 'message': 'Geofence not found'};
      }

      if (row['is_locked'] != true) {
        return {'success': false, 'message': 'Geofence is not locked'};
      }

      final double radius = kAttendanceFenceRadiusMeters;
      final latitude = (row['latitude'] as num?)?.toDouble();
      final longitude = (row['longitude'] as num?)?.toDouble();

      if (latitude != null && longitude != null) {
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );

          if (position.isMocked) {
            return {
              'success': false,
              'message': 'Cannot unlock: Fake GPS detected. Please turn off Mock Location apps.',
            };
          }

          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            latitude,
            longitude,
          );

          if (distance <= radius) {
            return {
              'success': false,
              'message':
                  'Cannot unlock: Admin is within ${radius.toStringAsFixed(0)}m of the locked location.',
            };
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Error checking location for unlock: $e');
        }
      }

      await _db.from('gps_settings').update({
        'is_locked': false,
        'unlocked_at': DateTime.now().toUtc().toIso8601String(),
        'unlocked_by': currentUser.id,
        'unlocked_by_email': currentUser.email ?? 'Unknown',
      }).eq('institute_id', instituteId).eq('admin_id', adminId);

      return {'success': true, 'message': 'Geofence unlocked successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error unlocking geofence: $e');
      return {'success': false, 'message': 'Error unlocking geofence: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> lockGeofence({
    required String instituteId,
    required String adminId,
  }) async {
    try {
      final currentUser = _db.auth.currentUser;
      if (currentUser == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      await _db.from('gps_settings').update({
        'is_locked': true,
        'locked_at': DateTime.now().toUtc().toIso8601String(),
        'locked_by': currentUser.id,
      }).eq('institute_id', instituteId).eq('admin_id', adminId);

      return {'success': true, 'message': 'Geofence locked successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error locking geofence: $e');
      return {'success': false, 'message': 'Error locking geofence: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>?> getGeofenceDetails({
    required String instituteId,
    required String adminId,
  }) async {
    try {
      final row = await _db
          .from('gps_settings')
          .select()
          .eq('institute_id', instituteId)
          .eq('admin_id', adminId)
          .maybeSingle();
      if (row == null) return null;
      return {
        'isLocked': row['is_locked'],
        'latitude': row['latitude'],
        'longitude': row['longitude'],
        'radius': row['radius'],
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting geofence details: $e');
      return null;
    }
  }

  Future<bool> isGeofenceLocked({
    required String instituteId,
    required String adminId,
  }) async {
    try {
      final details = await getGeofenceDetails(
        instituteId: instituteId,
        adminId: adminId,
      );
      return details?['isLocked'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchProfileForLocationGate(String userId) async {
    try {
      return await _db
          .from('profiles')
          .select('institute_id, role')
          .eq('id', userId)
          .maybeSingle();
    } catch (e) {
      if (kDebugMode) debugPrint('fetchProfileForLocationGate: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> checkAdminLocationStatus({
    required String instituteId,
    required String adminId,
    bool fastFenceSampleForLogin = false,
  }) async {
    try {
      final details = await getGeofenceDetails(
        instituteId: instituteId,
        adminId: adminId,
      );

      if (details == null) {
        return {
          'isLocked': false,
          'hasLocation': false,
          'isWithinRadius': null,
          'distance': null,
          'message': 'Location not configured',
        };
      }

      final isLocked = details['isLocked'] == true;
      final latitude = (details['latitude'] as num?)?.toDouble();
      final longitude = (details['longitude'] as num?)?.toDouble();

      final double radius = kAttendanceFenceRadiusMeters;

      final hasLocation = latitude != null &&
          longitude != null &&
          latitude != 0.0 &&
          longitude != 0.0;

      if (!hasLocation) {
        return {
          'isLocked': false,
          'hasLocation': false,
          'isWithinRadius': null,
          'distance': null,
          'message': 'Location not set',
        };
      }

      try {
        final sample = await samplePositionAgainstFence(
          fenceLat: latitude,
          fenceLng: longitude,
          radiusMeters: radius,
          maxSamples: fastFenceSampleForLogin ? 4 : 7,
          delayBetweenSamples: fastFenceSampleForLogin
              ? const Duration(milliseconds: 500)
              : const Duration(milliseconds: 1200),
          firstSampleTimeoutSeconds: fastFenceSampleForLogin ? 10 : 16,
          laterSampleTimeoutSeconds: fastFenceSampleForLogin ? 8 : 12,
          tryRecentLastKnownFirst: fastFenceSampleForLogin,
        );

        if (sample.mockedDetected) {
          return {
            'isLocked': isLocked,
            'hasLocation': true,
            'isWithinRadius': false,
            'distance': null,
            'message': isLocked ? 'Location locked - Fake GPS detected' : 'Location unlocked - Fake GPS detected',
          };
        }

        if (sample.errorMessage != null) {
          return {
            'isLocked': isLocked,
            'hasLocation': true,
            'isWithinRadius': null,
            'distance': null,
            'message': sample.errorMessage,
          };
        }

        final isWithinRadius = sample.isWithinFence;
        final distance = sample.bestDistanceMeters;

        return {
          'isLocked': isLocked,
          'hasLocation': true,
          'isWithinRadius': isWithinRadius,
          'distance': distance,
          'message': isWithinRadius ? 'Within radius' : 'Outside radius',
        };
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Error checking current location: $e');
        return {
          'isLocked': isLocked,
          'hasLocation': true,
          'isWithinRadius': null,
          'distance': null,
          'message': 'Unable to verify current location',
        };
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking admin location status: $e');
      return {
        'isLocked': false,
        'hasLocation': false,
        'isWithinRadius': null,
        'distance': null,
        'message': 'Error checking location status',
      };
    }
  }

  /// Locked [gps_settings] rows with valid coordinates, newest [locked_at] first.
  ///
  /// [gps_settings.institute_id] may be either [institutes.id] (UUID) or the
  /// numeric [institute_code] (e.g. `"99099"`). Instructor login types the code;
  /// we load institute row and query fences for every matching key (same idea as
  /// [AuthService.signInAttendanceStaff]).
  Future<List<Map<String, dynamic>>> _sortedLockedFenceRowsWithCoords(
    String instituteId,
  ) async {
    final raw = instituteId.trim();
    if (raw.isEmpty) return [];

    final keys = <String>{raw};
    try {
      final inst = await _db
          .from('institutes')
          .select('id, institute_code')
          .or('id.eq.$raw,institute_code.eq.$raw')
          .maybeSingle();
      final id = inst?['id']?.toString().trim();
      final code = inst?['institute_code']?.toString().trim();
      if (id != null && id.isNotEmpty) keys.add(id);
      if (code != null && code.isNotEmpty) keys.add(code);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ institute resolve for fence: $e');
    }

    int lockedRank(Map<String, dynamic> m) {
      final ts = m['locked_at'];
      if (ts == null) return 0;
      final t = DateTime.tryParse(ts.toString());
      return t?.millisecondsSinceEpoch ?? 0;
    }

    Future<List<Map<String, dynamic>>> fetchForKey(String id) async {
      final rows = await _db
          .from('gps_settings')
          .select('admin_id, latitude, longitude, locked_at')
          .eq('institute_id', id)
          .eq('is_locked', true);

      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((map) {
            final lat = (map['latitude'] as num?)?.toDouble();
            final lng = (map['longitude'] as num?)?.toDouble();
            return lat != null &&
                lng != null &&
                (lat.abs() > 1e-9 || lng.abs() > 1e-9);
          })
          .toList();
    }

    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final k in keys) {
      for (final row in await fetchForKey(k)) {
        final sig =
            '${row['admin_id']}|${row['latitude']}|${row['longitude']}|${row['locked_at']}';
        if (seen.add(sig)) merged.add(row);
      }
    }

    merged.sort((a, b) => lockedRank(b).compareTo(lockedRank(a)));
    return merged;
  }

  List<Map<String, dynamic>> _rowsFromRpcResult(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is Map) {
      return [Map<String, dynamic>.from(raw)];
    }
    return [];
  }

  /// Locked fence for PIN login: callable while **anon** (pre-auth). Uses Supabase RPC
  /// `get_locked_fence_for_pin_login`; falls back to direct [gps_settings] read when
  /// authenticated/RPC unavailable.
  Future<({double latitude, double longitude, String? adminId})?> _getLockedFenceForPinLogin(
    String instituteKey,
  ) async {
    final k = instituteKey.trim();
    if (k.isEmpty) return null;

    try {
      final raw = await _db.rpc(
        'get_locked_fence_for_pin_login',
        params: {'p_institute_key': k},
      );
      final rows = _rowsFromRpcResult(raw);
      if (rows.isNotEmpty) {
        final m = rows.first;
        final lat = (m['latitude'] as num?)?.toDouble();
        final lng = (m['longitude'] as num?)?.toDouble();
        final aid = m['admin_id']?.toString();
        if (lat != null && lng != null) {
          final adminId = (aid == null || aid.isEmpty) ? null : aid;
          return (latitude: lat, longitude: lng, adminId: adminId);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('get_locked_fence_for_pin_login RPC (will try direct query): $e');
      }
    }

    try {
      final list = await _sortedLockedFenceRowsWithCoords(k);
      if (list.isEmpty) return null;
      final m = list.first;
      final lat = (m['latitude'] as num?)?.toDouble();
      final lng = (m['longitude'] as num?)?.toDouble();
      final aid = m['admin_id']?.toString();
      if (lat == null || lng == null) return null;
      return (
        latitude: lat,
        longitude: lng,
        adminId: (aid == null || aid.isEmpty) ? null : aid,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ _getLockedFenceForPinLogin direct query: $e');
      return null;
    }
  }

  /// Locked [gps_settings] row admin for this institute (most recently locked first).
  Future<String?> lockedFenceAdminIdForInstitute(String instituteId) async {
    try {
      final fence = await _getLockedFenceForPinLogin(instituteId);
      return fence?.adminId;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ lockedFenceAdminIdForInstitute: $e');
      return null;
    }
  }

  /// Canonical lat/lng for pre-auth PIN login checks — same locked point as attendance staff.
  Future<({double latitude, double longitude})?> lockedFenceLatLngForInstitute(
    String instituteId,
  ) async {
    try {
      final fence = await _getLockedFenceForPinLogin(instituteId);
      if (fence == null) return null;
      return (latitude: fence.latitude, longitude: fence.longitude);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ lockedFenceLatLngForInstitute: $e');
      return null;
    }
  }

  /// [admin] and [attendance_user] must be inside the institute’s locked fence; staff uses the admin’s institute GPS row.
  /// Skipped on web. Other roles bypass.
  Future<Map<String, dynamic>> attendanceLocationGateForCurrentUser({
    Map<String, dynamic>? preloadedProfile,
    bool fastFenceSampleForLogin = false,
  }) async {
    if (kIsWeb) return {'allowed': true};

    final user = _db.auth.currentUser;
    if (user == null) return {'allowed': true};

    Map<String, dynamic> deny({required String message, double? distance}) =>
        {'allowed': false, 'message': message, 'distance': distance};

    try {
      final profile = preloadedProfile ??
          await _db
              .from('profiles')
              .select('institute_id, role')
              .eq('id', user.id)
              .maybeSingle();

      if (profile == null) return deny(message: 'Profile not found.');
      final role = (profile['role'] ?? '').toString().trim().toLowerCase();
      final instituteId = profile['institute_id']?.toString().trim();

      if (instituteId == null || instituteId.isEmpty) {
        return deny(message: 'No institute linked to this account.');
      }

      final isAdmin = role == 'admin';
      final isInstructor = role == 'attendance_user';
      if (!isAdmin && !isInstructor) return {'allowed': true};

      late final String fenceAdminId;
      if (isAdmin) {
        fenceAdminId = user.id;
      } else {
        final fid = await lockedFenceAdminIdForInstitute(instituteId);
        if (fid == null || fid.isEmpty) {
          return deny(message: 'Institute attendance GPS is not locked yet. Ask your admin to complete GPS Settings.');
        }
        fenceAdminId = fid;
      }

      final status = await checkAdminLocationStatus(
        instituteId: instituteId,
        adminId: fenceAdminId,
        fastFenceSampleForLogin: fastFenceSampleForLogin,
      );

      final isLocked = status['isLocked'] == true;
      final hasLocation = status['hasLocation'] == true;
      final within = status['isWithinRadius'] as bool?;
      final distance = status['distance'] as double?;

      if (!hasLocation || !isLocked) {
        // Return consistent error message when GPS is not locked
        final errorMsg = !isLocked
          ? 'Institute attendance GPS is not locked yet. Ask your admin to complete GPS Settings.'
          : '${status['message'] ?? 'Attendance zone unavailable'}. Ask your institute admin.';
        return deny(message: errorMsg, distance: distance);
      }

      if (within == true) return {'allowed': true, 'distance': distance};

      final rLabel = kAttendanceMaxEffectiveFenceMeters.toStringAsFixed(0);

      if (within == false && distance != null) {
        return deny(
          distance: distance,
          message:
              'Out of radius: you are about ${distance.toStringAsFixed(0)} m from the institute’s locked attendance point. '
              'Move within about $rLabel m (including GPS tolerance) or re-verify location in GPS Settings from your classroom. '
              'All features are blocked until you are inside the zone.'
              '\n\nआपण संस्थेच्या उपस्थिती क्षेत्राबाहेर आहात — GPS सेटिंग्जमधून वर्गातून स्थान पुन्हा तपासा.',
        );
      }

      final msg = status['message']?.toString();
      final detail = msg == null || msg.trim().isEmpty ? 'Unable to verify your location' : msg.trim();
      return deny(
        message:
            '$detail. Turn on GPS, allow location, and tap Check again when you are at the institute.'
            '\n\nजीपीएस सुरू करा आणि संस्थेत असताना पुन्हा तपासा.',
        distance: distance,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('attendanceLocationGateForCurrentUser: $e');
      return deny(message: 'Location check failed. Try again.');
    }
  }

  /// Check if user is within attendance radius when marking attendance.
  /// Returns: {'allowed': bool, 'message': String, 'distance': double}
  /// Checks actual GPS location distance (must be within 15m).
  Future<Map<String, dynamic>> checkAttendanceLocationForCurrentUser({
    Map<String, dynamic>? preloadedProfile,
  }) async {
    if (kIsWeb) return {'allowed': true};

    final user = _db.auth.currentUser;
    if (user == null) return {'allowed': false, 'message': 'Not authenticated'};

    try {
      final profile = preloadedProfile ??
          await _db
              .from('profiles')
              .select('institute_id, role')
              .eq('id', user.id)
              .maybeSingle();

      if (profile == null) {
        return {'allowed': false, 'message': 'Profile not found'};
      }

      final role = (profile['role'] ?? '').toString().trim().toLowerCase();
      final instituteId = profile['institute_id']?.toString().trim();

      if (instituteId == null || instituteId.isEmpty) {
        return {'allowed': false, 'message': 'No institute linked'};
      }

      final isAdmin = role == 'admin';
      final isInstructor = role == 'attendance_user';

      if (!isAdmin && !isInstructor) {
        return {'allowed': true}; // Non-staff roles not restricted
      }

      // Get the locked GPS point for this institute
      late final String fenceAdminId;
      if (isAdmin) {
        fenceAdminId = user.id;
      } else {
        final fid = await lockedFenceAdminIdForInstitute(instituteId);
        if (fid == null || fid.isEmpty) {
          return {
            'allowed': false,
            'message': 'Institute attendance GPS is not locked yet'
          };
        }
        fenceAdminId = fid;
      }

      // Get GPS settings
      final gpsSettings = await _db
          .from('gps_settings')
          .select('latitude, longitude, is_locked, radius')
          .eq('institute_id', instituteId)
          .eq('admin_id', fenceAdminId)
          .maybeSingle();

      if (gpsSettings == null) {
        return {'allowed': false, 'message': 'GPS settings not found'};
      }

      if (gpsSettings['is_locked'] != true) {
        return {
          'allowed': false,
          'message': 'Attendance zone not locked'
        };
      }

      final lockedLat = (gpsSettings['latitude'] as num?)?.toDouble();
      final lockedLng = (gpsSettings['longitude'] as num?)?.toDouble();

      if (lockedLat == null || lockedLng == null) {
        return {
          'allowed': false,
          'message': 'GPS coordinates missing'
        };
      }

      // Use the shared strict sampler so mock-GPS and weak-fix rules stay identical.
      try {
        final sample = await samplePositionAgainstFence(
          fenceLat: lockedLat,
          fenceLng: lockedLng,
          radiusMeters: kAttendanceFenceRadiusMeters,
          maxSamples: kAttendanceGpsFastMaxSamples,
          delayBetweenSamples:
              Duration(milliseconds: kAttendanceGpsFastDelayBetweenMs),
          firstSampleTimeoutSeconds: kAttendanceGpsFastFirstTimeoutSec,
          laterSampleTimeoutSeconds: kAttendanceGpsFastLaterTimeoutSec,
          preSampleStabilizationDelay:
              Duration(milliseconds: kAttendanceGpsFastStabilizationMs),
          tryRecentLastKnownFirst: kAttendanceGpsTryLastKnownFirst,
          lastKnownMaxAge:
              Duration(minutes: kAttendanceGpsLastKnownMaxAgeMinutes),
        );

        if (sample.mockedDetected) {
          return {
            'allowed': false,
            'message': 'Fake GPS detected. Please turn off Mock Location apps.',
          };
        }

        if (sample.errorMessage != null) {
          return {
            'allowed': false,
            'message': sample.errorMessage!,
          };
        }

        final distance = sample.bestDistanceMeters;

        if (sample.isWithinFence) {
          return {
            'allowed': true,
            'distance': distance,
          };
        } else {
          return {
            'allowed': false,
            'message':
                'You are about ${distance.toStringAsFixed(0)} m away from the institute. '
                'Move within about ${kAttendanceMaxEffectiveFenceMeters.toStringAsFixed(0)} m to mark attendance.',
            'distance': distance,
          };
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Error getting current position: $e');
        return {
          'allowed': false,
          'message': 'Cannot verify location. Ensure GPS is enabled: $e',
        };
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking attendance location: $e');
      return {
        'allowed': false,
        'message': 'Location check failed: $e',
      };
    }
  }

  /// Per-admin [gps_settings]: non-zero lat/lng and [is_locked] (same rule as post-login navigation).
  /// Non-admin roles always return true so teachers are not blocked.
  Future<bool> hasValidPersonalGpsForCurrentAdmin({
    Map<String, dynamic>? preloadedProfile,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) return true;

    try {
      final profile = preloadedProfile ??
          await _db
              .from('profiles')
              .select('institute_id, role')
              .eq('id', user.id)
              .maybeSingle();

      if (profile == null) return false;

      final role = profile['role'] as String?;
      final instituteId = profile['institute_id'] as String?;

      if (role == 'attendance_user') {
        if (instituteId == null || instituteId.isEmpty) return false;
        final fenceAdminId = await lockedFenceAdminIdForInstitute(instituteId);
        if (fenceAdminId == null || fenceAdminId.isEmpty) {
          if (kDebugMode) {
            debugPrint('🛰️ Attendance staff: institute has no valid locked GPS yet');
          }
          return false;
        }
        return true;
      }

      if (role != 'admin' || instituteId == null || instituteId.isEmpty) {
        return true;
      }

      final gpsSettings = await _db
          .from('gps_settings')
          .select('latitude, longitude, is_locked')
          .eq('institute_id', instituteId)
          .eq('admin_id', user.id)
          .maybeSingle();

      if (gpsSettings == null) {
        if (kDebugMode) debugPrint('🛰️ GPS settings not found for admin');
        return false;
      }

      if (gpsSettings['is_locked'] != true) {
        if (kDebugMode) debugPrint('🛰️ GPS not locked for admin');
        return false;
      }

      final lat = gpsSettings['latitude'];
      final lng = gpsSettings['longitude'];
      final hasValidCoordinates = lat != null &&
          lng != null &&
          lat.toString().isNotEmpty &&
          lng.toString().isNotEmpty &&
          (lat as num) != 0.0 &&
          (lng as num) != 0.0;

      if (kDebugMode) {
        if (hasValidCoordinates) {
          debugPrint('✅ GPS is configured and locked: $lat, $lng');
        } else {
          debugPrint('❌ GPS coordinates are missing or invalid');
        }
      }

      return hasValidCoordinates;
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking GPS configuration: $e');
      return false;
    }
  }

  /// Bumps legacy 25m / 30m rows to [kAttendanceFenceRadiusMeters].
  Future<Map<String, dynamic>> migrateRadiusTo30Meters() async {
    try {
      int updatedCount = 0;
      final target = kAttendanceFenceRadiusMeters;
      final institutes = await _db.from('institutes').select('id');
      for (final inst in institutes) {
        final iid = inst['id'] as String;
        final gpsRows = await _db.from('gps_settings').select().eq('institute_id', iid);
        for (final g in gpsRows) {
          final r = (g['radius'] as num?)?.toDouble() ?? 0.0;
          if ((r >= 24.9 && r <= 25.1) || (r >= 29.0 && r <= 31.0)) {
            await _db
                .from('gps_settings')
                .update({
                  'radius': target,
                  'extra': {
                    'radiusMigratedFrom': r,
                    'radiusMigratedAt': DateTime.now().toUtc().toIso8601String(),
                  },
                })
                .eq('institute_id', iid)
                .eq('admin_id', g['admin_id']);
            updatedCount++;
          }
        }
        final gf = await _db.from('institute_geofence').select().eq('institute_id', iid).maybeSingle();
        if (gf != null) {
          final data = gf['data'];
          final r = data is Map && data['radius'] != null
              ? (data['radius'] as num).toDouble()
              : (gf['radius'] as num?)?.toDouble() ?? 0;
          if ((r >= 24.9 && r <= 25.1) || (r >= 29.0 && r <= 31.0)) {
            await _db.from('institute_geofence').update({'radius': target}).eq('institute_id', iid);
            updatedCount++;
          }
        }
      }

      final global = await _db.from('system_settings').select().eq('key', 'gps_config').maybeSingle();
      if (global != null) {
        final val = global['value'];
        if (val is Map && val['radius'] != null) {
          final r = (val['radius'] as num).toDouble();
          if ((r >= 24.9 && r <= 25.1) || (r >= 29.0 && r <= 31.0)) {
            await _db.from('system_settings').upsert({
              'key': 'gps_config',
              'value': {...val, 'radius': target},
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
            updatedCount++;
          }
        }
      }

      return {
        'success': true,
        'updatedCount': updatedCount,
        'errorCount': 0,
        'message': 'Migration completed: Updated $updatedCount settings to ${target.toStringAsFixed(0)} meters.',
        'errors': <String>[],
      };
    } catch (e) {
      return {
        'success': false,
        'updatedCount': 0,
        'errorCount': 0,
        'message': 'Error during migration: ${e.toString()}',
        'errors': [e.toString()],
      };
    }
  }
}
