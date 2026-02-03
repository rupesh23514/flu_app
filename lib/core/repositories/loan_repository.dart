// Loan Repository - handles all loan-related database operations
// Extracted from DatabaseService to follow Single Responsibility Principle

import 'package:sqflite/sqflite.dart';
import 'package:decimal/decimal.dart';
import '../../shared/models/loan.dart';
import '../../shared/models/payment.dart';
import '../../shared/models/pagination_result.dart';
import 'base_repository.dart';

class LoanRepository extends BaseRepository {
  // Singleton pattern
  static final LoanRepository _instance = LoanRepository._internal();
  static LoanRepository get instance => _instance;
  LoanRepository._internal();

  // ==================== Loan CRUD Operations ====================

  /// Insert a new loan
  Future<Result<int>> insert(Loan loan) async {
    return safeExecute(() async {
      final db = await database;
      final map = loan.toMap();
      map.remove('id');
      return await db.insert('loans', map);
    });
  }

  /// Get all active loans
  Future<Result<List<Loan>>> getAll() async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'loans',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'due_date ASC',
      );
      return maps.map((map) => Loan.fromMap(map)).toList();
    });
  }

  /// Get loans with pagination and optional filters
  Future<Result<PaginationResult<Loan>>> getPaginated({
    int page = 1,
    int pageSize = 20,
    String? searchQuery,
    int? customerId,
    int? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return safeExecute(() async {
      final db = await database;
      final offset = (page - 1) * pageSize;

      String whereClause = 'l.is_active = 1';
      List<dynamic> whereArgs = [];

      if (customerId != null) {
        whereClause += ' AND l.customer_id = ?';
        whereArgs.add(customerId);
      }

      if (status != null) {
        whereClause += ' AND l.status = ?';
        whereArgs.add(status);
      }

      if (startDate != null) {
        whereClause += ' AND l.loan_date >= ?';
        whereArgs.add(startDate.toIso8601String().split('T')[0]);
      }

      if (endDate != null) {
        whereClause += ' AND l.loan_date <= ?';
        whereArgs.add(endDate.toIso8601String().split('T')[0]);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        whereClause +=
            ' AND (c.name LIKE ? OR c.phone_number LIKE ? OR CAST(l.id AS TEXT) LIKE ? OR l.book_no LIKE ?)';
        final searchPattern = '%$searchQuery%';
        whereArgs.addAll(
            [searchPattern, searchPattern, searchPattern, searchPattern]);
      }

      // Get total count
      final countQuery = '''
        SELECT COUNT(*) as count 
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        WHERE $whereClause AND c.is_active = 1
      ''';
      final countResult = await db.rawQuery(countQuery, whereArgs);
      final totalCount = Sqflite.firstIntValue(countResult) ?? 0;

      // Get paginated results with customer info
      final query = '''
        SELECT l.*, c.name as customer_name, c.phone_number as customer_phone
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        WHERE $whereClause AND c.is_active = 1
        ORDER BY 
          CASE 
            WHEN l.due_date < date('now') THEN 1
            WHEN l.due_date = date('now') THEN 2
            ELSE 3
          END,
          l.due_date ASC
        LIMIT ? OFFSET ?
      ''';

      final maps = await db.rawQuery(query, [...whereArgs, pageSize, offset]);
      final loans = maps.map((map) => Loan.fromMap(map)).toList();

      return PaginationResult.fromQuery(
        items: loans,
        totalCount: totalCount,
        page: page,
        pageSize: pageSize,
      );
    });
  }

  /// Get loan by ID
  Future<Result<Loan?>> getById(int id) async {
    return safeExecute(() async {
      final db = await database;
      final result = await db.query(
        'loans',
        where: 'id = ?',
        whereArgs: [id],
      );
      return result.isNotEmpty ? Loan.fromMap(result.first) : null;
    });
  }

  /// Get loans by customer ID
  Future<Result<List<Loan>>> getByCustomer(int customerId) async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'loans',
        where: 'customer_id = ? AND is_active = ?',
        whereArgs: [customerId, 1],
        orderBy: 'loan_date DESC',
      );
      return maps.map((map) => Loan.fromMap(map)).toList();
    });
  }

  /// Get loans with customer details (for list display)
  /// Returns ALL loans - use getWithCustomersPaginated for large datasets
  Future<Result<List<Map<String, dynamic>>>> getWithCustomers() async {
    return safeExecute(() async {
      final db = await database;
      return await db.rawQuery('''
        SELECT 
          l.*,
          c.name as customer_name,
          c.phone_number as customer_phone,
          c.alternate_phone as customer_phone2,
          c.address as customer_address
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        WHERE l.is_active = 1 AND c.is_active = 1
        ORDER BY 
          CASE 
            WHEN l.due_date < date('now') THEN 1
            WHEN l.due_date = date('now') THEN 2
            ELSE 3
          END,
          l.due_date ASC
      ''');
    });
  }

  /// ENTERPRISE SCALE: Paginated loans with customer details
  /// Use this for 1000+ records to prevent UI lag
  Future<Result<PaginationResult<Map<String, dynamic>>>>
      getWithCustomersPaginated({
    int page = 1,
    int pageSize = 50,
    String? searchQuery,
    int? statusFilter,
  }) async {
    return safeExecute(() async {
      final db = await database;
      final offset = (page - 1) * pageSize;

      String whereClause = 'l.is_active = 1 AND c.is_active = 1';
      List<dynamic> whereArgs = [];

      if (searchQuery != null && searchQuery.isNotEmpty) {
        whereClause +=
            ' AND (c.name LIKE ? OR c.phone_number LIKE ? OR l.book_no LIKE ?)';
        final pattern = '%$searchQuery%';
        whereArgs.addAll([pattern, pattern, pattern]);
      }

      if (statusFilter != null) {
        whereClause += ' AND l.status = ?';
        whereArgs.add(statusFilter);
      }

      // Count query
      final countResult = await db.rawQuery('''
        SELECT COUNT(*) as count 
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        WHERE $whereClause
      ''', whereArgs);
      final totalCount = Sqflite.firstIntValue(countResult) ?? 0;

      // Data query with pagination
      final data = await db.rawQuery('''
        SELECT 
          l.*,
          c.name as customer_name,
          c.phone_number as customer_phone,
          c.alternate_phone as customer_phone2,
          c.address as customer_address
        FROM loans l
        INNER JOIN customers c ON l.customer_id = c.id
        WHERE $whereClause
        ORDER BY 
          CASE 
            WHEN l.due_date < date('now') THEN 1
            WHEN l.due_date = date('now') THEN 2
            ELSE 3
          END,
          l.due_date ASC
        LIMIT ? OFFSET ?
      ''', [...whereArgs, pageSize, offset]);

      return PaginationResult<Map<String, dynamic>>(
        items: data,
        totalCount: totalCount,
        currentPage: page,
        pageSize: pageSize,
        hasNextPage: (page * pageSize) < totalCount,
        hasPreviousPage: page > 1,
      );
    });
  }

  /// Update loan
  Future<Result<int>> update(Loan loan) async {
    return safeExecute(() async {
      final db = await database;
      return await db.update(
        'loans',
        loan.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [loan.id],
      );
    });
  }

  /// Soft delete loan
  Future<Result<int>> delete(int id) async {
    return safeExecute(() async {
      final db = await database;
      return await db.update(
        'loans',
        {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Permanently delete a loan and all its payments from the database
  /// This is a hard delete - data cannot be recovered
  Future<Result<void>> deleteEntirely(int id) async {
    return safeExecute(() async {
      final db = await database;

      // Use transaction to ensure all deletes succeed or none do
      await db.transaction((txn) async {
        // Delete all payments for this loan
        await txn.delete(
          'payments',
          where: 'loan_id = ?',
          whereArgs: [id],
        );

        // Delete reminders for this loan
        await txn.delete(
          'reminders',
          where: 'loan_id = ?',
          whereArgs: [id],
        );

        // Delete the loan itself
        await txn.delete(
          'loans',
          where: 'id = ?',
          whereArgs: [id],
        );
      });
    });
  }

  /// Get loan count (excluding cancelled and closed)
  Future<Result<int>> getCount() async {
    return safeExecute(() async {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM loans WHERE status NOT IN (?, ?)',
        [LoanStatus.cancelled.index, LoanStatus.closed.index],
      );
      return result.first['count'] as int;
    });
  }

  // ==================== Dashboard & Statistics ====================

  /// Get dashboard statistics
  Future<Result<Map<String, Decimal>>> getDashboardStats() async {
    return safeExecute(() async {
      final db = await database;

      // Total given (all active loans)
      final totalGivenResult = await db.rawQuery(
        'SELECT SUM(CAST(principal_amount AS REAL)) as total FROM loans WHERE is_active = 1',
      );
      final totalGiven = Decimal.parse(
        (totalGivenResult.first['total'] ?? 0).toString(),
      );

      // Total received (all payments)
      final totalReceivedResult = await db.rawQuery(
        'SELECT SUM(CAST(amount AS REAL)) as total FROM payments WHERE is_active = 1',
      );
      final totalReceived = Decimal.parse(
        (totalReceivedResult.first['total'] ?? 0).toString(),
      );

      // Outstanding (remaining amount from active loans)
      final outstandingResult = await db.rawQuery(
        'SELECT SUM(CAST(remaining_amount AS REAL)) as total FROM loans WHERE is_active = 1 AND status IN (0, 1)',
      );
      final outstanding = Decimal.parse(
        (outstandingResult.first['total'] ?? 0).toString(),
      );

      // Today's collection
      final todayCollectionResult = await db.rawQuery(
        'SELECT SUM(CAST(amount AS REAL)) as total FROM payments WHERE date(payment_date) = date("now") AND is_active = 1',
      );
      final todayCollection = Decimal.parse(
        (todayCollectionResult.first['total'] ?? 0).toString(),
      );

      return {
        'totalGiven': totalGiven,
        'totalReceived': totalReceived,
        'outstanding': outstanding,
        'todayCollection': todayCollection,
      };
    });
  }

  /// Get all loans with their payments loaded
  Future<Result<List<Loan>>> getAllWithPayments() async {
    return safeExecute(() async {
      final db = await database;
      final loanMaps = await db.query(
        'loans',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'due_date ASC',
      );

      List<Loan> loans = [];
      for (final map in loanMaps) {
        final loan = Loan.fromMap(map);
        // Get payments for this loan
        final paymentMaps = await db.query(
          'payments',
          where: 'loan_id = ? AND is_active = 1',
          whereArgs: [loan.id],
          orderBy: 'payment_date DESC',
        );
        final payments =
            paymentMaps.map((pMap) => Payment.fromMap(pMap)).toList();
        loans.add(loan.copyWith(payments: payments));
      }
      return loans;
    });
  }

  /// Update all existing loans to fix tenure from 12 to 10 weeks
  Future<Result<int>> fixExistingLoansTenure() async {
    return safeExecute(() async {
      final db = await database;
      return await db.rawUpdate('''
        UPDATE loans 
        SET tenure = 10, updated_at = ? 
        WHERE tenure = 12 AND is_active = 1
      ''', [DateTime.now().toIso8601String()]);
    });
  }
}
