import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/gps_attendance_constants.dart';
import 'geofence_service.dart';

/// Manages PIN login sessions with GPS radius security (nominal [kAttendanceFenceRadiusMeters]
/// plus capped accuracy slack — see [pinLoginEffectiveFenceRadiusMeters]).
class PinSessionManager {
  static const String _prefPinSessionInstituteId = 'msce_pin_session_institute_id';
  static const String _prefPinSessionUserName = 'msce_pin_session_user_name';
  static const String _prefPinSessionUserData = 'msce_pin_session_user_data';
  static const String _prefPinSessionTimestamp = 'msce_pin_session_timestamp';
  static const String _prefPinSessionGpsLat = 'msce_pin_session_gps_latitude';
  static const String _prefPinSessionGpsLng = 'msce_pin_session_gps_longitude';
  static const String _prefLastStaffInstituteCode = 'msce_last_staff_institute_code';

  /// Nominal fence radius (meters); PIN login also adds [Position.accuracy]-based slack.
  static const double radiusMeters = kPinLoginNominalFenceRadiusMeters;

  /// Check if PIN session exists and hasn't expired (not past midnight)
  static Future<bool> hasActivePinSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final instituteId = prefs.getString(_prefPinSessionInstituteId);

      if (instituteId == null || instituteId.isEmpty) {
        return false;
      }

      // Check if session hasn't expired (past midnight)
      return await isSessionValidAndNotExpired();
    } catch (_) {
      return false;
    }
  }

  /// Check if PIN session is still valid (not past midnight)
  /// Session is valid until 11:59:59 PM of login day
  /// At 12:00:00 AM (next day), session automatically expires
  static Future<bool> isSessionValidAndNotExpired() async {
    try {
      final session = await restorePinSession();
      if (session == null) return false;

      // Get login time from session userData
      final userData = session['userData'] as Map<String, dynamic>?;
      final loginTimeStr = userData?['loginTime'] as String?;

      if (loginTimeStr == null) {
        // Old session without loginTime, treat as expired
        if (kDebugMode) debugPrint('⚠️ PIN Session: No loginTime stored, treating as expired');
        return false;
      }

      try {
        final loginTime = DateTime.parse(loginTimeStr);
        final now = DateTime.now();

        // Get midnight of next day (00:00:00 AM)
        final loginDate = DateTime(loginTime.year, loginTime.month, loginTime.day);
        final midnightNextDay = loginDate.add(const Duration(days: 1));

        // If current time is past midnight (new day), session expired
        if (now.isAfter(midnightNextDay)) {
          if (kDebugMode) {
            debugPrint('❌ PIN Session EXPIRED: Logged in ${loginTime.toString()}, '
                       'now ${now.toString()}, midnight was ${midnightNextDay.toString()}');
          }
          return false;
        }

        // Session still valid - same day before midnight
        if (kDebugMode) {
          final timeUntilMidnight = midnightNextDay.difference(now);
          debugPrint('✅ PIN Session VALID: ${timeUntilMidnight.inHours}h ${timeUntilMidnight.inMinutes % 60}m until midnight');
        }
        return true;
      } catch (e) {
        if (kDebugMode) debugPrint('Error parsing loginTime: $e');
        return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking session validity: $e');
      return false;
    }
  }

  /// Instructor PIN login stores [canonicalInstituteId] in session userData.
  static bool isAttendanceStaffSessionData(Map<String, dynamic>? userData) {
    if (userData == null) return false;
    final canon = userData['canonicalInstituteId']?.toString().trim() ?? '';
    return canon.isNotEmpty;
  }

  /// Restore PIN session from storage
  static Future<Map<String, dynamic>?> restorePinSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final instituteId = prefs.getString(_prefPinSessionInstituteId);
      final userName = prefs.getString(_prefPinSessionUserName);
      final userDataJson = prefs.getString(_prefPinSessionUserData);
      final timestamp = prefs.getInt(_prefPinSessionTimestamp);

      if (instituteId == null || userName == null || userDataJson == null) {
        return null;
      }

      try {
        final userData = jsonDecode(userDataJson) as Map<String, dynamic>;
        return {
          'instituteId': instituteId,
          'userName': userName,
          'userData': userData,
          'timestamp': timestamp ?? 0,
        };
      } catch (e) {
        if (kDebugMode) debugPrint('Error parsing PIN session data: $e');
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Save PIN session to storage (with cached GPS coordinates from first login)
  static Future<void> savePinSession({
    required String instituteId,
    required String userName,
    required Map<String, dynamic> userData,
    double? gpsLatitude,
    double? gpsLongitude,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final saveFutures = [
        prefs.setString(_prefPinSessionInstituteId, instituteId.trim()),
        prefs.setString(_prefPinSessionUserName, userName.trim()),
        prefs.setString(_prefPinSessionUserData, jsonEncode(userData)),
        prefs.setInt(_prefPinSessionTimestamp, DateTime.now().millisecondsSinceEpoch),
        prefs.setString(_prefLastStaffInstituteCode, instituteId.trim()),
      ];

      // Save GPS coordinates if provided (from first login)
      if (gpsLatitude != null && gpsLongitude != null) {
        saveFutures.add(prefs.setDouble(_prefPinSessionGpsLat, gpsLatitude));
        saveFutures.add(prefs.setDouble(_prefPinSessionGpsLng, gpsLongitude));
      }

      await Future.wait(saveFutures);

      if (kDebugMode) {
        debugPrint('💾 PIN Session Saved: Institute=$instituteId, '
                   'GPS=${gpsLatitude != null ? '($gpsLatitude, $gpsLongitude)' : 'Not cached'}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error saving PIN session: $e');
    }
  }

  /// Clear PIN session (including cached GPS coordinates)
  static Future<void> clearPinSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(_prefPinSessionInstituteId),
        prefs.remove(_prefPinSessionUserName),
        prefs.remove(_prefPinSessionUserData),
        prefs.remove(_prefPinSessionTimestamp),
        prefs.remove(_prefPinSessionGpsLat),
        prefs.remove(_prefPinSessionGpsLng),
      ]);
      if (kDebugMode) debugPrint('🗑️ PIN Session Cleared');
    } catch (e) {
      if (kDebugMode) debugPrint('Error clearing PIN session: $e');
    }
  }

  /// Get saved institute ID (for read-only display)
  static Future<String?> getLastStaffInstituteCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefLastStaffInstituteCode);
    } catch (_) {
      return null;
    }
  }

  /// Verify user is within the PIN-login geofence (nominal [radiusMeters] + GPS accuracy slack).
  /// Uses cached GPS coordinates from first login (no DB query on repeat logins).
  /// **STRICT MODE**: Always requires GPS check — mandatory, no timeout fallbacks for position.
  static Future<({bool isWithinRadius, double? distanceMeters, String? error})>
    verifyLocationRadius({
    required String instituteId,
    double? cachedLatitude,
    double? cachedLongitude,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔒 PIN LOGIN: GPS radius verification (nominal ${radiusMeters}m + accuracy slack)...');
      }

      // Get current location - MUST SUCCEED, no timeout fallback
      if (kDebugMode) {
        debugPrint('📍 Requesting GPS position with HIGH accuracy (timeout: 15 seconds)...');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('GPS location acquisition timed out after 15 seconds');
        },
      );

      if (kDebugMode) {
        debugPrint('✅ GPS position acquired: Lat=${position.latitude.toStringAsFixed(6)}, Lng=${position.longitude.toStringAsFixed(6)}, Accuracy=±${position.accuracy.toStringAsFixed(1)}m');
      }

      if (position.isMocked) {
        if (kDebugMode) {
          debugPrint('❌ PIN LOGIN DENIED: mocked GPS position reported by Android');
        }
        return (
          isWithinRadius: false,
          distanceMeters: null,
          error:
              'Fake GPS detected. Turn off Mock Location apps and disable mock location before using the app.',
        );
      }

      double? instLat = cachedLatitude;
      double? instLng = cachedLongitude;

      // Only query DB if coordinates not cached
      if (instLat == null || instLng == null) {
        if (kDebugMode) {
          debugPrint('📍 No cached GPS, fetching from gps_settings for institute: $instituteId');
        }

        // [gps_settings] has one row per admin; pre-auth PIN login uses the same
        // locked fence as attendance (not .single() on institute_id alone).
        final fence = await GeofenceService().lockedFenceLatLngForInstitute(instituteId);
        if (fence == null) {
          if (kDebugMode) {
            debugPrint(
              '❌ No locked GPS fence for institute_id=$instituteId. '
              'Admin must open GPS Settings, set coordinates, and lock.',
            );
          }
          // 🔧 Return same error as LocationVerificationService
          return (
            isWithinRadius: false,
            distanceMeters: null,
            error: 'Institute GPS is not locked yet. Ask an admin to open GPS Settings, set the campus point, and lock it.',
          );
        }

        instLat = fence.latitude;
        instLng = fence.longitude;

        if (kDebugMode) {
          debugPrint('📍 Using locked fence from gps_settings: Lat=$instLat, Lng=$instLng');
        }
      } else {
        if (kDebugMode) {
          debugPrint('📍 Using cached GPS coordinates: ($instLat, $instLng)');
        }
      }

      // Promotion: institute coords resolved from cache or locked fence row.
      final double refLat = instLat;
      final double refLng = instLng;

      // Calculate distance
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        refLat,
        refLng,
      );

      final double effectiveRadius =
          pinLoginEffectiveFenceRadiusMeters(position.accuracy);
      final isWithin = distance <= effectiveRadius;

      if (kDebugMode) {
        debugPrint(
          '📍 GPS RADIUS CHECK:\n'
          '   Institute: Lat=$refLat, Lng=$refLng\n'
          '   User: Lat=${position.latitude}, Lng=${position.longitude}\n'
          '   Reported accuracy: ±${position.accuracy.toStringAsFixed(1)}m\n'
          '   Distance: ${distance.toStringAsFixed(1)}m | '
          'Effective max: ${effectiveRadius.toStringAsFixed(1)}m '
          '(nominal ${radiusMeters}m + slack) | '
          'Result: ${isWithin ? '✅ INSIDE' : '❌ OUTSIDE'}',
        );
      }

      // If outside, provide helpful message with distance
      if (!isWithin) {
        final outsideBy = (distance - effectiveRadius).toStringAsFixed(1);
        if (kDebugMode) {
          debugPrint(
            '❌ DENIED: User is ${outsideBy}m outside the allowed zone '
            '(effective radius ${effectiveRadius.toStringAsFixed(1)}m)',
          );
        }
      } else {
        if (kDebugMode) {
          debugPrint('✅ APPROVED: PIN login allowed (within effective GPS zone)');
        }
      }

      return (
        isWithinRadius: isWithin,
        distanceMeters: distance,
        error: null,
      );
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ CRITICAL: GPS LOCATION TIMEOUT - PIN LOGIN DENIED');
        debugPrint('   Error: $e');
        debugPrint('   Action Required: Check GPS signal, ensure location services enabled');
      }
      return (
        isWithinRadius: false,
        distanceMeters: null,
        error: '🔒 SECURITY: GPS location verification timed out (15+ seconds).\n\n'
               'Your PIN login has been DENIED for security reasons.\n\n'
               'Please:\n'
               '1. Enable Location Services in Settings\n'
               '2. Enable Location Permission for this app\n'
               '3. Move outdoors or near a window for better GPS signal\n'
               '4. Try PIN login again',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ CRITICAL GPS VERIFICATION FAILURE:');
        debugPrint('   Error: $e');
        debugPrint('   PIN login will be DENIED');
      }
      return (
        isWithinRadius: false,
        distanceMeters: null,
        error: '🔒 SECURITY: Location verification failed.\n\n'
               'Your PIN login has been DENIED for security reasons.\n\n'
               'Error: ${e.toString()}\n\n'
               'Please ensure:\n'
               '• Location Services are ENABLED\n'
               '• Location Permission is GRANTED\n'
               '• You are in an area with GPS signal',
      );
    }
  }

  /// Get cached GPS coordinates from PIN session
  static Future<({double? latitude, double? longitude})> getCachedGpsCoordinates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_prefPinSessionGpsLat);
      final lng = prefs.getDouble(_prefPinSessionGpsLng);
      return (latitude: lat, longitude: lng);
    } catch (_) {
      return (latitude: null, longitude: null);
    }
  }

  /// Check location permission status
  static Future<bool> hasLocationPermission() async {
    try {
      final status = await Geolocator.checkPermission();
      if (status == LocationPermission.denied) {
        final newStatus = await Geolocator.requestPermission();
        return newStatus == LocationPermission.whileInUse ||
            newStatus == LocationPermission.always;
      }
      return status == LocationPermission.whileInUse ||
          status == LocationPermission.always;
    } catch (e) {
      if (kDebugMode) debugPrint('Location permission check error: $e');
      return false;
    }
  }

  /// Enable location services if disabled
  static Future<bool> ensureLocationEnabled() async {
    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        return await Geolocator.openLocationSettings();
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Error enabling location: $e');
      return false;
    }
  }

  /// Format distance for display
  static String formatDistance(double meters) {
    if (meters < 1) {
      return '${(meters * 100).toStringAsFixed(0)} cm';
    } else if (meters < 1000) {
      return '${meters.toStringAsFixed(1)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
  }

  /// Get location permission status string
  static Future<String> getLocationStatusString() async {
    try {
      final hasPermission = await hasLocationPermission();
      if (!hasPermission) {
        return 'Location permission denied';
      }

      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        return 'Location services disabled';
      }

      return 'Location OK';
    } catch (e) {
      return 'Location check failed';
    }
  }
}
