import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:decimal/decimal.dart';
import '../../shared/models/customer.dart';
import '../../shared/models/customer_group.dart';
import '../../shared/models/loan.dart';
import '../../shared/models/payment.dart';
import '../../shared/models/pagination_result.dart';

/// Database service handling SQLite operations for the app.
///
/// **Security Note (TODO)**: The database is currently unencrypted. For a financial
/// application handling sensitive customer data, consider using `sqflite_sqlcipher`
/// or similar library to encrypt data at rest. The encryption key should be stored
/// securely in the device's Keystore (Android) or Keychain (iOS).
///
/// **Architecture Note (TODO)**: This class has grown to handle multiple concerns:
/// - Database lifecycle management (init, close, backup, restore)
/// - Schema migrations (version 1-12)
/// - CRUD operations for Customers, Loans, Payments, Groups, Reminders
///
/// **Recommended Refactoring**:
/// 1. Extract a `DatabaseManager` class for lifecycle/migrations
/// 2. Create domain-specific repositories:
///    - `CustomerRepository` for customer operations
///    - `LoanRepository` for loan operations
///    - `PaymentRepository` for payment operations
///    - `ReminderRepository` for reminder operations
/// 3. Move business logic (e.g., tenure fixing, status-based sorting) to
///    a dedicated Business Logic/Service layer
///
/// This refactoring would improve maintainability and testability.
class DatabaseService {
  /// Permanently delete a customer and all related data (loans, payments)
  Future<void> deleteCustomerEntirely(int customerId) async {
    final db = await database;

    // Use transaction to ensure all deletes succeed or none do
    await db.transaction((txn) async {
      // Get all loan IDs for this customer
      final loanIdsResult = await txn.query(
        'loans',
        columns: ['id'],
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );
      final loanIds = loanIdsResult.map((row) => row['id'] as int).toList();

      // Delete all payments for these loans
      if (loanIds.isNotEmpty) {
        final loanIdPlaceholders = List.filled(loanIds.length, '?').join(',');
        await txn.delete(
          'payments',
          where: 'loan_id IN ($loanIdPlaceholders)',
          whereArgs: loanIds,
        );
      }

      // Delete all loans for this customer
      await txn.delete(
        'loans',
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );

      // Delete the customer record
      await txn.delete(
        'customers',
        where: 'id = ?',
        whereArgs: [customerId],
      );
    });
  }

  static final DatabaseService instance = DatabaseService._internal();
  static Database? _database;
  static String? _databasePath;
  static bool _schemaEnsured = false;

  /// Current database schema version. ALL version references should use this.
  static const int currentVersion = 12;

  /// Detailed error message from the last failed restore operation.
  /// Callers should read this when `restoreFromFile()` returns false.
  String? _lastRestoreError;
  String? get lastRestoreError => _lastRestoreError;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) {
      // If database exists but schema not ensured, ensure it now
      if (!_schemaEnsured) {
        await _ensureAllSchemas();
      }
      return _database!;
    }
    _database = await _initializeDatabase();
    await _ensureAllSchemas();
    return _database!;
  }

  /// Ensure all table schemas exist - called on first database access
  /// Uses _database! directly to avoid recursion through database getter
  Future<void> _ensureAllSchemas() async {
    if (_schemaEnsured) return;
    if (_database == null) return;

    try {
      final db = _database!;
      await _ensurePaymentTableSchemaWithDb(db);
      await _ensureCustomerTableSchemaWithDb(db);
      await _ensureLoanTableSchemaWithDb(db);
      await _ensureGroupMembersTableExistsWithDb(db);
      await _ensureEnterpriseIndexes(db);
      _schemaEnsured = true;
      debugPrint('All database schemas verified');
    } catch (e) {
      // Set flag to true even on error to prevent infinite retry loop
      // The app can still function with partial schema - individual operations will fail gracefully
      _schemaEnsured = true;
      debugPrint('Error ensuring schemas: ${e.runtimeType}');
    }
  }

  // ============================================================
  // ENTERPRISE SCALE: Constants for legendary performance
  // ============================================================
  /// Default page size for paginated queries
  static const int defaultPageSize = 50;

  /// Maximum reminders for batch operations
  static const int maxReminders = 1000;

  /// ENTERPRISE SCALE: Create indexes for 3000+ records performance
  Future<void> _ensureEnterpriseIndexes(Database db) async {
    try {
      // Loan table indexes for fast queries
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loans_customer ON loans(customer_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loans_status ON loans(status)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loans_due_date ON loans(due_date)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loans_active ON loans(is_active)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loans_book_no ON loans(book_no)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loans_combined ON loans(is_active, status, due_date)');

      // Customer table indexes
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone_number)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_customers_active ON customers(is_active)');

      // Payment table indexes
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_payments_loan ON payments(loan_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_payments_active ON payments(is_active)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_payments_customer ON payments(customer_id)');

      // LEGENDARY SCALE: Reminder composite index for 1000+ tasks
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_reminders_combined ON reminders(is_active, is_completed, scheduled_date)');

      debugPrint('⚡ Enterprise indexes verified (legendary scale)');
    } catch (e) {
      debugPrint('Error creating enterprise indexes: $e');
    }
  }

  /// Get the database file path
  Future<String> getDatabasePath() async {
    if (_databasePath != null) return _databasePath!;
    _databasePath = join(await getDatabasesPath(), 'financial_app.db');
    return _databasePath!;
  }

  /// Create a safe copy of the database file for backup purposes.
  /// This uses SQLite's backup mechanism to avoid corrupting active database.
  /// Returns the path to the temporary copy.
  /// Throws an exception with details if copy failed.
  Future<String> createSafeCopy() async {
    final dbPath = await getDatabasePath();
    final sourceFile = File(dbPath);
    
    if (!await sourceFile.exists()) {
      throw Exception('Database file does not exist at: $dbPath');
    }

    final tempDir = await getTemporaryDirectory();
    final tempPath = join(tempDir.path,
        'backup_copy_${DateTime.now().millisecondsSinceEpoch}.db');

    // Flush WAL to main database file before copying
    // Use rawQuery for PRAGMA commands (execute() doesn't support them in sqflite)
    final db = await database;
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');

    // Copy the database file
    await sourceFile.copy(tempPath);
    
    // Verify the copy was created
    final copiedFile = File(tempPath);
    if (!await copiedFile.exists()) {
      throw Exception('Failed to create copy at: $tempPath');
    }
    
    return tempPath;
  }

  /// Clear and recreate the entire database - FOR TESTING/DEVELOPMENT ONLY
  Future<void> recreateDatabase() async {
    final path = await getDatabasePath();
    await deleteDatabase(path);
    _database = null;
    _schemaEnsured = false; // Reset flag so schema is verified for new database
    _database = await _initializeDatabase();
  }

  /// Force database schema update - useful for fixing migration issues
  Future<void> forceSchemaUpdate() async {
    await database; // Ensure database is initialized
    try {
      // Ensure all required columns exist
      await _ensurePaymentTableSchema();
      debugPrint('Database schema updated successfully');
    } catch (e) {
      debugPrint('Error updating database schema: $e');
    }
  }

  Future<Database> _initializeDatabase() async {
    String path = await getDatabasePath();

    return await openDatabase(
      path,
      version: currentVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> initializeDatabase() async {
    await database;
    await _ensurePaymentTableSchema();
    await _ensureCustomerTableSchema();
    await _ensureLoanTableSchema();
    await _ensureGroupMembersTableExists();
  }

  /// Ensure customer_group_members junction table exists (for multi-group support)
  Future<void> _ensureGroupMembersTableExists() async {
    final db = await database;
    await _ensureGroupMembersTableExistsWithDb(db);
  }

  /// WithDb version - takes database directly to avoid recursion
  Future<void> _ensureGroupMembersTableExistsWithDb(Database db) async {
    try {
      // Check if table exists
      final result = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='customer_group_members'");

      if (result.isEmpty) {
        debugPrint(
            'Creating customer_group_members table for multi-group support');

        // Create junction table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS customer_group_members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER NOT NULL,
            group_id INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE,
            FOREIGN KEY (group_id) REFERENCES customer_groups (id) ON DELETE CASCADE,
            UNIQUE(customer_id, group_id)
          )
        ''');

        // Create indexes
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_cgm_customer ON customer_group_members(customer_id)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_cgm_group ON customer_group_members(group_id)');

        // Migrate existing group_id data to junction table
        await db.execute('''
          INSERT OR IGNORE INTO customer_group_members (customer_id, group_id, created_at)
          SELECT id, group_id, datetime('now')
          FROM customers
          WHERE group_id IS NOT NULL AND is_active = 1
        ''');

        debugPrint('customer_group_members table created successfully');
      }
    } catch (e) {
      debugPrint('Error ensuring customer_group_members table: $e');
    }
  }

  /// WithDb version of payment table schema check
  Future<void> _ensurePaymentTableSchemaWithDb(Database db) async {
    try {
      final result = await db.rawQuery('PRAGMA table_info(payments)');
      final columns = result.map((row) => row['name'].toString()).toList();

      if (!columns.contains('payment_method')) {
        debugPrint('Adding missing payment_method column');
        await db.execute(
            'ALTER TABLE payments ADD COLUMN payment_method INTEGER NOT NULL DEFAULT 0');
      }
    } catch (e) {
      debugPrint('Error checking/updating payment table schema: $e');
    }
  }

  /// WithDb version of customer table schema check
  Future<void> _ensureCustomerTableSchemaWithDb(Database db) async {
    try {
      final result = await db.rawQuery('PRAGMA table_info(customers)');
      final columns = result.map((row) => row['name'].toString()).toList();

      if (!columns.contains('latitude')) {
        debugPrint('Adding missing latitude column to customers');
        await db.execute('ALTER TABLE customers ADD COLUMN latitude REAL');
      }
      if (!columns.contains('longitude')) {
        debugPrint('Adding missing longitude column to customers');
        await db.execute('ALTER TABLE customers ADD COLUMN longitude REAL');
      }
    } catch (e) {
      debugPrint('Error checking/updating customer table schema: $e');
    }
  }

  /// WithDb version of loan table schema check
  Future<void> _ensureLoanTableSchemaWithDb(Database db) async {
    try {
      final result = await db.rawQuery('PRAGMA table_info(loans)');
      final columns = result.map((row) => row['name'].toString()).toList();

      if (!columns.contains('loan_type')) {
        debugPrint('Adding missing loan_type column to loans');
        await db.execute(
            'ALTER TABLE loans ADD COLUMN loan_type INTEGER NOT NULL DEFAULT 0');
      }
      if (!columns.contains('monthly_interest_amount')) {
        debugPrint('Adding missing monthly_interest_amount column to loans');
        await db.execute(
            'ALTER TABLE loans ADD COLUMN monthly_interest_amount TEXT');
      }
      if (!columns.contains('total_interest_collected')) {
        debugPrint('Adding missing total_interest_collected column to loans');
        await db.execute(
            'ALTER TABLE loans ADD COLUMN total_interest_collected TEXT');
      }
    } catch (e) {
      debugPrint('Error checking/updating loans table schema: $e');
    }
  }

  /// Ensure payment table has all required columns
  Future<void> _ensurePaymentTableSchema() async {
    final db = await database;

    try {
      // Check if payment_method column exists
      final result = await db.rawQuery('PRAGMA table_info(payments)');
      final columns = result.map((row) => row['name'].toString()).toList();

      if (!columns.contains('payment_method')) {
        debugPrint('Adding missing payment_method column');
        await db.execute(
            'ALTER TABLE payments ADD COLUMN payment_method INTEGER NOT NULL DEFAULT 0');
      }
    } catch (e) {
      debugPrint('Error checking/updating payment table schema: $e');
    }
  }

  /// Ensure customer table has latitude/longitude columns for location feature
  Future<void> _ensureCustomerTableSchema() async {
    final db = await database;

    try {
      final result = await db.rawQuery('PRAGMA table_info(customers)');
      final columns = result.map((row) => row['name'].toString()).toList();

      if (!columns.contains('latitude')) {
        debugPrint('Adding missing latitude column to customers');
        await db.execute('ALTER TABLE customers ADD COLUMN latitude REAL');
      }
      if (!columns.contains('longitude')) {
        debugPrint('Adding missing longitude column to customers');
        await db.execute('ALTER TABLE customers ADD COLUMN longitude REAL');
      }
    } catch (e) {
      debugPrint('Error checking/updating customer table schema: $e');
    }
  }

  /// Ensure loans table has monthly interest loan columns
  Future<void> _ensureLoanTableSchema() async {
    final db = await database;

    try {
      final result = await db.rawQuery('PRAGMA table_info(loans)');
      final columns = result.map((row) => row['name'].toString()).toList();

      if (!columns.contains('loan_type')) {
        debugPrint('Adding missing loan_type column to loans');
        await db.execute(
            'ALTER TABLE loans ADD COLUMN loan_type INTEGER NOT NULL DEFAULT 0');
      }
      if (!columns.contains('monthly_interest_amount')) {
        debugPrint('Adding missing monthly_interest_amount column to loans');
        await db.execute(
            'ALTER TABLE loans ADD COLUMN monthly_interest_amount TEXT');
      }
      if (!columns.contains('total_interest_collected')) {
        debugPrint('Adding missing total_interest_collected column to loans');
        await db.execute(
            'ALTER TABLE loans ADD COLUMN total_interest_collected TEXT');
      }
    } catch (e) {
      debugPrint('Error checking/updating loans table schema: $e');
    }
  }

  Future<void> _createTables(Database db, int version) async {
    // Create customer_groups table
    await db.execute('''
      CREATE TABLE customer_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Create customers table (phone_number is NOT unique to allow same person multiple loans)
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        alternate_phone TEXT,
        address TEXT,
        book_no TEXT,
        pan_number TEXT,
        group_id INTEGER,
        latitude REAL,
        longitude REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (group_id) REFERENCES customer_groups (id) ON DELETE SET NULL
      )
    ''');

    // Create loans table
    await db.execute('''
      CREATE TABLE loans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        principal_amount TEXT NOT NULL,
        book_no TEXT,
        loan_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        total_amount TEXT NOT NULL,
        paid_amount TEXT NOT NULL DEFAULT '0',
        remaining_amount TEXT NOT NULL,
        status INTEGER NOT NULL DEFAULT 0,
        last_payment_date TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        tenure INTEGER NOT NULL DEFAULT 10,
        penalty_rate TEXT,
        loan_type INTEGER NOT NULL DEFAULT 0,
        monthly_interest_amount TEXT,
        total_interest_collected TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');

    // Create payments table
    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id INTEGER NOT NULL,
        customer_id INTEGER NOT NULL,
        amount TEXT NOT NULL,
        payment_date TEXT NOT NULL,
        payment_type INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        receipt_number TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE CASCADE,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');

    // Create audit log table
    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        old_values TEXT,
        new_values TEXT,
        user_id TEXT,
        timestamp TEXT NOT NULL
      )
    ''');

    // Create settings table
    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL UNIQUE,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Create reminders table
    await db.execute('''
      CREATE TABLE reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id INTEGER,
        customer_id INTEGER,
        notification_id INTEGER,
        type INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        scheduled_date TEXT NOT NULL,
        recurrence_pattern INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE CASCADE,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for performance
    await db
        .execute('CREATE INDEX idx_customers_phone ON customers(phone_number)');
    await db.execute(
        'CREATE INDEX idx_customers_name ON customers(name COLLATE NOCASE)');
    await db.execute(
        'CREATE INDEX idx_customers_search ON customers(name COLLATE NOCASE, phone_number)');
    await db.execute('CREATE INDEX idx_loans_customer ON loans(customer_id)');
    await db.execute('CREATE INDEX idx_loans_status ON loans(status)');
    await db.execute('CREATE INDEX idx_loans_due_date ON loans(due_date)');
    await db.execute(
        'CREATE INDEX idx_loans_search ON loans(customer_id, status, due_date)');
    await db.execute('CREATE INDEX idx_payments_loan ON payments(loan_id)');
    await db
        .execute('CREATE INDEX idx_payments_customer ON payments(customer_id)');
    await db
        .execute('CREATE INDEX idx_payments_date ON payments(payment_date)');
    await db.execute(
        'CREATE INDEX idx_reminders_customer ON reminders(customer_id)');
    await db.execute('CREATE INDEX idx_reminders_loan ON reminders(loan_id)');
    await db.execute(
        'CREATE INDEX idx_reminders_date ON reminders(scheduled_date)');
    await db.execute(
        'CREATE INDEX idx_reminders_active ON reminders(is_active, scheduled_date)');
  }

  Future<void> _upgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades here
    if (oldVersion < 2) {
      // Migrate from version 1 to 2: Remove interest fields, add tenure field
      await db.execute('DROP TABLE IF EXISTS loans_backup');
      await db.execute('ALTER TABLE loans RENAME TO loans_backup');

      // Create new loans table with updated schema
      await db.execute('''
        CREATE TABLE loans (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          principal_amount TEXT NOT NULL,
          loan_date TEXT NOT NULL,
          due_date TEXT NOT NULL,
          total_amount TEXT NOT NULL,
          paid_amount TEXT NOT NULL DEFAULT '0',
          remaining_amount TEXT NOT NULL,
          status INTEGER NOT NULL DEFAULT 0,
          last_payment_date TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          notes TEXT,
          tenure INTEGER NOT NULL DEFAULT 10,
          penalty_rate TEXT,
          FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
        )
      ''');

      // Migrate data from old table to new table
      await db.execute('''
        INSERT INTO loans (id, customer_id, principal_amount, loan_date, due_date, 
                          total_amount, paid_amount, remaining_amount, status, 
                          last_payment_date, created_at, updated_at, is_active, 
                          notes, tenure, penalty_rate)
        SELECT id, customer_id, principal_amount, loan_date, due_date,
               total_amount, paid_amount, remaining_amount, status,
               last_payment_date, created_at, updated_at, is_active,
               notes, 10, penalty_rate
        FROM loans_backup
      ''');

      // Drop backup table
      await db.execute('DROP TABLE loans_backup');
    }

    // Version 3: Add alternate_phone column to customers
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE customers ADD COLUMN alternate_phone TEXT');
    }

    // Version 4: Add payment_method column to payments
    if (oldVersion < 4) {
      await db.execute(
          'ALTER TABLE payments ADD COLUMN payment_method INTEGER NOT NULL DEFAULT 0');
    }

    // Version 5: Add customer_groups table and group_id to customers
    if (oldVersion < 5) {
      // Create customer_groups table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS customer_groups (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          color_value INTEGER NOT NULL,
          description TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1
        )
      ''');

      // Add group_id column to customers
      await db.execute('ALTER TABLE customers ADD COLUMN group_id INTEGER');
    }

    // Version 6: Add reminders table and enhanced indexes
    if (oldVersion < 6) {
      debugPrint(
          'Upgrading database to version 6: Adding reminders and enhanced indexes');

      // Create reminders table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS reminders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          loan_id INTEGER,
          customer_id INTEGER,
          type INTEGER NOT NULL,
          title TEXT NOT NULL,
          description TEXT,
          scheduled_date TEXT NOT NULL,
          recurrence_pattern INTEGER NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1,
          is_completed INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE CASCADE,
          FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
        )
      ''');

      // Add enhanced indexes for better performance (use IF NOT EXISTS to avoid errors)
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_customers_name_collate ON customers(name COLLATE NOCASE)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_customers_search_enhanced ON customers(name COLLATE NOCASE, phone_number)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loans_search_enhanced ON loans(customer_id, status, due_date)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_payments_date_enhanced ON payments(payment_date)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_reminders_customer ON reminders(customer_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_reminders_loan ON reminders(loan_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_reminders_date ON reminders(scheduled_date)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_reminders_active ON reminders(is_active, scheduled_date)');

      debugPrint('Database successfully upgraded to version 6');
    }

    // Version 7: Rename aadhar_number column to book_no
    if (oldVersion < 7) {
      debugPrint(
          'Upgrading database to version 7: Renaming aadhar_number to book_no');

      // SQLite doesn't support direct column rename before version 3.25.0
      // So we need to create a new table, copy data, and rename
      await db.execute('DROP TABLE IF EXISTS customers_backup');
      await db.execute('ALTER TABLE customers RENAME TO customers_backup');

      // Create new customers table with book_no column
      // Note: phone_number is NOT UNIQUE to allow same person with multiple loans
      await db.execute('''
        CREATE TABLE customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone_number TEXT NOT NULL,
          alternate_phone TEXT,
          address TEXT,
          book_no TEXT,
          pan_number TEXT,
          group_id INTEGER,
          latitude REAL,
          longitude REAL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          FOREIGN KEY (group_id) REFERENCES customer_groups (id) ON DELETE SET NULL
        )
      ''');

      // Copy data from backup table (map aadhar_number to book_no)
      await db.execute('''
        INSERT INTO customers (id, name, phone_number, alternate_phone, address, book_no, pan_number, group_id, created_at, updated_at, is_active)
        SELECT id, name, phone_number, alternate_phone, address, aadhar_number, pan_number, group_id, created_at, updated_at, is_active
        FROM customers_backup
      ''');

      // Drop backup table
      await db.execute('DROP TABLE customers_backup');

      // Recreate indexes
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_customers_name_collate ON customers(name COLLATE NOCASE)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_customers_search_enhanced ON customers(name COLLATE NOCASE, phone_number)');

      debugPrint('Database successfully upgraded to version 7');
    }

    // Version 8: Add monthly interest loan fields
    if (oldVersion < 8) {
      debugPrint(
          'Upgrading database to version 8: Adding monthly interest loan fields');

      // Add loan_type column (0 = weekly, 1 = monthlyInterest)
      await db.execute(
          'ALTER TABLE loans ADD COLUMN loan_type INTEGER NOT NULL DEFAULT 0');

      // Add monthly_interest_amount column (manually entered monthly interest)
      await db
          .execute('ALTER TABLE loans ADD COLUMN monthly_interest_amount TEXT');

      // Add total_interest_collected column (track total interest collected)
      await db.execute(
          'ALTER TABLE loans ADD COLUMN total_interest_collected TEXT');

      debugPrint('Database successfully upgraded to version 8');
    }

    // Version 9: Add location fields to customers table
    if (oldVersion < 9) {
      debugPrint(
          'Upgrading database to version 9: Adding location fields to customers');

      // Check if columns already exist (V7 migration may have added them)
      final tableInfo = await db.rawQuery('PRAGMA table_info(customers)');
      final columns = tableInfo.map((row) => row['name'].toString()).toSet();

      // Add latitude and longitude columns only if they don't exist
      if (!columns.contains('latitude')) {
        await db.execute('ALTER TABLE customers ADD COLUMN latitude REAL');
      }
      if (!columns.contains('longitude')) {
        await db.execute('ALTER TABLE customers ADD COLUMN longitude REAL');
      }

      debugPrint('Database successfully upgraded to version 9');
    }

    // Version 10: Add customer_group_members junction table for multi-group support
    if (oldVersion < 10) {
      debugPrint(
          'Upgrading database to version 10: Adding multi-group support');

      // Create junction table for many-to-many relationship
      await db.execute('''
        CREATE TABLE IF NOT EXISTS customer_group_members (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          group_id INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE,
          FOREIGN KEY (group_id) REFERENCES customer_groups (id) ON DELETE CASCADE,
          UNIQUE(customer_id, group_id)
        )
      ''');

      // Create indexes for performance
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cgm_customer ON customer_group_members(customer_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cgm_group ON customer_group_members(group_id)');

      // Migrate existing group_id data to junction table
      await db.execute('''
        INSERT OR IGNORE INTO customer_group_members (customer_id, group_id, created_at)
        SELECT id, group_id, datetime('now')
        FROM customers
        WHERE group_id IS NOT NULL AND is_active = 1
      ''');

      debugPrint('Database successfully upgraded to version 10');
    }

    // Version 11: Remove UNIQUE constraint from phone_number and add book_no to loans
    if (oldVersion < 11) {
      debugPrint(
          'Upgrading database to version 11: Removing phone UNIQUE constraint and adding book_no to loans');

      // Step 1: Recreate customers table without UNIQUE constraint on phone_number
      await db.execute('DROP TABLE IF EXISTS customers_backup');
      await db.execute('ALTER TABLE customers RENAME TO customers_backup');

      // Create customers table without UNIQUE constraint
      await db.execute('''
        CREATE TABLE customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone_number TEXT NOT NULL,
          alternate_phone TEXT,
          address TEXT,
          book_no TEXT,
          pan_number TEXT,
          group_id INTEGER,
          latitude REAL,
          longitude REAL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          FOREIGN KEY (group_id) REFERENCES customer_groups (id) ON DELETE SET NULL
        )
      ''');

      // Copy data from backup
      await db.execute('''
        INSERT INTO customers (id, name, phone_number, alternate_phone, address, book_no, pan_number, group_id, latitude, longitude, created_at, updated_at, is_active)
        SELECT id, name, phone_number, alternate_phone, address, book_no, pan_number, group_id, latitude, longitude, created_at, updated_at, is_active
        FROM customers_backup
      ''');

      await db.execute('DROP TABLE customers_backup');

      // Recreate indexes
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone_number)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name COLLATE NOCASE)');

      // Step 2: Add book_no column to loans table
      await db.execute('ALTER TABLE loans ADD COLUMN book_no TEXT');

      // Create index for book_no search
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loans_book_no ON loans(book_no)');

      debugPrint('Database successfully upgraded to version 11');
    }

    // Version 12: Add notification_id column to reminders for reliable tracking
    if (oldVersion < 12) {
      debugPrint(
          'Upgrading database to version 12: Adding notification_id to reminders');

      await db
          .execute('ALTER TABLE reminders ADD COLUMN notification_id INTEGER');

      debugPrint('Database successfully upgraded to version 12');
    }
  }

  // Customer operations
  Future<int> insertCustomer(Customer customer) async {
    final db = await database;
    final map = customer.toMap();
    map.remove('id'); // Remove id to let SQLite auto-generate it
    return await db.insert('customers', map);
  }

  Future<List<Customer>> getAllCustomers() async {
    final db = await database;
    final maps = await db.query(
      'customers',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Customer.fromMap(map)).toList();
  }

  // Paginated customer queries
  Future<PaginationResult<Customer>> getCustomersPaginated({
    int page = 1,
    int pageSize = 20,
    String? searchQuery,
    int? groupId,
  }) async {
    final db = await database;
    final offset = (page - 1) * pageSize;

    // Build where clause
    String whereClause = 'is_active = 1';
    List<dynamic> whereArgs = [];

    if (searchQuery != null && searchQuery.isNotEmpty) {
      whereClause +=
          ' AND (LOWER(name) LIKE ? OR phone_number LIKE ? OR alternate_phone LIKE ?)';
      final searchPattern = '%${searchQuery.toLowerCase()}%';
      whereArgs.addAll([searchPattern, '%$searchQuery%', '%$searchQuery%']);
    }

    if (groupId != null) {
      whereClause += ' AND group_id = ?';
      whereArgs.add(groupId);
    }

    // Get total count
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM customers WHERE $whereClause',
      whereArgs,
    );
    final totalCount = Sqflite.firstIntValue(countResult) ?? 0;

    // Get paginated results
    final maps = await db.query(
      'customers',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'name COLLATE NOCASE ASC',
      limit: pageSize,
      offset: offset,
    );

    final customers = maps.map((map) => Customer.fromMap(map)).toList();

    return PaginationResult.fromQuery(
      items: customers,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
    );
  }

  Future<Customer?> getCustomerById(int id) async {
    final db = await database;
    final maps = await db.query(
      'customers',
      where: 'id = ? AND is_active = ?',
      whereArgs: [id, 1],
      limit: 1,
    );
    return maps.isNotEmpty ? Customer.fromMap(maps.first) : null;
  }

  Future<Customer?> getCustomerByPhone(String phoneNumber) async {
    final db = await database;
    final maps = await db.query(
      'customers',
      where: 'phone_number = ? AND is_active = ?',
      whereArgs: [phoneNumber, 1],
      limit: 1,
    );
    return maps.isNotEmpty ? Customer.fromMap(maps.first) : null;
  }

  Future<int> updateCustomer(Customer customer) async {
    final db = await database;
    return await db.update(
      'customers',
      customer.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  /// Soft delete a customer (sets is_active = 0).
  /// For permanent deletion, use [deleteCustomerEntirely].
  Future<int> softDeleteCustomer(int id) async {
    final db = await database;
    return await db.update(
      'customers',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Customer Group operations
  Future<int> insertCustomerGroup(CustomerGroup group) async {
    final db = await database;
    final map = group.toMap();
    map.remove('id');
    return await db.insert('customer_groups', map);
  }

  Future<List<CustomerGroup>> getAllCustomerGroups() async {
    final db = await database;
    final maps = await db.query(
      'customer_groups',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'name ASC',
    );
    return maps.map((map) => CustomerGroup.fromMap(map)).toList();
  }

  /// Get all customer groups with their customer counts in a single query
  /// This avoids N+1 query problem when loading groups with counts
  Future<List<Map<String, dynamic>>> getAllCustomerGroupsWithCounts() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT g.*, 
        (SELECT COUNT(DISTINCT cgm.customer_id) 
         FROM customer_group_members cgm 
         INNER JOIN customers c ON cgm.customer_id = c.id 
         WHERE cgm.group_id = g.id AND c.is_active = 1) as customer_count
      FROM customer_groups g
      WHERE g.is_active = 1
      ORDER BY g.name ASC
    ''');
    return result;
  }

  /// Search customers by name or phone with database-side filtering
  /// Use for large datasets instead of loading all customers into memory
  Future<List<Customer>> searchCustomers(String query, {int limit = 50}) async {
    final db = await database;
    final searchTerm = '%${query.toLowerCase()}%';
    final maps = await db.query(
      'customers',
      where: '(LOWER(name) LIKE ? OR phone_number LIKE ?) AND is_active = ?',
      whereArgs: [searchTerm, searchTerm, 1],
      orderBy: 'name ASC',
      limit: limit,
    );
    return maps.map((map) => Customer.fromMap(map)).toList();
  }

  /// Search customers not in a specific group
  Future<List<Customer>> searchCustomersNotInGroup(String query, int groupId,
      {int limit = 50}) async {
    final db = await database;
    final searchTerm = '%${query.toLowerCase()}%';
    final maps = await db.rawQuery('''
      SELECT c.* FROM customers c
      WHERE c.is_active = 1
        AND (LOWER(c.name) LIKE ? OR c.phone_number LIKE ?)
        AND c.id NOT IN (
          SELECT customer_id FROM customer_group_members WHERE group_id = ?
        )
      ORDER BY c.name ASC
      LIMIT ?
    ''', [searchTerm, searchTerm, groupId, limit]);
    return maps.map((map) => Customer.fromMap(map)).toList();
  }

  Future<CustomerGroup?> getCustomerGroupById(int id) async {
    final db = await database;
    final maps = await db.query(
      'customer_groups',
      where: 'id = ? AND is_active = ?',
      whereArgs: [id, 1],
      limit: 1,
    );
    return maps.isNotEmpty ? CustomerGroup.fromMap(maps.first) : null;
  }

  Future<int> updateCustomerGroup(CustomerGroup group) async {
    final db = await database;
    return await db.update(
      'customer_groups',
      group.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [group.id],
    );
  }

  Future<int> deleteCustomerGroup(int id) async {
    final db = await database;
    // First, set group_id to null for all customers in this group
    await db.update(
      'customers',
      {'group_id': null, 'updated_at': DateTime.now().toIso8601String()},
      where: 'group_id = ?',
      whereArgs: [id],
    );
    // Then soft delete the group
    return await db.update(
      'customer_groups',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getCustomerCountInGroup(int groupId) async {
    final db = await database;
    // Query junction table for accurate multi-group count
    final result = await db.rawQuery('''
      SELECT COUNT(DISTINCT cgm.customer_id) as count 
      FROM customer_group_members cgm
      INNER JOIN customers c ON cgm.customer_id = c.id
      WHERE cgm.group_id = ? AND c.is_active = 1
    ''', [groupId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Customer>> getCustomersByGroup(int? groupId) async {
    final db = await database;
    if (groupId == null) {
      // Get all customers
      return getAllCustomers();
    }
    final maps = await db.query(
      'customers',
      where: 'group_id = ? AND is_active = ?',
      whereArgs: [groupId, 1],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Customer.fromMap(map)).toList();
  }

  /// Assign customer to a single group (updates both legacy column and junction table)
  Future<int> assignCustomerToGroup(int customerId, int? groupId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    return await db.transaction((txn) async {
      // Update legacy group_id column
      final result = await txn.update(
        'customers',
        {'group_id': groupId, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [customerId],
      );

      // Also update junction table to keep in sync
      await txn.delete(
        'customer_group_members',
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );
      if (groupId != null) {
        await txn.insert('customer_group_members', {
          'customer_id': customerId,
          'group_id': groupId,
          'created_at': now,
        });
      }

      return result;
    });
  }

  /// Add customer to multiple groups using junction table
  /// Note: Uses individual inserts within a transaction. For typical use cases
  /// (1-5 groups per customer), this overhead is negligible. For bulk operations
  /// with many groups, consider using rawInsert with VALUES clause.
  Future<void> addCustomerToMultipleGroups(
      int customerId, List<int> groupIds) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      // Clear existing memberships for this customer
      await txn.delete(
        'customer_group_members',
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );
      // Add new memberships
      for (final groupId in groupIds) {
        await txn.insert('customer_group_members', {
          'customer_id': customerId,
          'group_id': groupId,
          'created_at': now,
        });
      }
      // Also update legacy group_id to first group (for backward compatibility)
      await txn.update(
        'customers',
        {
          'group_id': groupIds.isNotEmpty ? groupIds.first : null,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );
    });
  }

  /// Get all group IDs for a customer
  Future<List<int>> getCustomerGroupIds(int customerId) async {
    final db = await database;
    final maps = await db.query(
      'customer_group_members',
      columns: ['group_id'],
      where: 'customer_id = ?',
      whereArgs: [customerId],
    );
    return maps.map((m) => m['group_id'] as int).toList();
  }

  // Loan operations
  Future<int> insertLoan(Loan loan) async {
    final db = await database;
    final map = loan.toMap();
    map.remove('id'); // Remove id to let SQLite auto-generate it
    return await db.insert('loans', map);
  }

  Future<List<Loan>> getAllLoans() async {
    final db = await database;
    final maps = await db.query(
      'loans',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'due_date ASC',
    );
    return maps.map((map) => Loan.fromMap(map)).toList();
  }

  // Paginated loan queries
  Future<PaginationResult<Loan>> getLoansPaginated({
    int page = 1,
    int pageSize = 20,
    String? searchQuery,
    int? customerId,
    int? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;
    final offset = (page - 1) * pageSize;

    // Build where clause
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
      whereArgs
          .addAll([searchPattern, searchPattern, searchPattern, searchPattern]);
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
  }

  Future<List<Map<String, dynamic>>> getLoansWithCustomers() async {
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
  }

  Future<List<Loan>> getLoansByCustomer(int customerId) async {
    final db = await database;
    final maps = await db.query(
      'loans',
      where: 'customer_id = ? AND is_active = ?',
      whereArgs: [customerId, 1],
      orderBy: 'loan_date DESC',
    );
    return maps.map((map) => Loan.fromMap(map)).toList();
  }

  Future<int> updateLoan(Loan loan) async {
    final db = await database;
    return await db.update(
      'loans',
      loan.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [loan.id],
    );
  }

  // Dashboard statistics
  /// Helper to safely parse a SQL SUM result to Decimal.
  /// Handles null, numeric, and string types to avoid precision loss.
  Decimal _parseSumResult(dynamic value) {
    if (value == null) return Decimal.zero;
    if (value is String) {
      return Decimal.tryParse(value) ?? Decimal.zero;
    }
    if (value is int) {
      return Decimal.fromInt(value);
    }
    if (value is double) {
      return Decimal.tryParse(value.toStringAsFixed(2)) ?? Decimal.zero;
    }
    return Decimal.tryParse(value.toString()) ?? Decimal.zero;
  }

  Future<Map<String, Decimal>> getDashboardStats() async {
    final db = await database;

    // Sum values precisely in Dart to avoid floating-point precision loss
    // Total given (all active loans) - sum principal_amount as TEXT
    final totalGivenRows = await db.rawQuery(
        'SELECT principal_amount FROM loans WHERE is_active = 1');
    Decimal totalGiven = Decimal.zero;
    for (final row in totalGivenRows) {
      final value = row['principal_amount'];
      if (value != null) {
        totalGiven += Decimal.tryParse(value.toString()) ?? Decimal.zero;
      }
    }

    // Total received (all payments) - sum amount as TEXT
    final totalReceivedRows = await db.rawQuery(
        'SELECT amount FROM payments WHERE is_active = 1');
    Decimal totalReceived = Decimal.zero;
    for (final row in totalReceivedRows) {
      final value = row['amount'];
      if (value != null) {
        totalReceived += Decimal.tryParse(value.toString()) ?? Decimal.zero;
      }
    }

    // Outstanding (remaining amount from active loans) - sum remaining_amount as TEXT
    final outstandingRows = await db.rawQuery(
        'SELECT remaining_amount FROM loans WHERE is_active = 1 AND status IN (0, 1)');
    Decimal outstanding = Decimal.zero;
    for (final row in outstandingRows) {
      final value = row['remaining_amount'];
      if (value != null) {
        outstanding += Decimal.tryParse(value.toString()) ?? Decimal.zero;
      }
    }

    // Today's collection - still use SUM since daily values are small
    final todayCollectionResult = await db.rawQuery(
        'SELECT COALESCE(SUM(CAST(amount AS REAL)), 0) as total FROM payments WHERE date(payment_date) = date("now") AND is_active = 1');
    final todayCollection =
        _parseSumResult(todayCollectionResult.first['total']);

    return {
      'totalGiven': totalGiven,
      'totalReceived': totalReceived,
      'outstanding': outstanding,
      'todayCollection': todayCollection,
    };
  }

  // Backup and restore
  /// Exports ALL data (including soft-deleted records) as JSON string.
  /// This ensures a complete backup that preserves the full database state.
  /// **Memory Note**: For large datasets (thousands of records), this loads
  /// all data into memory. Use [exportDataChunked] for streaming export.
  Future<String> exportData() async {
    final db = await database;

    // Export ALL records (including soft-deleted) for complete backup
    final customers = await db.query('customers');
    final loans = await db.query('loans');
    final payments = await db.query('payments');

    return jsonEncode({
      'customers': customers,
      'loans': loans,
      'payments': payments,
      'exportDate': DateTime.now().toIso8601String(),
    });
  }

  /// Exports data in chunks to a file to avoid memory issues with large datasets.
  /// Returns the path to the exported file.
  Future<String> exportDataChunked(String filePath) async {
    final db = await database;
    final file = File(filePath);
    final sink = file.openWrite();
    const chunkSize = 500;

    try {
      sink.write('{"exportDate":"${DateTime.now().toIso8601String()}",');

      // Export customers in chunks (ALL records for complete backup)
      sink.write('"customers":[');
      int offset = 0;
      bool firstCustomer = true;
      while (true) {
        final chunk = await db.query('customers',
            limit: chunkSize, offset: offset);
        if (chunk.isEmpty) break;
        for (final row in chunk) {
          if (!firstCustomer) sink.write(',');
          sink.write(jsonEncode(row));
          firstCustomer = false;
        }
        offset += chunkSize;
      }
      sink.write('],');

      // Export loans in chunks
      sink.write('"loans":[');
      offset = 0;
      bool firstLoan = true;
      while (true) {
        final chunk = await db.query('loans',
            limit: chunkSize, offset: offset);
        if (chunk.isEmpty) break;
        for (final row in chunk) {
          if (!firstLoan) sink.write(',');
          sink.write(jsonEncode(row));
          firstLoan = false;
        }
        offset += chunkSize;
      }
      sink.write('],');

      // Export payments in chunks
      sink.write('"payments":[');
      offset = 0;
      bool firstPayment = true;
      while (true) {
        final chunk = await db.query('payments',
            limit: chunkSize, offset: offset);
        if (chunk.isEmpty) break;
        for (final row in chunk) {
          if (!firstPayment) sink.write(',');
          sink.write(jsonEncode(row));
          firstPayment = false;
        }
        offset += chunkSize;
      }
      sink.write(']}');

      await sink.flush();
      return filePath;
    } finally {
      await sink.close();
    }
  }

  // Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _schemaEnsured = false; // Reset flag so schema is verified on next open
    }
  }

  /// Restore database from a backup file.
  /// Supports ALL database versions (v1 through v$currentVersion) — old versions
  /// are automatically migrated to the latest schema via _upgradeDatabase().
  ///
  /// On failure, check [lastRestoreError] for a user-friendly error message.
  Future<bool> restoreFromFile(String backupPath) async {
    _lastRestoreError = null;
    String? safetyBackupPath;

    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        _lastRestoreError = 'Backup file not found.';
        debugPrint('Restore: backup file does not exist');
        return false;
      }

      // Step 1: Validate SQLite magic header before touching live DB
      if (!await _isValidSqliteFile(backupPath)) {
        _lastRestoreError = 'This file is not a valid database backup.';
        debugPrint('Restore: file is not a valid SQLite database');
        return false;
      }

      // Step 2: Check backup version
      final backupVersion = await _readDatabaseVersion(backupPath);
      if (backupVersion > currentVersion) {
        _lastRestoreError =
            'This backup was created by a newer version of the app '
            '(database v$backupVersion). Please update the app to the latest '
            'version and try again.';
        debugPrint(
            'Restore: backup version $backupVersion is newer than app ($currentVersion).');
        return false;
      }
      if (backupVersion < 1) {
        _lastRestoreError =
            'This backup file has an invalid database version ($backupVersion). '
            'The file may be corrupted.';
        debugPrint('Restore: invalid backup version $backupVersion');
        return false;
      }

      debugPrint('Restore: backup version $backupVersion → will migrate to v$currentVersion');

      // Step 3: Close current database
      await close();

      final dbPath = await getDatabasePath();

      // Step 4: Create safety backup of current DB before replacing
      final currentDb = File(dbPath);
      if (await currentDb.exists()) {
        final tempDir = await getTemporaryDirectory();
        safetyBackupPath = join(tempDir.path,
            'safety_backup_${DateTime.now().millisecondsSinceEpoch}.db');
        await currentDb.copy(safetyBackupPath);
        debugPrint('Safety backup created before restore');
      }

      // Step 5: Delete stale WAL/SHM files — they belong to the old DB and
      // must not be merged into the restored database.
      await _deleteWalFiles(dbPath);

      // Step 6: Copy the backup file over the current database
      await backupFile.copy(dbPath);

      // Step 7: Delete any WAL/SHM companions the backup file might have brought
      await _deleteWalFiles(dbPath);

      // Step 8: Reopen database — this triggers _upgradeDatabase() automatically
      // when the backup has an older version than our current version.
      _schemaEnsured = false;
      _database = await _initializeDatabase();

      // Step 9: Run schema checks to add any missing columns
      await _ensureAllSchemas();

      debugPrint('Database restored and migrated successfully (v$backupVersion → v$currentVersion)');

      // Step 10: Clean up safety backup on success
      if (safetyBackupPath != null) {
        try {
          await File(safetyBackupPath).delete();
        } catch (_) {}
      }

      return true;
    } catch (e) {
      // Restore failed — try to rollback to safety backup
      _lastRestoreError = 'Restore failed: ${e.toString().split(':').last.trim()}';
      debugPrint('Restore error: $e (${e.runtimeType})');

      if (safetyBackupPath != null) {
        try {
          final dbPath = await getDatabasePath();
          await _deleteWalFiles(dbPath);
          await File(safetyBackupPath).copy(dbPath);
          _schemaEnsured = false;
          _database = await _initializeDatabase();
          debugPrint('Rolled back to safety backup after restore failure');
        } catch (rollbackError) {
          debugPrint('CRITICAL: Rollback also failed: $rollbackError');
          _lastRestoreError =
              'Restore failed and rollback also failed. '
              'Please reinstall the app and restore from Google Drive.';
        }
      }

      return false;
    }
  }

  /// Delete SQLite WAL and SHM companion files if they exist.
  Future<void> _deleteWalFiles(String dbPath) async {
    for (final suffix in ['-wal', '-shm']) {
      try {
        final f = File('$dbPath$suffix');
        if (await f.exists()) {
          await f.delete();
          debugPrint('Deleted stale $suffix file');
        }
      } catch (_) {}
    }
  }

  /// Check whether a file starts with the SQLite magic header bytes.
  Future<bool> _isValidSqliteFile(String path) async {
    try {
      final file = File(path);
      final bytes = await file.openRead(0, 16).first;
      // SQLite files start with "SQLite format 3\000"
      const magic = [83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];
      if (bytes.length < 16) return false;
      for (int i = 0; i < 16; i++) {
        if (bytes[i] != magic[i]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Read the user_version pragma from a SQLite file without migrating it.
  Future<int> _readDatabaseVersion(String path) async {
    try {
      final db = await openDatabase(path, readOnly: true);
      final version = await db.getVersion();
      await db.close();
      return version;
    } catch (_) {
      return -1;
    }
  }

  /// Get count of active customers
  Future<int> getCustomerCount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM customers WHERE is_active = 1');
    return result.first['count'] as int;
  }

  /// Get count of loans that are not cancelled or closed
  Future<int> getLoanCount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM loans WHERE status NOT IN (?, ?)',
        [LoanStatus.cancelled.index, LoanStatus.closed.index]);
    return result.first['count'] as int;
  }

  /// Get count of active payments (fast count query for telemetry)
  Future<int> getPaymentCount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM payments WHERE is_active = 1');
    return result.first['count'] as int? ?? 0;
  }

  // ============================================================
  // TELEMETRY AGGREGATES - For admin dashboard statistics
  // ============================================================

  /// Get count of active loans (status = active or overdue)
  Future<int> getActiveLoanCount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM loans WHERE is_active = 1 AND status IN (?, ?)',
        [LoanStatus.active.index, LoanStatus.overdue.index]);
    return result.first['count'] as int? ?? 0;
  }

  /// Get count of overdue loans
  Future<int> getOverdueLoanCount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM loans WHERE is_active = 1 AND status = ?',
        [LoanStatus.overdue.index]);
    return result.first['count'] as int? ?? 0;
  }

  /// Get total principal outstanding (remaining principal on active loans)
  Future<Decimal> getTotalPrincipalOutstanding() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT remaining_amount FROM loans WHERE is_active = 1 AND status IN (?, ?)',
        [LoanStatus.active.index, LoanStatus.overdue.index]);
    
    Decimal total = Decimal.zero;
    for (final row in rows) {
      final value = row['remaining_amount'];
      if (value != null) {
        total += Decimal.tryParse(value.toString()) ?? Decimal.zero;
      }
    }
    return total;
  }

  /// Get total interest outstanding (for monthly interest loans)
  Future<Decimal> getTotalInterestOutstanding() async {
    final db = await database;
    // For monthly interest loans, calculate unpaid interest based on loan duration
    // For regular loans, interest is included in total_amount
    final rows = await db.rawQuery('''
      SELECT loan_type, monthly_interest_amount, total_amount, paid_amount, remaining_amount
      FROM loans 
      WHERE is_active = 1 AND status IN (?, ?)
    ''', [LoanStatus.active.index, LoanStatus.overdue.index]);
    
    Decimal totalInterest = Decimal.zero;
    for (final row in rows) {
      final loanType = row['loan_type'] as int? ?? 0;
      if (loanType == 1) {
        // Monthly interest loan - calculate based on monthly_interest_amount
        final monthlyInterest = Decimal.tryParse(row['monthly_interest_amount']?.toString() ?? '0') ?? Decimal.zero;
        totalInterest += monthlyInterest; // Current month's interest
      }
      // Note: For regular loans, interest is included in remaining_amount (principal + interest combined)
      // We don't separate it here as it's already accounted for in getTotalPrincipalOutstanding
    }
    return totalInterest;
  }

  /// Get total collections for the current month (bounded to exclude future months)
  Future<Decimal> getMonthlyCollectionThisMonth() async {
    final db = await database;
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfNextMonth = DateTime(now.year, now.month + 1, 1);
    
    final rows = await db.rawQuery(
        'SELECT amount FROM payments WHERE is_active = 1 AND payment_date >= ? AND payment_date < ?',
        [startOfMonth.toIso8601String().split('T')[0], startOfNextMonth.toIso8601String().split('T')[0]]);
    
    Decimal total = Decimal.zero;
    for (final row in rows) {
      final value = row['amount'];
      if (value != null) {
        total += Decimal.tryParse(value.toString()) ?? Decimal.zero;
      }
    }
    return total;
  }

  /// Get loan count breakdown by type (regular, monthly_interest, reducing)
  Future<Map<String, int>> getLoanTypeBreakdown() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT loan_type, COUNT(*) as count 
      FROM loans 
      WHERE is_active = 1 AND status IN (?, ?)
      GROUP BY loan_type
    ''', [LoanStatus.active.index, LoanStatus.overdue.index]);
    
    final breakdown = <String, int>{
      'regular': 0,
      'monthly_interest': 0,
      'reducing': 0,
    };
    
    for (final row in result) {
      final loanType = row['loan_type'] as int? ?? 0;
      final count = row['count'] as int? ?? 0;
      switch (loanType) {
        case 0:
          breakdown['regular'] = count;
          break;
        case 1:
          breakdown['monthly_interest'] = count;
          break;
        case 2:
          breakdown['reducing'] = count;
          break;
      }
    }
    return breakdown;
  }

  /// Get comprehensive telemetry stats for admin dashboard
  /// Optimized: Uses a single query with subqueries to reduce DB round-trips
  Future<Map<String, dynamic>> getTelemetryStats() async {
    final db = await database;
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];
    final startOfNextMonth = DateTime(now.year, now.month + 1, 1).toIso8601String().split('T')[0];

    // Single optimized query that fetches all stats in one DB round-trip
    final result = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM customers WHERE is_active = 1) as customerCount,
        (SELECT COUNT(*) FROM loans WHERE is_active = 1 AND status NOT IN (?, ?)) as loanCount,
        (SELECT COUNT(*) FROM loans WHERE is_active = 1 AND status IN (?, ?)) as activeLoanCount,
        (SELECT COUNT(*) FROM loans WHERE is_active = 1 AND status = ?) as overdueLoanCount,
        (SELECT COUNT(*) FROM payments WHERE is_active = 1) as paymentCount,
        (SELECT COALESCE(SUM(CAST(remaining_amount AS REAL)), 0) FROM loans WHERE is_active = 1 AND status IN (?, ?)) as totalOutstanding,
        (SELECT COALESCE(SUM(CAST(monthly_interest_amount AS REAL)), 0) FROM loans WHERE is_active = 1 AND loan_type = 1 AND status IN (?, ?)) as monthlyInterestDue,
        (SELECT COALESCE(SUM(CAST(amount AS REAL)), 0) FROM payments WHERE is_active = 1 AND payment_date >= ? AND payment_date < ?) as monthlyCollection
    ''', [
      LoanStatus.cancelled.index, LoanStatus.closed.index,        // loanCount
      LoanStatus.active.index, LoanStatus.overdue.index,           // activeLoanCount
      LoanStatus.overdue.index,                                    // overdueLoanCount
      LoanStatus.active.index, LoanStatus.overdue.index,           // totalOutstanding
      LoanStatus.active.index, LoanStatus.overdue.index,           // monthlyInterestDue
      startOfMonth, startOfNextMonth,                              // monthlyCollection (bounded)
    ]);

    final row = result.first;

    // Loan type breakdown still needs a separate group-by query (but just one)
    final loanTypeResult = await db.rawQuery('''
      SELECT loan_type, COUNT(*) as count
      FROM loans
      WHERE is_active = 1 AND status IN (?, ?)
      GROUP BY loan_type
    ''', [LoanStatus.active.index, LoanStatus.overdue.index]);

    final breakdown = <String, int>{'regular': 0, 'monthly_interest': 0, 'reducing': 0};
    for (final r in loanTypeResult) {
      final loanType = r['loan_type'] as int? ?? 0;
      final count = r['count'] as int? ?? 0;
      switch (loanType) {
        case 0: breakdown['regular'] = count; break;
        case 1: breakdown['monthly_interest'] = count; break;
        case 2: breakdown['reducing'] = count; break;
      }
    }

    return {
      'customerCount': row['customerCount'] as int? ?? 0,
      'loanCount': row['loanCount'] as int? ?? 0,
      'activeLoanCount': row['activeLoanCount'] as int? ?? 0,
      'overdueLoanCount': row['overdueLoanCount'] as int? ?? 0,
      'paymentCount': row['paymentCount'] as int? ?? 0,
      'totalOutstanding': (row['totalOutstanding'] as num?)?.toDouble() ?? 0.0,
      'monthlyInterestDue': (row['monthlyInterestDue'] as num?)?.toDouble() ?? 0.0,
      'monthlyCollectionThisMonth': (row['monthlyCollection'] as num?)?.toDouble() ?? 0.0,
      'loanTypeBreakdown': breakdown,
    };
  }

  /// Delete a loan (soft delete)
  /// This also soft-deletes all payments for this loan to maintain data consistency.
  Future<int> deleteLoan(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Use transaction to ensure both loan and payments are soft-deleted together
    return await db.transaction((txn) async {
      // Soft-delete all payments for this loan
      await txn.update(
        'payments',
        {'is_active': 0, 'updated_at': now},
        where: 'loan_id = ?',
        whereArgs: [id],
      );

      // Soft-delete the loan itself
      return await txn.update(
        'loans',
        {'is_active': 0, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // Additional methods
  Future<Loan?> getLoanById(int id) async {
    final db = await database;
    final result = await db.query(
      'loans',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isNotEmpty) {
      return Loan.fromMap(result.first);
    }
    return null;
  }

  Future<int> insertPayment(Payment payment) async {
    try {
      final db = await database;

      // Get payment data and ensure schema compatibility
      Map<String, dynamic> paymentData = payment.toMap();

      // Check if payment_method column exists
      final result = await db.rawQuery('PRAGMA table_info(payments)');
      final columns = result.map((row) => row['name'].toString()).toList();

      if (!columns.contains('payment_method')) {
        // Remove payment_method from data if column doesn't exist
        paymentData.remove('payment_method');
        debugPrint(
            'DEBUG: Removed payment_method from insert data (column does not exist)');
      }

      // Log only non-sensitive metadata (avoid PII like customer names, amounts, notes)
      debugPrint(
          'DEBUG: Database insertPayment called for loanId: ${payment.loanId}');
      final insertResult = await db.insert('payments', paymentData);
      debugPrint('DEBUG: insertPayment result ID: $insertResult');
      return insertResult;
    } catch (e) {
      // Log only error type to avoid exposing PII in exception messages
      debugPrint('DEBUG: insertPayment error type: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Get all payments for a specific loan
  Future<List<Payment>> getPaymentsForLoan(int loanId) async {
    final db = await database;
    final maps = await db.query(
      'payments',
      where: 'loan_id = ? AND is_active = 1',
      whereArgs: [loanId],
      orderBy: 'payment_date DESC',
    );
    return maps.map((map) => Payment.fromMap(map)).toList();
  }

  /// Get a single payment by ID
  Future<Payment?> getPaymentById(int paymentId) async {
    final db = await database;
    final maps = await db.query(
      'payments',
      where: 'id = ? AND is_active = 1',
      whereArgs: [paymentId],
      limit: 1,
    );
    return maps.isNotEmpty ? Payment.fromMap(maps.first) : null;
  }

  /// Update an existing payment
  Future<int> updatePayment(Payment payment) async {
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
  }

  /// Soft delete a payment (set is_active = 0)
  Future<int> deletePayment(int paymentId) async {
    final db = await database;
    return await db.update(
      'payments',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [paymentId],
    );
  }

  /// Permanently delete a payment (hard delete)
  Future<int> permanentlyDeletePayment(int paymentId) async {
    final db = await database;
    return await db.delete(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
  }

  /// Get all payments for a specific customer
  Future<List<Payment>> getPaymentsForCustomer(int customerId) async {
    final db = await database;
    final maps = await db.query(
      'payments',
      where: 'customer_id = ? AND is_active = 1',
      whereArgs: [customerId],
      orderBy: 'payment_date DESC',
    );
    return maps.map((map) => Payment.fromMap(map)).toList();
  }

  /// Get payments within a date range
  Future<List<Payment>> getPaymentsByDateRange(
      DateTime startDate, DateTime endDate) async {
    final db = await database;
    final maps = await db.query(
      'payments',
      where: 'payment_date >= ? AND payment_date <= ? AND is_active = 1',
      whereArgs: [startDate.toIso8601String(), endDate.toIso8601String()],
      orderBy: 'payment_date DESC',
    );
    return maps.map((map) => Payment.fromMap(map)).toList();
  }

  /// Get all payments
  Future<List<Payment>> getAllPayments() async {
    final db = await database;
    final maps = await db.query(
      'payments',
      where: 'is_active = 1',
      orderBy: 'payment_date DESC',
    );
    return maps.map((map) => Payment.fromMap(map)).toList();
  }

  /// Get loans with their payments loaded (for home page display)
  /// Optimized to use a single bulk query instead of N+1 individual queries
  Future<List<Loan>> getAllLoansWithPayments() async {
    final db = await database;
    // Use simple query to get all active loans - don't filter by customer join
    // The home page will handle missing customers gracefully
    final loanMaps = await db.query(
      'loans',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'due_date ASC',
    );

    if (loanMaps.isEmpty) {
      return [];
    }

    // Extract all loan IDs for bulk payment query
    final loanIds = loanMaps.map((m) => m['id'] as int).toList();

    // Batch loanIds to avoid SQLite parameter limit (max ~999 params)
    const batchSize = 900;
    final List<Map<String, dynamic>> allPayments = [];

    for (int i = 0; i < loanIds.length; i += batchSize) {
      final batch = loanIds.skip(i).take(batchSize).toList();
      final placeholders = List.filled(batch.length, '?').join(', ');

      final batchPayments = await db.rawQuery(
        'SELECT * FROM payments WHERE loan_id IN ($placeholders) AND is_active = 1',
        batch,
      );
      allPayments.addAll(batchPayments);
    }

    // Sort all payments by payment_date DESC (since we batched, need to re-sort)
    allPayments.sort((a, b) {
      final dateA = a['payment_date'] as String?;
      final dateB = b['payment_date'] as String?;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      return dateB.compareTo(dateA); // DESC order
    });

    // Group payments by loan_id in memory
    final paymentsByLoanId = <int, List<Payment>>{};
    for (final paymentMap in allPayments) {
      final payment = Payment.fromMap(paymentMap);
      final loanId = paymentMap['loan_id'] as int;
      paymentsByLoanId.putIfAbsent(loanId, () => []).add(payment);
    }

    // Build loans with their payments
    final loans = loanMaps.map((map) {
      final loan = Loan.fromMap(map);
      final payments = paymentsByLoanId[loan.id] ?? [];
      return loan.copyWith(payments: payments);
    }).toList();

    debugPrint('📋 Loaded ${loans.length} loans with payments (bulk query)');
    return loans;
  }

  /// Update all existing loans to fix tenure from 12 to 10 weeks
  /// **Business Logic Note**: This is a data correction/migration operation.
  /// Ideally, such business rules should be in a LoanService/BusinessLogic layer.
  Future<int> fixExistingLoansTenure() async {
    final db = await database;
    return await db.rawUpdate('''
      UPDATE loans 
      SET tenure = 10, updated_at = ? 
      WHERE tenure = 12 AND is_active = 1
    ''', [DateTime.now().toIso8601String()]);
  }

  /// Completely clear all data and reset database
  Future<void> clearAllDataAndReset() async {
    try {
      final db = await database;

      // Clear all tables in order (respecting foreign keys)
      await db.delete('payments');
      await db.delete('loans');
      await db.delete('customers');
      await db.delete('audit_log');
      await db.delete('settings');
      await db.delete('reminders');

      // Reset auto-increment counters
      await db.execute('DELETE FROM sqlite_sequence');

      // Vacuum to reclaim space
      await db.execute('VACUUM');

      debugPrint('Database completely cleared and reset');
    } catch (e) {
      // Log only error type to avoid exposing sensitive data
      debugPrint('Error clearing database: ${e.runtimeType}');
      rethrow;
    }
  }

  // ============================================================
  // REMINDER OPERATIONS - For atomic dismiss/snooze
  // ============================================================

  /// Update reminder scheduled time (for snooze operations)
  Future<int> updateReminderTime(int reminderId, DateTime newTime) async {
    final db = await database;
    return await db.update(
      'reminders',
      {
        'scheduled_date': newTime.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [reminderId],
    );
  }

  /// Permanently delete a reminder (hard delete for dismiss)
  Future<int> deleteReminderPermanently(int reminderId) async {
    final db = await database;
    return await db.delete(
      'reminders',
      where: 'id = ?',
      whereArgs: [reminderId],
    );
  }

  /// Clean up past reminders to save storage space
  /// Deletes completed/dismissed reminders from previous days
  Future<int> cleanupPastReminders() async {
    final db = await database;
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    // Delete reminders that are:
    // 1. Completed (is_completed = 1) OR
    // 2. Inactive (is_active = 0) AND scheduled for before today
    final deletedCount = await db.delete(
      'reminders',
      where: '''
        (is_completed = 1 AND scheduled_date < ?) OR
        (is_active = 0 AND scheduled_date < ?)
      ''',
      whereArgs: [
        startOfToday.toIso8601String(),
        startOfToday.toIso8601String(),
      ],
    );

    if (deletedCount > 0) {
      debugPrint('🧹 DatabaseService: Cleaned up $deletedCount past reminders');
    }

    return deletedCount;
  }

  /// Update reminder notification ID
  Future<int> updateReminderNotificationId(
      int reminderId, int notificationId) async {
    final db = await database;
    return await db.update(
      'reminders',
      {
        'notification_id': notificationId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [reminderId],
    );
  }

  /// Get reminder by ID
  Future<Map<String, dynamic>?> getReminderById(int reminderId) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT r.*, c.name as customer_name, c.phone_number as customer_phone
      FROM reminders r
      LEFT JOIN customers c ON r.customer_id = c.id
      WHERE r.id = ?
    ''', [reminderId]);
    return results.isNotEmpty ? results.first : null;
  }
}
