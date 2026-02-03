import 'package:decimal/decimal.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import '../services/database_service.dart';
import '../../shared/models/transaction.dart';

/// Service for bank-style transaction tracking
class TransactionService {
  static final TransactionService _instance = TransactionService._internal();
  static TransactionService get instance => _instance;
  TransactionService._internal();

  final DatabaseService _databaseService = DatabaseService.instance;

  /// Initialize transaction table if not exists
  Future<void> ensureTransactionTable() async {
    final db = await _databaseService.database;

    // Check if table exists
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'");

    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          loan_id INTEGER,
          customer_id INTEGER,
          customer_name TEXT,
          transaction_type INTEGER NOT NULL,
          amount TEXT NOT NULL,
          transaction_date TEXT NOT NULL,
          description TEXT,
          reference_number TEXT,
          running_balance TEXT NOT NULL DEFAULT '0',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE SET NULL,
          FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL
        )
      ''');

      // Create indexes
      await db.execute(
          'CREATE INDEX idx_transactions_customer ON transactions(customer_id)');
      await db.execute(
          'CREATE INDEX idx_transactions_date ON transactions(transaction_date)');
      await db.execute(
          'CREATE INDEX idx_transactions_type ON transactions(transaction_type)');
    } else {
      // Check if customer_name column exists, add if not
      final columns = await db.rawQuery("PRAGMA table_info(transactions)");
      final hasCustomerName =
          columns.any((col) => col['name'] == 'customer_name');

      if (!hasCustomerName) {
        await db
            .execute('ALTER TABLE transactions ADD COLUMN customer_name TEXT');

        // Populate customer_name from existing customers
        await db.execute('''
          UPDATE transactions 
          SET customer_name = (
            SELECT name FROM customers WHERE customers.id = transactions.customer_id
          )
          WHERE customer_name IS NULL
        ''');
      }
    }
  }

  /// Record a credit transaction (money received)
  Future<int> recordCredit({
    required int customerId,
    required Decimal amount,
    int? loanId,
    String? description,
    String? referenceNumber,
    DateTime? transactionDate,
  }) async {
    return await _recordTransaction(
      customerId: customerId,
      loanId: loanId,
      type: TransactionType.credit,
      amount: amount,
      description: description ?? 'Payment received',
      referenceNumber: referenceNumber,
      transactionDate: transactionDate ?? DateTime.now(),
    );
  }

  /// Record a debit transaction (money given)
  Future<int> recordDebit({
    required int customerId,
    required Decimal amount,
    int? loanId,
    String? description,
    String? referenceNumber,
    DateTime? transactionDate,
  }) async {
    return await _recordTransaction(
      customerId: customerId,
      loanId: loanId,
      type: TransactionType.debit,
      amount: amount,
      description: description ?? 'Loan disbursed',
      referenceNumber: referenceNumber,
      transactionDate: transactionDate ?? DateTime.now(),
    );
  }

  Future<int> _recordTransaction({
    required int customerId,
    int? loanId,
    required TransactionType type,
    required Decimal amount,
    String? description,
    String? referenceNumber,
    required DateTime transactionDate,
    String? customerName,
  }) async {
    await ensureTransactionTable();
    final db = await _databaseService.database;

    // Get customer name if not provided
    String? resolvedCustomerName = customerName;
    if (resolvedCustomerName == null) {
      final customerResult = await db.query(
        'customers',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      if (customerResult.isNotEmpty) {
        resolvedCustomerName = customerResult.first['name'] as String?;
      }
    }

    // Calculate running balance
    final currentBalance = await getCustomerBalance(customerId);
    final newBalance = type == TransactionType.credit
        ? currentBalance + amount
        : currentBalance - amount;

    final now = DateTime.now();
    final transaction = Transaction(
      loanId: loanId,
      customerId: customerId,
      customerName: resolvedCustomerName,
      type: type,
      amount: amount,
      transactionDate: transactionDate,
      description: description,
      referenceNumber: referenceNumber,
      runningBalance: newBalance,
      createdAt: now,
      updatedAt: now,
    );

    final map = transaction.toMap();
    map.remove('id');
    map.remove('loan_info');
    // Keep customer_name in the map for storage

    return await db.insert('transactions', map);
  }

  /// Get current balance for a customer (total credits - total debits)
  Future<Decimal> getCustomerBalance(int customerId) async {
    await ensureTransactionTable();
    final db = await _databaseService.database;

    final result = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(CASE WHEN transaction_type = 0 THEN CAST(amount AS REAL) ELSE 0 END), 0) as total_credits,
        COALESCE(SUM(CASE WHEN transaction_type = 1 THEN CAST(amount AS REAL) ELSE 0 END), 0) as total_debits
      FROM transactions
      WHERE customer_id = ? AND is_active = 1
    ''', [customerId]);

    if (result.isNotEmpty) {
      final credits =
          Decimal.parse((result.first['total_credits'] ?? 0).toString());
      final debits =
          Decimal.parse((result.first['total_debits'] ?? 0).toString());
      return credits - debits;
    }
    return Decimal.zero;
  }

  /// Get all transactions for a customer
  Future<List<Transaction>> getCustomerTransactions(
    int customerId, {
    int? limit,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
    TransactionType? type,
  }) async {
    await ensureTransactionTable();
    final db = await _databaseService.database;

    String where = 't.customer_id = ? AND t.is_active = 1';
    List<dynamic> args = [customerId];

    if (startDate != null) {
      where += ' AND t.transaction_date >= ?';
      args.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      where += ' AND t.transaction_date <= ?';
      args.add(endDate.toIso8601String());
    }

    if (type != null) {
      where += ' AND t.transaction_type = ?';
      args.add(type.index);
    }

    String query = '''
      SELECT t.*, COALESCE(c.name, t.customer_name) as customer_name
      FROM transactions t
      LEFT JOIN customers c ON t.customer_id = c.id
      WHERE $where
      ORDER BY t.transaction_date DESC, t.id DESC
    ''';

    if (limit != null) {
      query += ' LIMIT $limit';
      if (offset != null) {
        query += ' OFFSET $offset';
      }
    }

    final maps = await db.rawQuery(query, args);
    return maps.map((map) => Transaction.fromMap(map)).toList();
  }

  /// Get all recent transactions (across all customers)
  Future<List<Transaction>> getRecentTransactions({
    int limit = 50,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await ensureTransactionTable();
    final db = await _databaseService.database;

    String where = 't.is_active = 1';
    List<dynamic> args = [];

    if (startDate != null) {
      where += ' AND t.transaction_date >= ?';
      args.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      where += ' AND t.transaction_date <= ?';
      args.add(endDate.toIso8601String());
    }

    // Use COALESCE to get customer name from customers table or stored customer_name
    final maps = await db.rawQuery('''
      SELECT t.*, COALESCE(c.name, t.customer_name) as customer_name
      FROM transactions t
      LEFT JOIN customers c ON t.customer_id = c.id
      WHERE $where
      ORDER BY t.transaction_date DESC, t.id DESC
      LIMIT ?
    ''', [...args, limit]);

    return maps.map((map) => Transaction.fromMap(map)).toList();
  }

  /// Get transaction summary for a period
  Future<TransactionSummary> getTransactionSummary({
    DateTime? startDate,
    DateTime? endDate,
    int? customerId,
  }) async {
    await ensureTransactionTable();
    final db = await _databaseService.database;

    String where = 'is_active = 1';
    List<dynamic> args = [];

    if (customerId != null) {
      where += ' AND customer_id = ?';
      args.add(customerId);
    }

    if (startDate != null) {
      where += ' AND transaction_date >= ?';
      args.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      where += ' AND transaction_date <= ?';
      args.add(endDate.toIso8601String());
    }

    final result = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(CASE WHEN transaction_type = 0 THEN CAST(amount AS REAL) ELSE 0 END), 0) as total_credits,
        COALESCE(SUM(CASE WHEN transaction_type = 1 THEN CAST(amount AS REAL) ELSE 0 END), 0) as total_debits,
        COUNT(CASE WHEN transaction_type = 0 THEN 1 END) as credit_count,
        COUNT(CASE WHEN transaction_type = 1 THEN 1 END) as debit_count
      FROM transactions
      WHERE $where
    ''', args);

    if (result.isNotEmpty) {
      final row = result.first;
      final credits = Decimal.parse((row['total_credits'] ?? 0).toString());
      final debits = Decimal.parse((row['total_debits'] ?? 0).toString());

      return TransactionSummary(
        totalCredits: credits,
        totalDebits: debits,
        netBalance: credits - debits,
        creditCount: row['credit_count'] as int? ?? 0,
        debitCount: row['debit_count'] as int? ?? 0,
        periodStart: startDate,
        periodEnd: endDate,
      );
    }

    return TransactionSummary.empty();
  }

  /// Get today's transactions
  Future<List<Transaction>> getTodayTransactions() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return await getRecentTransactions(
      startDate: startOfDay,
      endDate: endOfDay,
    );
  }

  /// Delete a transaction (soft delete)
  Future<void> deleteTransaction(int transactionId) async {
    final db = await _databaseService.database;
    await db.update(
      'transactions',
      {
        'is_active': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  /// Permanently delete a transaction (hard delete)
  Future<void> permanentlyDeleteTransaction(int transactionId) async {
    final db = await _databaseService.database;
    await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  /// Permanently delete all transactions for a specific month and year
  Future<int> deleteTransactionsByMonthYear(int year, int month) async {
    await ensureTransactionTable();
    final db = await _databaseService.database;

    // Calculate start and end of month
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);

    final count = await db.delete(
      'transactions',
      where: 'transaction_date >= ? AND transaction_date <= ?',
      whereArgs: [
        startOfMonth.toIso8601String(),
        endOfMonth.toIso8601String(),
      ],
    );

    return count;
  }

  /// Get count of transactions for a specific month and year
  Future<int> getTransactionCountByMonthYear(int year, int month) async {
    await ensureTransactionTable();
    final db = await _databaseService.database;

    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM transactions WHERE transaction_date >= ? AND transaction_date <= ?',
      [startOfMonth.toIso8601String(), endOfMonth.toIso8601String()],
    );

    return result.isNotEmpty ? (result.first['count'] as int? ?? 0) : 0;
  }

  /// Sync transactions from existing payments and loans
  Future<void> syncFromExistingData() async {
    await ensureTransactionTable();
    final db = await _databaseService.database;

    // Get existing transaction count
    final existingCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM transactions')) ??
        0;

    if (existingCount > 0) {
      // Already synced
      return;
    }

    // Sync loans as debit transactions
    final loans = await db.rawQuery('''
      SELECT l.*, c.name as customer_name
      FROM loans l
      INNER JOIN customers c ON l.customer_id = c.id
      WHERE l.is_active = 1
      ORDER BY l.loan_date ASC
    ''');

    for (final loan in loans) {
      await recordDebit(
        customerId: loan['customer_id'] as int,
        loanId: loan['id'] as int,
        amount: Decimal.parse(loan['principal_amount'].toString()),
        description: 'Loan disbursed to ${loan['customer_name']}',
        transactionDate: DateTime.parse(loan['loan_date'] as String),
      );
    }

    // Sync payments as credit transactions
    final payments = await db.rawQuery('''
      SELECT p.*, c.name as customer_name
      FROM payments p
      INNER JOIN customers c ON p.customer_id = c.id
      WHERE p.is_active = 1
      ORDER BY p.payment_date ASC
    ''');

    for (final payment in payments) {
      await recordCredit(
        customerId: payment['customer_id'] as int,
        loanId: payment['loan_id'] as int?,
        amount: Decimal.parse(payment['amount'].toString()),
        description: 'Payment from ${payment['customer_name']}',
        transactionDate: DateTime.parse(payment['payment_date'] as String),
      );
    }
  }
}
