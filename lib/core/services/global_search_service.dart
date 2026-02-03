import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../../shared/models/customer.dart';
import '../../shared/models/loan.dart';

/// Search result types
enum SearchResultType {
  customer,
  loan,
  payment,
}

/// Individual search result item
class SearchResult {
  final SearchResultType type;
  final int id;
  final String title;
  final String subtitle;
  final String? matchedField;
  final dynamic data;

  SearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    this.matchedField,
    this.data,
  });

  String get typeLabel {
    switch (type) {
      case SearchResultType.customer:
        return 'Customer';
      case SearchResultType.loan:
        return 'Loan';
      case SearchResultType.payment:
        return 'Payment';
    }
  }
}

/// Global search results container
class GlobalSearchResults {
  final List<SearchResult> customers;
  final List<SearchResult> loans;
  final List<SearchResult> payments;
  final int totalCount;

  GlobalSearchResults({
    required this.customers,
    required this.loans,
    required this.payments,
  }) : totalCount = customers.length + loans.length + payments.length;

  bool get isEmpty => totalCount == 0;
  bool get isNotEmpty => totalCount > 0;

  List<SearchResult> get allResults => [...customers, ...loans, ...payments];
}

/// MASTER SEARCH SERVICE - Optimized for 20K+ customers
/// PRIORITY: Book Number > Phone Number > Name
class GlobalSearchService {
  static final GlobalSearchService _instance = GlobalSearchService._internal();
  static GlobalSearchService get instance => _instance;
  GlobalSearchService._internal();

  final DatabaseService _databaseService = DatabaseService.instance;

  /// MASTER SEARCH with optimized priority ordering
  /// Priority: 1. Book Number (exact) 2. Phone Number 3. Name
  /// Handles 20,000+ records efficiently
  Future<GlobalSearchResults> search(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) {
      return GlobalSearchResults(customers: [], loans: [], payments: []);
    }

    final trimmedQuery = query.trim();
    final isDigitsOnly = RegExp(r'^\d+$').hasMatch(trimmedQuery);
    final isPhoneLike = trimmedQuery.length >= 3 && RegExp(r'^[\d\s\-+]+$').hasMatch(trimmedQuery);

    // FAST PATH 1: Exact book number match (numeric input)
    if (isDigitsOnly) {
      final bookNoResult = await _searchByExactBookNo(trimmedQuery);
      if (bookNoResult != null) {
        return GlobalSearchResults(
          customers: [],
          loans: [bookNoResult],
          payments: [],
        );
      }
    }

    // FAST PATH 2: Phone number priority (digits or phone-like input)
    if (isPhoneLike) {
      final phoneResults = await _searchByPhone(trimmedQuery, limit: limit);
      if (phoneResults.isNotEmpty) {
        // Also search loans by book number for numeric input
        final loanResults = isDigitsOnly 
            ? await _searchLoansByBookNo(trimmedQuery, limit: limit ~/ 2) 
            : <SearchResult>[];
        
        return GlobalSearchResults(
          customers: phoneResults,
          loans: loanResults,
          payments: [],
        );
      }
    }

    // STANDARD SEARCH: Name-based with book number and phone support
    final results = await Future.wait([
      _searchLoansOptimized(trimmedQuery, isDigitsOnly, limit: limit),
      _searchCustomersOptimized(trimmedQuery, limit: limit),
    ]);

    return GlobalSearchResults(
      customers: results[1],
      loans: results[0],
      payments: [], // Skip for speed
    );
  }

  /// FAST: Exact book number match
  Future<SearchResult?> _searchByExactBookNo(String bookNo) async {
    try {
      final db = await _databaseService.database;
      final maps = await db.rawQuery('''
        SELECT l.*, c.name as customer_name
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id AND c.is_active = 1
        WHERE l.is_active = 1 AND l.book_no = ?
        LIMIT 1
      ''', [bookNo]);

      if (maps.isEmpty) return null;

      final loan = Loan.fromMap(maps.first);
      final customerName = maps.first['customer_name'] as String? ?? 'Unknown';

      return SearchResult(
        type: SearchResultType.loan,
        id: loan.id!,
        title: customerName,
        subtitle: '₹${loan.principal}',
        matchedField: 'Book #$bookNo',
        data: loan,
      );
    } catch (e) {
      debugPrint('Error exact book search: $e');
      return null;
    }
  }

  /// FAST: Search loans by book number prefix
  Future<List<SearchResult>> _searchLoansByBookNo(String bookNoPrefix, {int limit = 10}) async {
    try {
      final db = await _databaseService.database;
      final maps = await db.rawQuery('''
        SELECT l.*, c.name as customer_name
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id AND c.is_active = 1
        WHERE l.is_active = 1 AND l.book_no LIKE ?
        ORDER BY 
          CASE WHEN l.book_no = ? THEN 0 ELSE 1 END,
          l.loan_date DESC
        LIMIT ?
      ''', ['$bookNoPrefix%', bookNoPrefix, limit]);

      return maps.map((map) {
        final loan = Loan.fromMap(map);
        return SearchResult(
          type: SearchResultType.loan,
          id: loan.id!,
          title: map['customer_name'] as String? ?? 'Unknown',
          subtitle: '₹${loan.principal}',
          matchedField: loan.bookNo != null ? 'Book #${loan.bookNo}' : null,
          data: loan,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error book number search: $e');
      return [];
    }
  }

  /// FAST: Phone number search (indexed)
  Future<List<SearchResult>> _searchByPhone(String phone, {int limit = 15}) async {
    try {
      final db = await _databaseService.database;
      final cleanPhone = phone.replaceAll(RegExp(r'[\s\-+]'), '');

      final maps = await db.rawQuery('''
        SELECT * FROM customers 
        WHERE is_active = 1 
          AND REPLACE(REPLACE(REPLACE(phone_number, ' ', ''), '-', ''), '+', '') LIKE ?
        ORDER BY 
          CASE WHEN phone_number = ? THEN 0 
               WHEN phone_number LIKE ? THEN 1 
               ELSE 2 END,
          name COLLATE NOCASE
        LIMIT ?
      ''', ['$cleanPhone%', phone, '$phone%', limit]);

      return maps.map((map) {
        final customer = Customer.fromMap(map);
        return SearchResult(
          type: SearchResultType.customer,
          id: customer.id!,
          title: customer.name,
          subtitle: customer.phoneNumber,
          matchedField: 'Phone',
          data: customer,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error phone search: $e');
      return [];
    }
  }

  /// Optimized loan search for large datasets
  Future<List<SearchResult>> _searchLoansOptimized(String query, bool isNumeric, {int limit = 15}) async {
    try {
      final db = await _databaseService.database;
      final pattern = '%${query.toLowerCase()}%';

      // Optimized query with indexed columns prioritized
      final maps = await db.rawQuery('''
        SELECT l.*, c.name as customer_name, c.phone_number as customer_phone
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id AND c.is_active = 1
        WHERE l.is_active = 1 AND (
          l.book_no LIKE ?
          OR LOWER(c.name) LIKE ?
          OR c.phone_number LIKE ?
        )
        ORDER BY 
          CASE 
            WHEN l.book_no = ? THEN 0
            WHEN l.book_no LIKE ? THEN 1
            WHEN c.phone_number LIKE ? THEN 2
            WHEN LOWER(c.name) LIKE ? THEN 3
            ELSE 4
          END,
          l.loan_date DESC
        LIMIT ?
      ''', [
        pattern, pattern, pattern,
        query, '$query%', '$query%', '${query.toLowerCase()}%',
        limit,
      ]);

      return maps.map((map) {
        final loan = Loan.fromMap(map);
        return SearchResult(
          type: SearchResultType.loan,
          id: loan.id!,
          title: map['customer_name'] as String? ?? 'Unknown',
          subtitle: '₹${loan.principal}',
          matchedField: loan.bookNo != null && loan.bookNo!.isNotEmpty 
              ? 'Book #${loan.bookNo}' 
              : null,
          data: loan,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error optimized loan search: $e');
      return [];
    }
  }

  /// Optimized customer search for large datasets
  Future<List<SearchResult>> _searchCustomersOptimized(String query, {int limit = 15}) async {
    try {
      final db = await _databaseService.database;
      final pattern = '%${query.toLowerCase()}%';

      final maps = await db.rawQuery('''
        SELECT * FROM customers 
        WHERE is_active = 1 
          AND (LOWER(name) LIKE ? OR phone_number LIKE ?)
        ORDER BY 
          CASE 
            WHEN phone_number LIKE ? THEN 0
            WHEN LOWER(name) LIKE ? THEN 1
            ELSE 2
          END,
          name COLLATE NOCASE ASC
        LIMIT ?
      ''', [pattern, pattern, '$query%', '${query.toLowerCase()}%', limit]);

      return maps.map((map) {
        final customer = Customer.fromMap(map);
        return SearchResult(
          type: SearchResultType.customer,
          id: customer.id!,
          title: customer.name,
          subtitle: customer.phoneNumber,
          matchedField: null,
          data: customer,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error customer search: $e');
      return [];
    }
  }

  /// Quick lookup by book number
  Future<Loan?> findLoanByBookNumber(String bookNumber) async {
    try {
      final db = await _databaseService.database;
      final maps = await db.rawQuery(
        'SELECT * FROM loans WHERE is_active = 1 AND book_no = ? LIMIT 1',
        [bookNumber],
      );
      if (maps.isEmpty) return null;
      return Loan.fromMap(maps.first);
    } catch (e) {
      debugPrint('Error finding loan by book number: $e');
      return null;
    }
  }

  /// Quick search for customer by phone number
  Future<Customer?> findCustomerByPhone(String phoneNumber) async {
    try {
      return await _databaseService.getCustomerByPhone(phoneNumber);
    } catch (e) {
      debugPrint('Error finding customer by phone: $e');
      return null;
    }
  }
}
