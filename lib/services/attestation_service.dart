import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../core/app_db.dart';

class AttestationService {
  Future<Map<String, dynamic>> verifyToken({
    required String platform,
    required String token,
    required String sharedSecret,
  }) async {
    try {
      final result = await appDb.functions.invoke(
        'attestation-verify',
        body: {
          'platform': platform,
          'token': token,
          'sharedSecret': sharedSecret,
        },
      );
      final data = result.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return data.map((k, v) => MapEntry(k.toString(), v));
      return {'success': false, 'verified': false, 'reason': 'invalid response'};
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ attestation verify failed: $e');
      return {'success': false, 'verified': false, 'reason': e.toString()};
    }
  }
}
