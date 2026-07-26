import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;
import 'dart:async';
import '../../core/app_db.dart';
import '../../core/support_contact_instructions.dart';
import '../../core/supabase_maps.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/shimmer_effect.dart';
import '../widgets/enhanced_animations.dart';
import '../widgets/google_search_bar.dart';
import 'institute_registration_screen.dart';

// Sorting enum (Phase 2)
enum InstituteSort {
  byRelevance('Relevance (Default)', Icons.star_outline),
  byNameAsc('Name (A-Z)', Icons.sort_by_alpha),
  byIdAsc('ID (Ascending)', Icons.tag);

  final String label;
  final IconData icon;
  const InstituteSort(this.label, this.icon);
}

class InstituteSearchScreen extends StatefulWidget {
  static const routeName = '/institute-search';
  const InstituteSearchScreen({super.key});

  @override
  State<InstituteSearchScreen> createState() => _InstituteSearchScreenState();
}

class _InstituteSearchScreenState extends State<InstituteSearchScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<String> _suggestions = [];
  bool _isSearching = false;
  bool _isLoading = false;
  bool _showSuggestions = false;
  Timer? _debounce;

  // Phase 2: Sorting state
  InstituteSort _sortOption = InstituteSort.byRelevance;

  // Phase 3: Error and state tracking
  String? _lastError;
  bool _hasNetworkError = false;

  // Pagination state (optimized in Phase 1)
  static const int _pageSize = 30;
  int _page = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _totalCount = 0;
  String _currentSearchQuery = '';
  bool _isInitialLoad = true;

  /// Short SnackBar text for common failures; full error still logged in debug.
  String _messageForInstitutesLoadError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('failed host lookup') ||
        s.contains('socketexception') ||
        s.contains('no address associated with hostname') ||
        s.contains('network is unreachable')) {
      return "Can't reach the server. Check internet, try another network, or turn off VPN/private DNS blocking.";
    }
    if (s.contains('timed out') || s.contains('timeout')) {
      return 'Supabase timed out. Try mobile data, restart the app, or check the project is active in Supabase Dashboard.';
    }
    return 'Error loading institutes: $e';
  }

  static bool _isRetryableNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('socketexception') ||
        s.contains('failed host lookup');
  }

  Future<T> _withNetworkRetry<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      if (!_isRetryableNetworkError(e)) rethrow;
      await Future<void>.delayed(const Duration(seconds: 2));
      return await run();
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchInputChanged);
    _loadInitialInstitutes();
  }

  void _onSearchInputChanged() {
    setState(() => _showSuggestions = _searchController.text.isNotEmpty);

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_searchController.text.isNotEmpty) {
        _updateSuggestions(_searchController.text);
      }
    });
  }

  void _updateSuggestions(String query) {
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    final safe = _sanitizeIlikeFragment(query).toLowerCase();
    final exactMatches = <String>[];
    final partialMatches = <String>{};
    final isNumericQuery = RegExp(r'^[0-9]+$').hasMatch(safe);

    // Get unique institute names and codes that match
    for (final institute in _searchResults) {
      final name = institute['name']?.toString().toLowerCase() ?? '';
      final id = institute['id']?.toString() ?? '';
      final code = institute['instituteCode']?.toString().toLowerCase() ?? '';
      final city = institute['city']?.toString().toLowerCase() ?? '';

      // Exact matches first
      if (name == safe) {
        exactMatches.add(name);
      } else if (isNumericQuery && id == safe) {
        exactMatches.add(id);
      } else if (code == safe) {
        exactMatches.add(code);
      } else {
        // Partial matches
        if (name.contains(safe)) partialMatches.add(name);
        if (code.contains(safe)) partialMatches.add(code);
        if (city.contains(safe)) partialMatches.add(city);
        if (id.contains(safe)) partialMatches.add(id);
      }
    }

    setState(() {
      // Show exact matches first, then partial matches
      _suggestions = [
        ...exactMatches,
        ...partialMatches.toList()..sort(),
      ];
      if (_suggestions.length > 8) {
        _suggestions = _suggestions.sublist(0, 8);
      }
    });
  }

  // Phase 2: Apply sorting based on selected option
  void _applySort(List<Map<String, dynamic>> results) {
    switch (_sortOption) {
      case InstituteSort.byNameAsc:
        results.sort((a, b) {
          final nameA = (a['name'] ?? '').toString().toLowerCase();
          final nameB = (b['name'] ?? '').toString().toLowerCase();
          return nameA.compareTo(nameB);
        });
        break;
      case InstituteSort.byIdAsc:
        results.sort((a, b) {
          final idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
          final idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
          return idA.compareTo(idB);
        });
        break;
      case InstituteSort.byRelevance:
        // Keep original order (already sorted by relevance)
        break;
    }
  }

  // Phase 2: Change sort option and re-sort results
  void _changeSortOption(InstituteSort newSort) {
    if (_sortOption == newSort) return;

    setState(() {
      _sortOption = newSort;
      _applySort(_searchResults);
    });
  }

  // Phase 3: Check if error is network-related
  bool _isNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('failed host lookup') ||
        s.contains('socketexception') ||
        s.contains('no address associated with hostname') ||
        s.contains('network is unreachable') ||
        s.contains('timed out') ||
        s.contains('timeout');
  }

  // Phase 1: Load initial institutes (optimized pagination)
  Future<void> _loadInitialInstitutes() async {
    if (!_isInitialLoad) return;

    setState(() {
      _isLoading = true;
      _page = 0;
      _searchResults.clear();
      _hasMore = true;
      _currentSearchQuery = '';
      _lastError = null;
      _hasNetworkError = false;
    });

    try {
      // Get total count (retry once on timeout — common on slow Wi‑Fi)
      final countRes = await _withNetworkRetry(
        () => appDb.from('institutes').select('id').count(CountOption.exact),
      );
      _totalCount = countRes.count;

      // Load first page
      final rows = await _withNetworkRetry(
        () => appDb
            .from('institutes')
            .select()
            .order('id', ascending: true)
            .range(0, _pageSize - 1),
      );

      if (!mounted) return;

      final newResults = _processInstituteRows(rows as List);
      _applySort(newResults);

      setState(() {
        _searchResults = newResults;
        _page = 1;
        _hasMore = _pageSize < _totalCount;
        _isLoading = false;
        _isInitialLoad = false;
        _lastError = null;
        _hasNetworkError = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading initial institutes: $e');
      if (mounted) {
        final errorMsg = _messageForInstitutesLoadError(e);
        setState(() {
          _isLoading = false;
          _isInitialLoad = false;
          _lastError = errorMsg;
          _hasNetworkError = _isNetworkError(e);
        });
      }
    }
  }

  // Phase 1: Load more institutes (pagination)
  Future<void> _loadMoreInstitutes() async {
    if (_isLoadingMore || !_hasMore || _currentSearchQuery.isNotEmpty) return;

    setState(() => _isLoadingMore = true);

    try {
      final from = _page * _pageSize;
      final rows = await appDb
          .from('institutes')
          .select()
          .order('id', ascending: true)
          .range(from, from + _pageSize - 1);

      if (!mounted) return;

      final newResults = _processInstituteRows(rows as List);

      setState(() {
        _searchResults.addAll(newResults);
        _page += 1;
        _hasMore = from + _pageSize + newResults.length < _totalCount;
        _isLoadingMore = false;
        _lastError = null;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading more institutes: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _lastError = _messageForInstitutesLoadError(e);
        });
      }
    }
  }

  // Phase 1: Process institute rows into display format
  List<Map<String, dynamic>> _processInstituteRows(List rows) {
    return rows.map((row) {
      final m = instituteRowToMap(row as Map<String, dynamic>);
      return {
        ...m,
        'id': row['id'],
        'instituteId': m['instituteId'],
        'instituteCode': m['instituteCode'],
        'name': m['name'] ?? 'Unknown',
        'location': m['location'] ?? '',
        'city': m['city'] ?? '',
        'state': m['state'] ?? '',
        'address': m['address'],
        'district': m['district'],
        'taluka': m['taluka'],
        'mobileNo': m['mobileNo'],
      };
    }).toList();
  }

  /// Safe fragment for PostgREST `ilike` patterns (avoid breaking `.or(...)`).
  static String _sanitizeIlikeFragment(String q) {
    var s = q.trim().replaceAll(',', ' ');
    s = s.replaceAll('%', '').replaceAll('_', '');
    return s.trim();
  }

  /// Columns searched for institute discovery (code, numeric id, name, address).
  static String _orIlikeClause(String pattern) {
    return [
      'name.ilike.$pattern',
      'institute_code.ilike.$pattern',
      'id.ilike.$pattern',
      'location.ilike.$pattern',
      'address.ilike.$pattern',
      'city.ilike.$pattern',
      'district.ilike.$pattern',
      'taluka.ilike.$pattern',
      'state.ilike.$pattern',
    ].join(',');
  }

  Future<List<Map<String, dynamic>>> _queryInstitutesIlike({
    required String pattern,
    int limit = 100,
  }) async {
    final raw = await appDb
        .from('institutes')
        .select()
        .or(_orIlikeClause(pattern))
        .order('id', ascending: true)
        .limit(limit);
    final list = raw as List;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Every token must appear somewhere on the row (any column), case-insensitive.
  static bool _rowMatchesAllTokens(
    Map<String, dynamic> row,
    List<String> tokens,
  ) {
    final blob = [
      row['name'],
      row['institute_code'],
      row['id'],
      row['location'],
      row['address'],
      row['city'],
      row['district'],
      row['taluka'],
      row['state'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
    for (final t in tokens) {
      final tl = t.toLowerCase();
      if (tl.isEmpty) continue;
      if (!blob.contains(tl)) return false;
    }
    return true;
  }


  // Phase 1: Optimized search with server-side filtering
  Future<void> _searchInstitutes(String query) async {
    final safe = _sanitizeIlikeFragment(query);
    if (safe.isEmpty) {
      // Reset to initial load if search is cleared
      setState(() {
        _searchResults.clear();
        _currentSearchQuery = '';
        _page = 0;
        _hasMore = true;
        _lastError = null;
      });
      _loadInitialInstitutes();
      return;
    }

    if (safe == _currentSearchQuery) return;

    setState(() {
      _isSearching = true;
      _searchResults.clear();
      _currentSearchQuery = safe;
      _lastError = null;
    });

    try {
      final qLower = safe.toLowerCase();
      final isNumericQuery = RegExp(r'^[0-9]+$').hasMatch(safe);

      // Construct server-side filter pattern
      final phrasePattern = '%$safe%';

      // Query with optimized filters
      var rows = await _queryInstitutesIlike(
        pattern: phrasePattern,
        limit: 150,
      );

      // Filter for multi-token queries
      final tokens = safe
          .split(RegExp(r'\s+'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      if (tokens.length > 1) {
        final filtered = rows
            .where((r) => _rowMatchesAllTokens(r, tokens))
            .toList();
        if (filtered.isNotEmpty) {
          rows = filtered;
        } else {
          // Fall back to searching with longest token
          final anchor = tokens.reduce((a, b) => a.length >= b.length ? a : b);
          rows = await _queryInstitutesIlike(pattern: '%$anchor%', limit: 200);
          rows = rows.where((r) => _rowMatchesAllTokens(r, tokens)).toList();
        }
      }

      if (!mounted) return;

      final newResults = _processInstituteRows(rows);
      _applySort(newResults);

      setState(() {
        _searchResults = newResults;
        _isSearching = false;
        _hasMore = false; // No pagination for search results
        _lastError = null;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error searching institutes: $e');
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _lastError = _messageForInstitutesLoadError(e);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchInputChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : AppTheme.backgroundGrey,
      appBar: AppBar(
        title: const Text(
          'Find Your Institute',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _buildSupportInfoBanner(isDark),
            ),
            // Google-like Search Bar
            GoogleSearchBar(
              controller: _searchController,
              onSearchChanged: _searchInstitutes,
              onClear: () {
                setState(() => _suggestions = []);
                _loadInitialInstitutes();
              },
              suggestions: _suggestions,
              onSuggestionSelected: (suggestion) {
                _searchInstitutes(suggestion);
                setState(() => _showSuggestions = false);
              },
              showSuggestions: _showSuggestions,
              isSearching: _isSearching,
            ),

            // Phase 2: Sorting selector - show only when results exist
            if (_searchResults.isNotEmpty && !_isLoading)
              _buildSortSelector(isDark),

            // Phase 3: Error message display
            if (_lastError != null)
              _buildErrorBanner(isDark),

            // Results List with Pagination
            Expanded(
              child: _buildResultsList(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportInfoBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.amber.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              kInstituteSupportContactInstructions,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.white70 : AppTheme.textDark,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // Phase 2: Build sorting selector UI
  Widget _buildSortSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              'Sort by: ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : AppTheme.textGray,
              ),
            ),
            const SizedBox(width: 8),
            ...InstituteSort.values.map((sort) {
              final isSelected = _sortOption == sort;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        sort.icon,
                        size: 14,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : AppTheme.textGray),
                      ),
                      const SizedBox(width: 4),
                      Text(sort.label),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (_) => _changeSortOption(sort),
                  backgroundColor: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.grey.shade100,
                  selectedColor: AppTheme.primaryBlue,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : null,
                    fontSize: 11,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? AppTheme.primaryBlue
                        : (isDark ? Colors.white10 : Colors.grey.shade300),
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  // Phase 3: Build error banner
  Widget _buildErrorBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accentRed.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.accentRed.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _hasNetworkError ? Icons.wifi_off : Icons.error_outline,
            color: AppTheme.accentRed,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _lastError ?? 'An error occurred',
              style: TextStyle(
                color: AppTheme.accentRed,
                fontSize: 12,
              ),
            ),
          ),
          if (_hasNetworkError)
            TextButton(
              onPressed: _isInitialLoad ? _loadInitialInstitutes : null,
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  // Phase 3: Build results list with better states
  Widget _buildResultsList(bool isDark) {
    // Phase 3: Loading state with shimmer
    if (_isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) {
          return ShimmerCard().stagger(index: index);
        },
      );
    }

    // Phase 3: Better empty state handling
    if (_searchResults.isEmpty) {
      return _buildEmptyState(isDark);
    }

    // Results with pagination
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length + 1,
      itemBuilder: (context, index) {
        // Pagination footer
        if (index == _searchResults.length) {
          return _buildPaginationFooter(isDark);
        }

        final institute = _searchResults[index];
        return _buildInstituteCard(institute);
      },
    );
  }

  // Phase 3: Enhanced empty state with better messaging
  Widget _buildEmptyState(bool isDark) {
    final query = _searchController.text.trim();
    final isSearching = _isSearching;
    final isSearchActive = query.isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSearchActive
                    ? Icons.search_off
                    : Icons.school_outlined,
                size: 80,
                color: isDark
                    ? Colors.white.withOpacity(0.2)
                    : Colors.grey.shade300,
              ),
              const SizedBox(height: 20),
              Text(
                isSearching
                    ? 'Searching...'
                    : isSearchActive
                        ? 'No institutes found'
                        : 'Loading institutes...',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isSearching
                    ? 'Please wait while we search...'
                    : isSearchActive
                        ? 'Try searching with:\n• Institute name\n• Institute ID\n• City or location'
                        : 'Pull down to load institutes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : AppTheme.textGray,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Phase 3: Better pagination footer
  Widget _buildPaginationFooter(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          if (_isLoadingMore)
            Column(
              children: [
                const CircularProgressIndicator(strokeWidth: 2),
                const SizedBox(height: 12),
                Text(
                  'Loading more institutes...',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                  ),
                ),
              ],
            )
          else if (_hasMore)
            ElevatedButton.icon(
              onPressed: _loadMoreInstitutes,
              icon: const Icon(Icons.expand_more),
              label: Text(
                'Load More (${_searchResults.length}/$_totalCount)',
                style: const TextStyle(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle,
                  color: Colors.green.shade400,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Showing all ${_searchResults.length} institutes',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _openInstituteRegistration(
    Map<String, dynamic> institute,
  ) async {
    final instituteId = (institute['instituteId'] ?? institute['id'])
        .toString();
    final instituteCode = institute['instituteCode']?.toString().trim();
    String? inviteId;
    String? fullName;
    String? email;
    String? phone;
    try {
      Future<void> loadInvite(String key) async {
        final rows = await appDb
            .from('admin_invites')
            .select('id, full_name, phone, email')
            .eq('institute_id', key)
            .eq('claimed', false)
            .limit(1);
        final inviteRows = rows as List;
        if (inviteRows.isEmpty) return;
        final row = Map<String, dynamic>.from(inviteRows.first as Map);
        inviteId = row['id']?.toString();
        fullName = row['full_name']?.toString();
        email = row['email']?.toString();
        phone = row['phone']?.toString();
      }

      await loadInvite(instituteId);
      if (inviteId == null &&
          instituteCode != null &&
          instituteCode.isNotEmpty &&
          instituteCode != instituteId) {
        await loadInvite(instituteCode);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Invite lookup: $e');
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InstituteRegistrationScreen(
          instituteId: instituteId,
          instituteName: institute['name'] ?? 'Unknown',
          instituteLocation: institute['location'] ?? '',
          inviteId: inviteId,
          prefilledFullName: fullName,
          prefilledEmail: email,
          prefilledPhone: phone,
        ),
      ),
    );
  }

  Widget _buildInstituteCard(Map<String, dynamic> institute) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 400;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openInstituteRegistration(institute),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(isNarrowScreen ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with icon and name
                Row(
                  children: [
                    Container(
                      width: isNarrowScreen ? 48 : 56,
                      height: isNarrowScreen ? 48 : 56,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.school_rounded,
                        color: AppTheme.primaryBlue,
                        size: isNarrowScreen ? 24 : 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            institute['name'] ?? 'Unknown Institute',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isNarrowScreen ? 16 : 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.textDark,
                            ),
                          ),
                          if (institute['id'] != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: AppTheme.primaryBlue.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                'ID: ${institute['id']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.primaryBlue,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios,
                        color: AppTheme.primaryBlue,
                        size: isNarrowScreen ? 16 : 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Location info
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: isDark ? Colors.white70 : AppTheme.textGray,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        institute['address'] ??
                            institute['location'] ??
                            'Address not specified',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : AppTheme.textGray,
                        ),
                      ),
                    ),
                  ],
                ),
                // City, District, State info
                if (institute['city'] != null ||
                    institute['district'] != null ||
                    institute['state'] != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (institute['city'] != null)
                        Text(
                          institute['city'],
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : AppTheme.textGray,
                          ),
                        ),
                      if (institute['district'] != null &&
                          institute['district'] != institute['city'])
                        Text(
                          institute['district'],
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : AppTheme.textGray,
                          ),
                        ),
                      if (institute['state'] != null)
                        Text(
                          institute['state'],
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : AppTheme.textGray,
                          ),
                        ),
                    ],
                  ),
                ],
                // Mobile info
                if (institute['mobileNo'] != null &&
                    institute['mobileNo'].toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.phone_outlined,
                        size: 12,
                        color: isDark ? Colors.white70 : AppTheme.textGray,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          institute['mobileNo'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : AppTheme.textGray,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
