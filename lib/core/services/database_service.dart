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
      debugPrint('Error ensuring schemas: $e');
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
  /// Returns the path to the temporary copy, or null if copy failed.
  Future<String?> createSafeCopy() async {
    try {
      final dbPath = await getDatabasePath();
      final tempDir = await getTemporaryDirectory();
      final tempPath = join(tempDir.path, 'backup_copy_${DateTime.now().millisecondsSinceEpoch}.db');
      
      // Close any pending transactions by getting a checkpoint
      final db = await database;
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      
      // Copy the database file
      final sourceFile = File(dbPath);
      if (await sourceFile.exists()) {
        await sourceFile.copy(tempPath);
        return tempPath;
      }
      return null;
    } catch (e) {
      debugPrint('Error creating safe database copy: $e');
      return null;
    }
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
      version: 12,
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
      await db.execute('''
        CREATE TABLE customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone_number TEXT NOT NULL UNIQUE,
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

      // Add latitude and longitude columns for map integration
      await db.execute('ALTER TABLE customers ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE customers ADD COLUMN longitude REAL');

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

  Future<int> deleteCustomer(int id) async {
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

  Future<int> assignCustomerToGroup(int customerId, int? groupId) async {
    final db = await database;
    return await db.update(
      'customers',
      {'group_id': groupId, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  /// Add customer to multiple groups using junction table
  Future<void> addCustomerToMultipleGroups(
      int customerId, List<int> groupIds) async {
    final db = await database;
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
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      // Also update legacy group_id to first group (for backward compatibility)
      await txn.update(
        'customers',
        {
          'group_id': groupIds.isNotEmpty ? groupIds.first : null,
          'updated_at': DateTime.now().toIso8601String(),
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
  Future<Map<String, Decimal>> getDashboardStats() async {
    final db = await database;

    // Total given (all active loans)
    final totalGivenResult = await db.rawQuery(
        'SELECT SUM(CAST(principal_amount AS REAL)) as total FROM loans WHERE is_active = 1');
    final totalGiven =
        Decimal.parse((totalGivenResult.first['total'] ?? 0).toString());

    // Total received (all payments)
    final totalReceivedResult = await db.rawQuery(
        'SELECT SUM(CAST(amount AS REAL)) as total FROM payments WHERE is_active = 1');
    final totalReceived =
        Decimal.parse((totalReceivedResult.first['total'] ?? 0).toString());

    // Outstanding (remaining amount from active loans)
    final outstandingResult = await db.rawQuery(
        'SELECT SUM(CAST(remaining_amount AS REAL)) as total FROM loans WHERE is_active = 1 AND status IN (0, 1)');
    final outstanding =
        Decimal.parse((outstandingResult.first['total'] ?? 0).toString());

    // Today's collection
    final todayCollectionResult = await db.rawQuery(
        'SELECT SUM(CAST(amount AS REAL)) as total FROM payments WHERE date(payment_date) = date("now") AND is_active = 1');
    final todayCollection =
        Decimal.parse((todayCollectionResult.first['total'] ?? 0).toString());

    return {
      'totalGiven': totalGiven,
      'totalReceived': totalReceived,
      'outstanding': outstanding,
      'todayCollection': todayCollection,
    };
  }

  // Backup and restore
  Future<String> exportData() async {
    final db = await database;

    // Get all data
    final customers = await db.query('customers', where: 'is_active = 1');
    final loans = await db.query('loans', where: 'is_active = 1');
    final payments = await db.query('payments', where: 'is_active = 1');

    return {
      'customers': customers,
      'loans': loans,
      'payments': payments,
      'exportDate': DateTime.now().toIso8601String(),
    }.toString();
  }

  // Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _schemaEnsured = false; // Reset flag so schema is verified on next open
    }
  }

  /// Restore database from a backup file
  Future<bool> restoreFromFile(String backupPath) async {
    try {
      // Close current database
      await close();

      // Get current database path
      final dbPath = await getDatabasePath();

      // Copy backup file to database location
      final backupFile = File(backupPath);
      if (await backupFile.exists()) {
        await backupFile.copy(dbPath);

        // Reinitialize database
        _database = await _initializeDatabase();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Restore error: $e');
      return false;
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

  /// Delete a loan (soft delete)
  /// NOTE: This only soft-deletes the loan itself.
  /// To also delete payments, use LoanProvider.deleteLoan() which handles both.
  /// This ensures data integrity and only affects the specific loan ID.
  Future<int> deleteLoan(int id) async {
    final db = await database;
    return await db.update(
      'loans',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where:
          'id = ?', // Scoped to specific loan ID - other loans remain untouched
      whereArgs: [id],
    );
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
      debugPrint('DEBUG: insertPayment error: $e');
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

    List<Loan> loans = [];
    for (final map in loanMaps) {
      final loan = Loan.fromMap(map);
      final payments = await getPaymentsForLoan(loan.id!);
      loans.add(loan.copyWith(payments: payments));
    }
    debugPrint('📋 Loaded ${loans.length} loans from database');
    return loans;
  }

  /// Update all existing loans to fix tenure from 12 to 10 weeks
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
      debugPrint('Error clearing database: $e');
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
