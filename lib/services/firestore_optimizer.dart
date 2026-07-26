import 'package:flutter/foundation.dart';

import 'firestore_cache_service.dart';

/// Cache helper for expensive fetches (legacy name kept for imports).
class FirestoreOptimizer {
  /// Use cache for frequently accessed data
  static Future<T?> getWithCache<T>({
    required String cacheKey,
    required Future<T> Function() fetchFunction,
    Duration cacheDuration = const Duration(minutes: 5),
  }) async {
    final cached = FirestoreCacheService.get<T>(cacheKey);
    if (cached != null) {
      if (kDebugMode) debugPrint('✅ Cache hit: $cacheKey');
      return cached;
    }

    if (kDebugMode) debugPrint('📥 Cache miss: $cacheKey - fetching');
    final data = await fetchFunction();

    if (data != null) {
      FirestoreCacheService.set(cacheKey, data);
    }

    return data;
  }
}
