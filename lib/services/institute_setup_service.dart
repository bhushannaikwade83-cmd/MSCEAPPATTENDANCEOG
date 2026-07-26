import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../core/app_db.dart';
import '../core/gps_attendance_constants.dart';
import '../core/supabase_maps.dart';
import 'auth_service.dart';
import 'database_init_service.dart';

/// Creates an institute row, geofence defaults, and admin via [AuthService].
class InstituteSetupService {
  final AuthService _authService = AuthService();

  static String _setupKey(String instituteId) => 'institute_setup_$instituteId';

  Future<Map<String, dynamic>> setupInstitute({
    required String instituteId,
    required String name,
    String? instituteCode,
    String? location,
    String? address,
    String? city,
    String? district,
    String? taluka,
    String? state,
    String? country,
    String? mobileNo,
    required String adminName,
    required String adminEmail,
    required String adminPassword,
    required String adminMobile,
  }) async {
    try {
      await DatabaseInitService.ensureInitialized();

      if (kDebugMode) {
        debugPrint('🏗️  Starting institute setup for: $name (ID: $instituteId)');
      }

      final existing = await appDb.from('institutes').select('id').eq('id', instituteId).maybeSingle();
      if (existing != null) {
        return {
          'success': false,
          'message': 'Institute with ID "$instituteId" already exists',
        };
      }

      if (instituteCode != null && instituteCode.isNotEmpty) {
        final dup = await appDb
            .from('institutes')
            .select('id')
            .eq('institute_code', instituteCode)
            .maybeSingle();
        if (dup != null) {
          return {
            'success': false,
            'message': 'Institute with code "$instituteCode" already exists',
          };
        }
      }

      final now = DateTime.now().toUtc().toIso8601String();

      await appDb.from('institutes').insert({
        'id': instituteId,
        'institute_code': instituteCode ?? '',
        'name': name,
        'location': location ?? '',
        'address': address ?? '',
        'city': city ?? '',
        'district': district ?? '',
        'taluka': taluka ?? '',
        'state': state ?? '',
        'country': country ?? 'India',
        'mobile_no': mobileNo ?? '',
        'created_at': now,
        'updated_at': now,
        'is_active': true,
        'user_count': 0,
        'student_count': 0,
      });

      await appDb.from('institute_geofence').upsert(
        {
          'institute_id': instituteId,
          'radius': kAttendanceFenceRadiusMeters,
          'data': {
            'enabled': false,
            'latitude': 0.0,
            'longitude': 0.0,
          },
          'updated_at': now,
        },
        onConflict: 'institute_id',
      );

      final adminResult = await _authService.registerInstituteUser(
        instituteId: instituteId,
        instituteName: name,
        name: adminName,
        email: adminEmail,
        password: adminPassword,
        mobile: adminMobile,
      );

      if (adminResult['success'] != true) {
        await appDb.from('institutes').delete().eq('id', instituteId);
        await appDb.from('institute_geofence').delete().eq('institute_id', instituteId);
        return {
          'success': false,
          'message': 'Failed to create admin user: ${adminResult['message']}',
        };
      }

      await _createDefaultConfigurations(instituteId);
      await _createStorageStructure(instituteId);

      await appDb.from('system_settings').upsert(
        {
          'key': _setupKey(instituteId),
          'value': {
            'setupCompleted': true,
            'setupCompletedAt': now,
          },
          'updated_at': now,
        },
        onConflict: 'key',
      );

      if (kDebugMode) {
        debugPrint('✨ Institute setup completed: $instituteId');
      }

      return {
        'success': true,
        'message': 'Institute setup completed successfully',
        'instituteId': instituteId,
        'adminEmail': adminEmail,
        'adminPassword': adminPassword,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error setting up institute: $e');
      try {
        await appDb.from('institutes').delete().eq('id', instituteId);
        await appDb.from('institute_geofence').delete().eq('institute_id', instituteId);
      } catch (_) {}
      return {
        'success': false,
        'message': 'Error setting up institute: ${e.toString()}',
      };
    }
  }

  Future<void> _createDefaultConfigurations(String instituteId) async {
    await DatabaseInitService.ensureInitialized();
    final now = DateTime.now().toUtc().toIso8601String();
    await appDb.from('system_settings').upsert(
      {
        'key': 'institute_config_$instituteId',
        'value': {
          'instituteId': instituteId,
          'attendanceEnabled': true,
          'photoRequired': true,
          'locationRequired': true,
          'maxPhotoSizeKB': 50,
          'allowedFileTypes': ['jpg', 'jpeg', 'png'],
          'emailNotifications': true,
          'smsNotifications': false,
          'pushNotifications': true,
        },
        'updated_at': now,
      },
      onConflict: 'key',
    );
  }

  Future<void> _createStorageStructure(String instituteId) async {
    try {
      await DatabaseInitService.ensureInitialized();
      final now = DateTime.now().toUtc().toIso8601String();
      await appDb.from('system_settings').upsert(
        {
          'key': 'institute_storage_$instituteId',
          'value': {
            'initialized': true,
            'initializedAt': now,
            'note': 'B2 folders created on first upload',
          },
          'updated_at': now,
        },
        onConflict: 'key',
      );
      if (kDebugMode) debugPrint('📁 Storage marker saved in system_settings');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️  Could not create storage marker: $e');
    }
  }

  Future<Map<String, dynamic>> getSetupStatus(String instituteId) async {
    try {
      final instituteDoc = await appDb.from('institutes').select().eq('id', instituteId).maybeSingle();

      if (instituteDoc == null) {
        return {
          'exists': false,
          'setupCompleted': false,
        };
      }

      final meta = await appDb.from('system_settings').select().eq('key', _setupKey(instituteId)).maybeSingle();
      final value = meta?['value'];
      bool completed = false;
      if (value is Map) {
        completed = value['setupCompleted'] == true;
      }

      return {
        'exists': true,
        'setupCompleted': completed,
        'userCount': instituteDoc['user_count'] ?? 0,
        'studentCount': instituteDoc['student_count'] ?? 0,
        'createdAt': instituteDoc['created_at'],
      };
    } catch (e) {
      return {
        'exists': false,
        'error': e.toString(),
      };
    }
  }

  Future<List<Map<String, dynamic>>> listAllInstitutes() async {
    try {
      final rows = await appDb.from('institutes').select().order('created_at', ascending: false);

      return rows.map((data) => instituteRowToMap(data)).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Error listing institutes: $e');
      return [];
    }
  }
}
