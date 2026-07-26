import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/performance_utils.dart';
import '../models/pagination_model.dart';

/// Optimized database service for handling large-scale queries
/// Implements pagination, caching, and performance monitoring
class DatabaseOptimizationService {
  static final DatabaseOptimizationService _instance =
      DatabaseOptimizationService._internal();
  final SupabaseClient _db = Supabase.instance.client;
  final PerformanceCache<dynamic> _cache = PerformanceCache();
  final PerformanceMonitor _monitor = PerformanceMonitor();

  factory DatabaseOptimizationService() {
    return _instance;
  }

  DatabaseOptimizationService._internal();

  // ============================================================================
  // STUDENT QUERIES
  // ============================================================================

  /// Get paginated students for an institute
  /// Filters by institute_id automatically for data isolation
  Future<PaginationState<Map<String, dynamic>>> getStudentsPaginated({
    required String instituteId,
    int page = 1,
    int pageSize = 50,
    String? searchQuery,
    bool useCache = true,
  }) async {
    try {
      // Check cache first
      final cacheKey = 'students_${instituteId}_page_${page}_size_${pageSize}';
      if (useCache) {
        final cached = _cache.get(cacheKey) as List<Map<String, dynamic>>?;
        if (cached != null) {
          if (kDebugMode) debugPrint('💾 Using cached students page $page');
          return PaginationState(
            items: cached,
            currentPage: page,
            pageSize: pageSize,
            hasMore: cached.length == pageSize,
            isLoading: false,
          );
        }
      }

      // Build query — use `dynamic` so order/range chain types stay valid.
      dynamic query = _db
          .from('students')
          .select('id, name, user_id, sr_no, status')
          .eq('institute_id', instituteId);

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.ilike('name', '%$searchQuery%');
      }

      // Add pagination
      final offset = (page - 1) * pageSize;
      query = query.order('name', ascending: true).range(offset, offset + pageSize - 1);

      // Execute query with measurement
      final students = await measureQuery(
        'getStudentsPaginated (institute=$instituteId, page=$page)',
        () => query,
      );

      // Cache results
      if (useCache && students.isNotEmpty) {
        _cache.set(
          cacheKey,
          students,
          ttl: const Duration(minutes: 5),
        );
      }

      return PaginationState(
        items: students,
        currentPage: page,
        pageSize: pageSize,
        hasMore: students.length == pageSize,
        isLoading: false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error fetching paginated students: $e');
      return PaginationState(
        items: [],
        currentPage: page,
        pageSize: pageSize,
        hasMore: false,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Search students (with debounce and pagination)
  Future<List<Map<String, dynamic>>> searchStudents({
    required String instituteId,
    required String query,
    int limit = 20,
  }) async {
    try {
      if (query.length < 2) return [];

      final cacheKey = 'search_students_${instituteId}_$query';
      final cached = _cache.get(cacheKey) as List<Map<String, dynamic>>?;
      if (cached != null) {
        if (kDebugMode) debugPrint('💾 Using cached search results');
        return cached;
      }

      final results = await measureQuery(
        'searchStudents (query=$query)',
        () => _db
            .from('students')
            .select('id, name, user_id, sr_no')
            .eq('institute_id', instituteId)
            .ilike('name', '%$query%')
            .order('name')
            .limit(limit),
      );

      _cache.set(
        cacheKey,
        results,
        ttl: const Duration(minutes: 2),
      );

      return results;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error searching students: $e');
      return [];
    }
  }

  /// Get single student by ID
  Future<Map<String, dynamic>?> getStudentById({
    required String instituteId,
    required String studentId,
  }) async {
    try {
      final cacheKey = 'student_$studentId';
      final cached = _cache.get(cacheKey) as Map<String, dynamic>?;
      if (cached != null) {
        if (kDebugMode) debugPrint('💾 Using cached student');
        return cached;
      }

      final student = await measureQuery(
        'getStudentById (id=$studentId)',
        () => _db
            .from('students')
            .select()
            .eq('institute_id', instituteId)
            .eq('id', studentId)
            .maybeSingle(),
      );

      if (student != null) {
        _cache.set(
          cacheKey,
          student,
          ttl: const Duration(minutes: 5),
        );
      }

      return student;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error fetching student: $e');
      return null;
    }
  }

  // ============================================================================
  // ATTENDANCE QUERIES
  // ============================================================================

  /// Get paginated attendance records
  Future<PaginationState<Map<String, dynamic>>> getAttendancePaginated({
    required String instituteId,
    String? date,
    String? studentId,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      // App stores attendance in `attendance_in_out` (indexed by institutes.institute_code
      // and/or institutes.id — mirror hierarchical_attendance behaviour).
      final instRow =
          await _db.from('institutes').select('institute_code').eq('id', instituteId).maybeSingle();
      final code = (instRow?['institute_code'] as String?)?.trim() ?? '';
      final instituteCodes = <String>{
        instituteId,
        if (code.isNotEmpty) code,
      }..removeWhere((s) => s.isEmpty);

      dynamic query = _db
          .from('attendance_in_out')
          .select()
          .inFilter('institute_code', instituteCodes.toList());

      if (date != null) {
        query = query.eq('attendance_date', date);
      }

      if (studentId != null) {
        query = query.eq('student_id', studentId);
      }

      final offset = (page - 1) * pageSize;
      query = query
          .order('created_at', ascending: false)
          .range(offset, offset + pageSize - 1);

      final records = await measureQuery(
        'getAttendancePaginated (institute=$instituteId, page=$page)',
        () => query,
      );

      return PaginationState(
        items: records,
        currentPage: page,
        pageSize: pageSize,
        hasMore: records.length == pageSize,
        isLoading: false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error fetching paginated attendance: $e');
      return PaginationState(
        items: [],
        currentPage: page,
        pageSize: pageSize,
        hasMore: false,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Check if student exists and is approved
  Future<bool> studentExists({
    required String instituteId,
    required String studentId,
  }) async {
    try {
      final result = await measureQuery(
        'studentExists (id=$studentId)',
        () => _db
            .from('students')
            .select('id')
            .eq('institute_id', instituteId)
            .eq('id', studentId)
            .maybeSingle(),
      );

      return result != null;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking student existence: $e');
      return false;
    }
  }

  /// Invalidate student-related cache
  void invalidateStudentCache({String? instituteId}) {
    if (instituteId == null) {
      _cache.clear();
    }
    if (kDebugMode) {
      debugPrint('🔄 Invalidated student cache');
    }
  }

  /// Clear all cache
  void clearCache() {
    _cache.clear();
    if (kDebugMode) {
      debugPrint('🔄 Cleared all cache');
    }
  }

  // ============================================================================
  // PERFORMANCE MONITORING
  // ============================================================================

  /// Print performance summary
  void printPerformanceSummary() {
    _monitor.printSummary();
  }

  /// Get slowest queries
  List<QueryPerformance> getSlowestQueries({int limit = 5}) {
    return _monitor.getSlowestQueries(limit: limit);
  }
}
