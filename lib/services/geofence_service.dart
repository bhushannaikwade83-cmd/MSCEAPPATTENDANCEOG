import 'package:geolocator/geolocator.dart';
import 'dart:math';

/// 🗺️ Geofencing Service - Check if user is within 25m radius of institute
class GeofenceService {
  // 25m radius (50m diameter)
  static const double GEOFENCE_RADIUS_METERS = 25.0;

  /// 🔍 Check if GPS is enabled
  static Future<bool> isGpsEnabled() async {
    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      return isEnabled;
    } catch (e) {
      print('❌ [GEOFENCE] Error checking GPS: $e');
      return false;
    }
  }

  /// 📍 Request location permission
  static Future<LocationPermission> requestLocationPermission() async {
    try {
      final permission = await Geolocator.requestPermission();
      print('✅ [GEOFENCE] Permission result: $permission');
      return permission;
    } catch (e) {
      print('❌ [GEOFENCE] Error requesting permission: $e');
      return LocationPermission.denied;
    }
  }

  /// 📍 Get current location
  static Future<Position?> getCurrentLocation() async {
    try {
      // Check if service is enabled
      final isEnabled = await isGpsEnabled();
      if (!isEnabled) {
        print('❌ [GEOFENCE] GPS not enabled');
        return null;
      }

      // Check permission
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        print('⚠️ [GEOFENCE] Permission denied, requesting...');
        await requestLocationPermission();
      }

      // Get location with timeout
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );

      print('📍 [GEOFENCE] Current location: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('❌ [GEOFENCE] Error getting location: $e');
      return null;
    }
  }

  /// 📏 Calculate distance between two coordinates (in meters)
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusMeters = 6371000; // Earth's radius in meters

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final distance = earthRadiusMeters * c;

    return distance;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// ✅ Check if user is within 25m radius of institute
  static Future<bool> isWithinGeofence({
    required double instituteLat,
    required double instituteLon,
  }) async {
    try {
      print('🔍 [GEOFENCE] Checking if within 25m radius...');
      print('   Institute location: $instituteLat, $instituteLon');

      // Get current location
      final currentPos = await getCurrentLocation();
      if (currentPos == null) {
        print('❌ [GEOFENCE] Could not get current location');
        return false;
      }

      // Calculate distance
      final distance = calculateDistance(
        currentPos.latitude,
        currentPos.longitude,
        instituteLat,
        instituteLon,
      );

      print('📏 [GEOFENCE] Distance from institute: $distance meters');
      print('   Radius threshold: $GEOFENCE_RADIUS_METERS meters');

      final isWithin = distance <= GEOFENCE_RADIUS_METERS;
      print('${isWithin ? "✅" : "❌"} [GEOFENCE] ${isWithin ? "WITHIN" : "OUTSIDE"} geofence');

      return isWithin;
    } catch (e) {
      print('❌ [GEOFENCE] Error checking geofence: $e');
      return false;
    }
  }

  /// 📍 Get institute location (from database or config)
  /// This should return the institute's coordinates
  static Future<({double lat, double lon})?> getInstituteLocation(String instituteId) async {
    try {
      // For now, return dummy location - user should configure institute location
      // In production, fetch from database
      print('⚠️ [GEOFENCE] Institute location not configured for $instituteId');
      return null;
    } catch (e) {
      print('❌ [GEOFENCE] Error getting institute location: $e');
      return null;
    }
  }
}
