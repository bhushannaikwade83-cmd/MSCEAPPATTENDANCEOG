/// Pagination model for handling large datasets
/// Prevents loading 400K+ records at once
class PaginationState<T> {
  final List<T> items;
  final int currentPage;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final String? error;

  const PaginationState({
    this.items = const [],
    this.currentPage = 1,
    this.pageSize = 50,
    this.hasMore = true,
    this.isLoading = false,
    this.error,
  });

  /// Create initial pagination state
  static PaginationState<T> initial<T>({int pageSize = 50}) {
    return PaginationState<T>(
      items: [],
      currentPage: 1,
      pageSize: pageSize,
      hasMore: true,
      isLoading: false,
    );
  }

  /// Update with new items (for pagination)
  PaginationState<T> addItems(List<T> newItems) {
    final allItems = [...items, ...newItems];
    return PaginationState<T>(
      items: allItems,
      currentPage: currentPage + 1,
      pageSize: pageSize,
      hasMore: newItems.length == pageSize, // If got full page, assume there's more
      isLoading: false,
    );
  }

  /// Set loading state
  PaginationState<T> setLoading(bool loading) {
    return PaginationState<T>(
      items: items,
      currentPage: currentPage,
      pageSize: pageSize,
      hasMore: hasMore,
      isLoading: loading,
      error: error,
    );
  }

  /// Set error
  PaginationState<T> setError(String error) {
    return PaginationState<T>(
      items: items,
      currentPage: currentPage,
      pageSize: pageSize,
      hasMore: hasMore,
      isLoading: false,
      error: error,
    );
  }

  /// Reset pagination
  PaginationState<T> reset({int pageSize = 50}) {
    return PaginationState<T>(
      items: [],
      currentPage: 1,
      pageSize: pageSize,
      hasMore: true,
      isLoading: false,
    );
  }

  /// Calculate offset for current page
  int get offset => (currentPage - 1) * pageSize;

  /// Check if should load more
  bool get shouldLoadMore => hasMore && !isLoading;

  /// Total items loaded so far
  int get totalItems => items.length;
}

/// Helper for search pagination
class SearchPaginationState<T> extends PaginationState<T> {
  final String searchQuery;

  const SearchPaginationState({
    List<T> items = const [],
    int currentPage = 1,
    int pageSize = 20,
    bool hasMore = true,
    bool isLoading = false,
    String? error,
    this.searchQuery = '',
  }) : super(
    items: items,
    currentPage: currentPage,
    pageSize: pageSize,
    hasMore: hasMore,
    isLoading: isLoading,
    error: error,
  );

  /// Reset search and pagination
  SearchPaginationState<T> resetSearch(String newQuery) {
    return SearchPaginationState<T>(
      items: [],
      currentPage: 1,
      pageSize: pageSize,
      hasMore: true,
      isLoading: false,
      searchQuery: newQuery,
    );
  }

  /// Add search results
  SearchPaginationState<T> addSearchResults(List<T> newItems) {
    final allItems = [...items, ...newItems];
    return SearchPaginationState<T>(
      items: allItems,
      currentPage: currentPage + 1,
      pageSize: pageSize,
      hasMore: newItems.length == pageSize,
      isLoading: false,
      searchQuery: searchQuery,
    );
  }
}
