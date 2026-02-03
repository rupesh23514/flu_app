class PaginationResult<T> {
  final List<T> items;
  final int totalCount;
  final int currentPage;
  final int pageSize;
  final bool hasNextPage;
  final bool hasPreviousPage;

  const PaginationResult({
    required this.items,
    required this.totalCount,
    required this.currentPage,
    required this.pageSize,
    required this.hasNextPage,
    required this.hasPreviousPage,
  });

  int get totalPages => (totalCount / pageSize).ceil();
  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  factory PaginationResult.fromQuery({
    required List<T> items,
    required int totalCount,
    required int page,
    required int pageSize,
  }) {
    return PaginationResult<T>(
      items: items,
      totalCount: totalCount,
      currentPage: page,
      pageSize: pageSize,
      hasNextPage: page * pageSize < totalCount,
      hasPreviousPage: page > 1,
    );
  }

  factory PaginationResult.empty({
    int page = 1,
    int pageSize = 20,
  }) {
    return PaginationResult<T>(
      items: [],
      totalCount: 0,
      currentPage: page,
      pageSize: pageSize,
      hasNextPage: false,
      hasPreviousPage: false,
    );
  }

  @override
  String toString() {
    return 'PaginationResult(items: ${items.length}, totalCount: $totalCount, '
           'currentPage: $currentPage, pageSize: $pageSize, '
           'hasNextPage: $hasNextPage, hasPreviousPage: $hasPreviousPage)';
  }
}

class PaginationParams {
  final int page;
  final int pageSize;
  final String? searchQuery;
  final Map<String, dynamic>? filters;
  final String? orderBy;
  final bool ascending;

  const PaginationParams({
    this.page = 1,
    this.pageSize = 20,
    this.searchQuery,
    this.filters,
    this.orderBy,
    this.ascending = true,
  });

  int get offset => (page - 1) * pageSize;

  PaginationParams copyWith({
    int? page,
    int? pageSize,
    String? searchQuery,
    Map<String, dynamic>? filters,
    String? orderBy,
    bool? ascending,
  }) {
    return PaginationParams(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      searchQuery: searchQuery ?? this.searchQuery,
      filters: filters ?? this.filters,
      orderBy: orderBy ?? this.orderBy,
      ascending: ascending ?? this.ascending,
    );
  }

  @override
  String toString() {
    return 'PaginationParams(page: $page, pageSize: $pageSize, '
           'searchQuery: $searchQuery, filters: $filters, '
           'orderBy: $orderBy, ascending: $ascending)';
  }
}