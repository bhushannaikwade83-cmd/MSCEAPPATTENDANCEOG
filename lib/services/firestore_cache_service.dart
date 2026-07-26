import 'package:flutter/foundation.dart';
import 'dart:convert';

/// Cache service to reduce Firestore reads
/// Caches frequently accessed data in memory
class FirestoreCacheService {
  static final Map<String, dynamic> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5); // Cache for 5 minutes

  /// Get cached data
  static T? get<T>(String key) {
    if (!_cache.containsKey(key)) return null;
    
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) {
      _cache.remove(key);
      return null;
    }

    // Check if cache expired
    if (DateTime.now().difference(timestamp) > _cacheExpiry) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
      return null;
    }

    return _cache[key] as T?;
  }

  /// Set cached data
  static void set(String key, dynamic value) {
    _cache[key] = value;
    _cacheTimestamps[key] = DateTime.now();
  }

  /// Clear cache
  static void clear() {
    _cache.clear();
    _cacheTimestamps.clear();
  }

  /// Clear specific key
  static void clearKey(String key) {
    _cache.remove(key);
    _cacheTimestamps.remove(key);
  }

  /// Get cache size (for debugging)
  static int get cacheSize => _cache.length;
}
