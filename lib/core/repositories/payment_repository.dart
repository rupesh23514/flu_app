// Payment Repository - handles all payment-related database operations
// Extracted from DatabaseService to follow Single Responsibility Principle

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../shared/models/payment.dart';
import 'base_repository.dart';

class PaymentRepository extends BaseRepository {
  // Singleton pattern
  static final PaymentRepository _instance = PaymentRepository._internal();
  static PaymentRepository get instance => _instance;
  PaymentRepository._internal();

  // ==================== Payment CRUD Operations ====================

  /// Insert a new payment
  Future<Result<int>> insert(Payment payment) async {
    return safeExecute(() async {
      final db = await database;

      // Get payment data and ensure schema compatibility
      Map<String, dynamic> paymentData = payment.toMap();

      // Check if payment_method column exists
      final result = await db.rawQuery('PRAGMA table_info(payments)');
      final columns = result.map((row) => row['name'].toString()).toList();

      if (!columns.contains('payment_method')) {
        // Remove payment_method from data if column doesn't exist
        paymentData.remove('payment_method');
        debugPrint('DEBUG: Removed payment_method from insert data (column does not exist)');
      }

      debugPrint('DEBUG: PaymentRepository insert called with payment: $paymentData');
      final insertResult = await db.insert('payments', paymentData);
      debugPrint('DEBUG: insert result: $insertResult');
      return insertResult;
    });
  }

  /// Get all payments for a specific loan
  Future<Result<List<Payment>>> getByLoan(int loanId) async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'payments',
        where: 'loan_id = ? AND is_active = 1',
        whereArgs: [loanId],
        orderBy: 'payment_date DESC',
      );
      return maps.map((map) => Payment.fromMap(map)).toList();
    });
  }

  /// Get a single payment by ID
  Future<Result<Payment?>> getById(int paymentId) async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'payments',
        where: 'id = ? AND is_active = 1',
        whereArgs: [paymentId],
        limit: 1,
      );
      return maps.isNotEmpty ? Payment.fromMap(maps.first) : null;
    });
  }

  /// Get all payments for a specific customer
  Future<Result<List<Payment>>> getByCustomer(int customerId) async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'payments',
        where: 'customer_id = ? AND is_active = 1',
        whereArgs: [customerId],
        orderBy: 'payment_date DESC',
      );
      return maps.map((map) => Payment.fromMap(map)).toList();
    });
  }

  /// Get payments within a date range
  Future<Result<List<Payment>>> getByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'payments',
        where: 'payment_date >= ? AND payment_date <= ? AND is_active = 1',
        whereArgs: [startDate.toIso8601String(), endDate.toIso8601String()],
        orderBy: 'payment_date DESC',
      );
      return maps.map((map) => Payment.fromMap(map)).toList();
    });
  }

  /// Get all payments
  Future<Result<List<Payment>>> getAll() async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'payments',
        where: 'is_active = 1',
        orderBy: 'payment_date DESC',
      );
      return maps.map((map) => Payment.fromMap(map)).toList();
    });
  }

  /// Update an existing payment
  Future<Result<int>> update(Payment payment) async {
    return safeExecute(() async {
      final db = await database;
      final paymentData = payment.copyWith(updatedAt: DateTime.now()).toMap();

      // Check if payment_method column exists
      final result = await db.rawQuery('PRAGMA table_info(payments)');
      final columns = result.map((row) => row['name'].toString()).toList();

      if (!columns.contains('payment_method')) {
        paymentData.remove('payment_method');
      }

      return await db.update(
        'payments',
        paymentData,
        where: 'id = ?',
        whereArgs: [payment.id],
      );
    });
  }

  /// Soft delete a payment (set is_active = 0)
  Future<Result<int>> delete(int paymentId) async {
    return safeExecute(() async {
      final db = await database;
      return await db.update(
        'payments',
        {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [paymentId],
      );
    });
  }

  /// Permanently delete a payment (hard delete)
  Future<Result<int>> permanentlyDelete(int paymentId) async {
    return safeExecute(() async {
      final db = await database;
      return await db.delete(
        'payments',
        where: 'id = ?',
        whereArgs: [paymentId],
      );
    });
  }

  /// Soft delete all payments for a specific loan (scoped to loan ID only)
  /// This ensures other loans for the same customer are not affected
  Future<Result<int>> deleteByLoan(int loanId) async {
    return safeExecute(() async {
      final db = await database;
      return await db.update(
        'payments',
        {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'loan_id = ? AND is_active = 1', // Only delete active payments for this specific loan
        whereArgs: [loanId],
      );
    });
  }

  // ==================== Statistics & Aggregations ====================

  /// Get total amount collected today
  Future<Result<double>> getTodayCollection() async {
    return safeExecute(() async {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT SUM(CAST(amount AS REAL)) as total FROM payments WHERE date(payment_date) = date("now") AND is_active = 1',
      );
      return (result.first['total'] as num?)?.toDouble() ?? 0.0;
    });
  }

  /// Get total amount collected in a date range
  Future<Result<double>> getTotalByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    return safeExecute(() async {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT SUM(CAST(amount AS REAL)) as total FROM payments WHERE payment_date >= ? AND payment_date <= ? AND is_active = 1',
        [startDate.toIso8601String(), endDate.toIso8601String()],
      );
      return (result.first['total'] as num?)?.toDouble() ?? 0.0;
    });
  }

  /// Get payment count for a loan
  Future<Result<int>> getCountByLoan(int loanId) async {
    return safeExecute(() async {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM payments WHERE loan_id = ? AND is_active = 1',
        [loanId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    });
  }

  /// Get total paid amount for a loan
  Future<Result<double>> getTotalByLoan(int loanId) async {
    return safeExecute(() async {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT SUM(CAST(amount AS REAL)) as total FROM payments WHERE loan_id = ? AND is_active = 1',
        [loanId],
      );
      return (result.first['total'] as num?)?.toDouble() ?? 0.0;
    });
  }
}
