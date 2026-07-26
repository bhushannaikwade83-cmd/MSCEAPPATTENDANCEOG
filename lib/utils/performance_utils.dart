import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, VoidCallback;

/// Cache entry with expiry time
class _CacheEntry<T> {
  final T data;
  final DateTime createdAt;
  final Duration ttl; // Time to live

  _CacheEntry(this.data, this.ttl) : createdAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt).compareTo(ttl) > 0;
}

/// Simple in-memory cache with TTL support
class PerformanceCache<T> {
  final Map<String, _CacheEntry<T>> _cache = {};

  /// Get from cache if not expired
  T? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }

    if (kDebugMode) {
      debugPrint('💾 Cache HIT: $key');
    }
    return entry.data;
  }

  /// Set in cache with TTL
  void set(String key, T data, {Duration ttl = const Duration(minutes: 5)}) {
    _cache[key] = _CacheEntry(data, ttl);
    if (kDebugMode) {
      debugPrint('💾 Cache SET: $key (TTL: ${ttl.inMinutes}m)');
    }
  }

  /// Clear specific key
  void invalidate(String key) {
    _cache.remove(key);
    if (kDebugMode) {
      debugPrint('💾 Cache INVALIDATED: $key');
    }
  }

  /// Clear all cache
  void clear() {
    _cache.clear();
    if (kDebugMode) {
      debugPrint('💾 Cache CLEARED (${_cache.length} entries removed)');
    }
  }

  /// Get cache size
  int get size => _cache.length;
}

/// Retry logic with exponential backoff
class RetryHelper {
  static Future<T> retry<T>(
    Future<T> Function() fn, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    double backoffMultiplier = 2.0,
  }) async {
    int retryCount = 0;
    Duration delay = initialDelay;

    while (true) {
      try {
        return await fn();
      } catch (e) {
        retryCount++;

        if (retryCount >= maxRetries) {
          if (kDebugMode) {
            debugPrint('❌ RETRY FAILED after $maxRetries attempts: $e');
          }
          rethrow;
        }

        if (kDebugMode) {
          debugPrint(
            '⚠️ RETRY: Attempt $retryCount failed, waiting ${delay.inSeconds}s before retry: $e',
          );
        }

        await Future.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * backoffMultiplier).toInt(),
        );
      }
    }
  }
}

/// Query performance measurement
class QueryPerformance {
  final String queryName;
  final Duration duration;
  final bool success;
  final String? error;

  QueryPerformance({
    required this.queryName,
    required this.duration,
    this.success = true,
    this.error,
  });

  bool get isSlowQuery => duration.inMilliseconds > 5000;

  String get formattedDuration {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds}ms';
    }
    return '${(duration.inMilliseconds / 1000).toStringAsFixed(2)}s';
  }

  @override
  String toString() {
    if (success) {
      final emoji = isSlowQuery ? '🐢' : '⚡';
      return '$emoji $queryName: $formattedDuration';
    }
    return '❌ $queryName failed (${duration.inMilliseconds}ms): $error';
  }
}

/// Measure query performance
Future<T> measureQuery<T>(
  String queryName,
  Future<T> Function() query, {
  bool logSlowOnly = false,
}) async {
  final stopwatch = Stopwatch()..start();

  try {
    final result = await query();
    stopwatch.stop();

    final performance = QueryPerformance(
      queryName: queryName,
      duration: stopwatch.elapsed,
      success: true,
    );

    if (kDebugMode) {
      if (logSlowOnly && !performance.isSlowQuery) {
        // Only log if slow
      } else {
        debugPrint(performance.toString());
      }
    }

    return result;
  } catch (e) {
    stopwatch.stop();

    final performance = QueryPerformance(
      queryName: queryName,
      duration: stopwatch.elapsed,
      success: false,
      error: e.toString(),
    );

    if (kDebugMode) {
      debugPrint(performance.toString());
    }

    rethrow;
  }
}

/// Performance monitoring service
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  final List<QueryPerformance> _metrics = [];

  factory PerformanceMonitor() {
    return _instance;
  }

  PerformanceMonitor._internal();

  /// Record a query performance metric
  void recordMetric(QueryPerformance metric) {
    _metrics.add(metric);

    // Keep only last 100 metrics to avoid memory bloat
    if (_metrics.length > 100) {
      _metrics.removeAt(0);
    }

    if (kDebugMode && metric.isSlowQuery) {
      debugPrint('⚠️ SLOW QUERY DETECTED: $metric');
    }
  }

  /// Get average query time
  Duration getAverageQueryTime() {
    if (_metrics.isEmpty) return Duration.zero;

    final totalMs = _metrics.fold<int>(
      0,
      (sum, metric) => sum + metric.duration.inMilliseconds,
    );

    return Duration(milliseconds: totalMs ~/ _metrics.length);
  }

  /// Get slowest queries
  List<QueryPerformance> getSlowestQueries({int limit = 5}) {
    final sorted = List<QueryPerformance>.from(_metrics)
      ..sort((a, b) => b.duration.compareTo(a.duration));
    return sorted.take(limit).toList();
  }

  /// Clear metrics
  void clear() {
    _metrics.clear();
    if (kDebugMode) {
      debugPrint('📊 Performance metrics cleared');
    }
  }

  /// Print performance summary
  void printSummary() {
    if (_metrics.isEmpty) {
      if (kDebugMode) {
        debugPrint('📊 No performance metrics recorded yet');
      }
      return;
    }

    final slowQueries =
        _metrics.where((m) => m.isSlowQuery && m.success).length;
    final failedQueries = _metrics.where((m) => !m.success).length;
    final avgTime = getAverageQueryTime();

    if (kDebugMode) {
      debugPrint('''
📊 PERFORMANCE SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📈 Total Queries: ${_metrics.length}
⚡ Avg Time: ${avgTime.inMilliseconds}ms
🐢 Slow Queries (>5s): $slowQueries
❌ Failed Queries: $failedQueries
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      ''');

      final slowest = getSlowestQueries(limit: 3);
      if (slowest.isNotEmpty) {
        debugPrint('🐢 SLOWEST QUERIES:');
        for (final metric in slowest) {
          debugPrint('   $metric');
        }
      }
    }
  }
}

/// Debounce helper for search and rapid operations
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 500)});

  /// Run function after delay (cancels previous calls)
  void call(VoidCallback callback) {
    _timer?.cancel();
    _timer = Timer(delay, callback);
  }

  /// Cancel pending execution
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Dispose resources
  void dispose() {
    cancel();
  }
}

/// Throttle helper for scroll and continuous events
class Throttler {
  final Duration duration;
  DateTime? _lastExecutedTime;
  Timer? _pendingTimer;

  Throttler({this.duration = const Duration(milliseconds: 300)});

  /// Execute function, throttled by duration
  void call(VoidCallback callback) {
    final now = DateTime.now();
    final lastTime = _lastExecutedTime;

    if (lastTime == null ||
        now.difference(lastTime).compareTo(duration) >= 0) {
      _lastExecutedTime = now;
      _pendingTimer?.cancel();
      _pendingTimer = null;
      callback();
    } else {
      // Schedule for later
      _pendingTimer?.cancel();
      _pendingTimer = Timer(duration, () {
        _lastExecutedTime = DateTime.now();
        callback();
      });
    }
  }

  /// Dispose resources
  void dispose() {
    _pendingTimer?.cancel();
  }
}
