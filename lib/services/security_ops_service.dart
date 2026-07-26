import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import 'device_fingerprint_service.dart';

class SecurityOpsService {
  SupabaseClient get _db => appDb;

  Future<bool> isLocked({
    required String identifier,
    required String actionType,
  }) async {
    try {
      final result = await _db.rpc('is_auth_locked', params: {
        'p_identifier': identifier.trim().toLowerCase(),
        'p_action_type': actionType,
      });
      return result == true;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ isLocked failed: $e');
      return false;
    }
  }

  Future<int> getFailedAttemptCount({
    required String identifier,
    required String actionType,
  }) async {
    try {
      final rows = await _db
          .from('security_operations')
          .select('id')
          .eq('identifier', identifier.trim().toLowerCase())
          .eq('action_type', actionType)
          .eq('success', false);
      return (rows as List).length;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ getFailedAttemptCount failed: $e');
      return 0;
    }
  }

  Future<Map<String, dynamic>> recordAttempt({
    required String identifier,
    required String actionType,
    required bool success,
    String? instituteId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final result = await _db.rpc('record_auth_attempt', params: {
        'p_identifier': identifier.trim().toLowerCase(),
        'p_action_type': actionType,
        'p_success': success,
        'p_institute_id': instituteId,
        'p_metadata': metadata ?? <String, dynamic>{},
      });
      if (result is Map<String, dynamic>) return result;
      if (result is Map) {
        return result.map((k, v) => MapEntry(k.toString(), v));
      }
      return {'success': true, 'locked': false};
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ recordAttempt failed: $e');
      return {'success': false, 'locked': false, 'message': e.toString()};
    }
  }

  Future<void> reportIncident({
    required String instituteId,
    required String category,
    required String severity,
    required String title,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _db.rpc('report_security_incident', params: {
        'p_institute_id': instituteId,
        'p_category': category,
        'p_severity': severity,
        'p_title': title,
        'p_description': description,
        'p_metadata': metadata ?? <String, dynamic>{},
      });
      await sendIncidentAlert(
        incident: {
          'institute_id': instituteId,
          'category': category,
          'severity': severity,
          'title': title,
          'description': description,
          'metadata': metadata ?? <String, dynamic>{},
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ reportIncident failed: $e');
    }
  }

  Future<Map<String, dynamic>> collectDeviceRiskSignals() async {
    try {
      final fp = await DeviceFingerprintService.getDeviceFingerprint();
      final history = await DeviceFingerprintService.getDeviceHistory();
      final deviceChanged = await DeviceFingerprintService.hasDeviceChanged();

      final platform = (fp['platform'] ?? 'unknown').toString();
      final hasStableId = (fp['deviceId'] != null || fp['androidId'] != null);
      final riskFlags = <String>[];
      if (deviceChanged) riskFlags.add('device_changed');
      if (!hasStableId) riskFlags.add('missing_stable_device_id');
      if (platform == 'unknown') riskFlags.add('unknown_platform');
      if (history.length > 5) riskFlags.add('many_device_fingerprints');

      // Attestation readiness signal (server-side integrity token verification can use this).
      final attestationReady = platform == 'android' || platform == 'ios';

      return {
        'platform': platform,
        'fingerprint': fp['fingerprint'],
        'deviceChanged': deviceChanged,
        'historyCount': history.length,
        'attestationReady': attestationReady,
        'riskFlags': riskFlags,
      };
    } catch (e) {
      return {
        'platform': 'unknown',
        'deviceChanged': false,
        'historyCount': 0,
        'attestationReady': false,
        'riskFlags': ['risk_collection_error'],
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> verifyDeviceTrust({
    required String platform,
    required String token,
  }) async {
    try {
      final normalizedPlatform = platform.trim().toLowerCase();
      final normalizedToken = token.trim();
      final supportedPlatform =
          normalizedPlatform == 'android' || normalizedPlatform == 'ios';
      final looksValid = supportedPlatform && normalizedToken.length >= 16;

      return {
        'success': true,
        'verified': looksValid,
        'riskLevel': looksValid ? 'low' : 'high',
        'reason': looksValid
            ? 'baseline device trust accepted'
            : 'platform/token shape invalid',
      };
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ verifyAttestation failed: $e');
      return {'success': false, 'verified': false, 'reason': e.toString()};
    }
  }

  // Backward-compatible alias while migrating callers.
  Future<Map<String, dynamic>> verifyAttestation({
    required String platform,
    required String token,
  }) {
    return verifyDeviceTrust(platform: platform, token: token);
  }

  Future<void> sendIncidentAlert({
    required Map<String, dynamic> incident,
  }) async {
    try {
      await _db.functions.invoke(
        'security-incident-alert',
        body: {
          'mode': 'single',
          'incident': incident,
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ sendIncidentAlert failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getRecentIncidents({
    required String instituteId,
    int limit = 50,
  }) async {
    try {
      final rows = await _db
          .from('security_incidents')
          .select()
          .eq('institute_id', instituteId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ getRecentIncidents failed: $e');
      return [];
    }
  }

  Future<Map<String, int>> getIncidentSummary({
    required String instituteId,
  }) async {
    final incidents = await getRecentIncidents(instituteId: instituteId, limit: 200);
    var open = 0;
    var high = 0;
    var critical = 0;
    for (final i in incidents) {
      final status = (i['status'] ?? '').toString().toLowerCase();
      final severity = (i['severity'] ?? '').toString().toLowerCase();
      if (status == 'open' || status == 'investigating') open++;
      if (severity == 'high') high++;
      if (severity == 'critical') critical++;
    }
    return {
      'open': open,
      'high': high,
      'critical': critical,
      'total': incidents.length,
    };
  }
}
