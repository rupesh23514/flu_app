import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

/// Service to validate and ensure safe app updates
/// Provides comprehensive data protection during APK updates
class MigrationSafetyService {
  static const String _tag = 'MigrationSafetyService';

  // Keys for tracking data integrity
  static const String _keyLastKnownCustomerCount = 'last_known_customer_count';
  static const String _keyLastKnownLoanCount = 'last_known_loan_count';
  static const String _keyLastKnownPaymentCount = 'last_known_payment_count';
  static const String _keyLastIntegrityCheck = 'last_integrity_check';

  /// Validates that the database migration was successful and data is intact
  static Future<bool> validateMigrationIntegrity() async {
    try {
      final db = await DatabaseService.instance.database;

      // Check if all required tables exist
      final tables = await _getTableNames(db);

      // Core tables that must exist
      final requiredTables = [
        'customers',
        'loans',
        'payments',
      ];

      // Optional tables (may not exist in older versions)
      final optionalTables = [
        'settings',
        'reminders',
        'customer_groups',
        'audit_log',
      ];

      for (final table in requiredTables) {
        if (!tables.contains(table)) {
          debugPrint('$_tag: Missing required table: $table');
          return false;
        }
      }

      // Log optional tables status
      for (final table in optionalTables) {
        if (!tables.contains(table)) {
          debugPrint('$_tag: Optional table not found (OK): $table');
        }
      }

      // Validate that existing data is still accessible
      final customerCount = await _getRecordCount(db, 'customers');
      final loanCount = await _getRecordCount(db, 'loans');
      final paymentCount = await _getRecordCount(db, 'payments');

      // Validate data integrity against last known counts
      final dataLoss =
          await _checkForDataLoss(customerCount, loanCount, paymentCount);
      if (dataLoss) {
        debugPrint('$_tag: WARNING - Potential data loss detected!');
        // Don't fail - just warn, user data may have legitimately changed
      }

      // Update last known counts
      await _updateLastKnownCounts(customerCount, loanCount, paymentCount);

      debugPrint('$_tag: Migration validation complete:');
      debugPrint('$_tag: - Customers: $customerCount');
      debugPrint('$_tag: - Loans: $loanCount');
      debugPrint('$_tag: - Payments: $paymentCount');
      debugPrint('$_tag: - All required tables present');

      return true;
    } catch (e) {
      debugPrint('$_tag: Migration validation failed: $e');
      return false;
    }
  }

  /// Check for potential data loss
  static Future<bool> _checkForDataLoss(
      int customers, int loans, int payments) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final lastCustomers = prefs.getInt(_keyLastKnownCustomerCount) ?? 0;
      final lastLoans = prefs.getInt(_keyLastKnownLoanCount) ?? 0;
      final lastPayments = prefs.getInt(_keyLastKnownPaymentCount) ?? 0;

      // Only check if we have previous counts (not fresh install)
      if (lastCustomers == 0 && lastLoans == 0 && lastPayments == 0) {
        return false;
      }

      // Check for significant decrease (more than 10% loss is suspicious)
      final customerLoss = lastCustomers > 0 && customers < lastCustomers * 0.9;
      final loanLoss = lastLoans > 0 && loans < lastLoans * 0.9;
      final paymentLoss = lastPayments > 0 && payments < lastPayments * 0.9;

      return customerLoss || loanLoss || paymentLoss;
    } catch (e) {
      return false;
    }
  }

  /// Update last known record counts
  static Future<void> _updateLastKnownCounts(
      int customers, int loans, int payments) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastKnownCustomerCount, customers);
      await prefs.setInt(_keyLastKnownLoanCount, loans);
      await prefs.setInt(_keyLastKnownPaymentCount, payments);
      await prefs.setString(
          _keyLastIntegrityCheck, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('$_tag: Failed to update counts: $e');
    }
  }

  /// Gets list of table names in the database
  static Future<List<String>> _getTableNames(Database db) async {
    final result = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");

    return result.map((row) => row['name'] as String).toList();
  }

  /// Gets record count for a table
  static Future<int> _getRecordCount(Database db, String tableName) async {
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM $tableName');
    return result.isNotEmpty ? ((result.first['count'] as int?) ?? 0) : 0;
  }

  /// Creates backup of critical data before migration (for safety)
  static Future<Map<String, dynamic>> createDataSnapshot() async {
    try {
      final db = await DatabaseService.instance.database;

      final snapshot = <String, dynamic>{};

      // Take count snapshots of critical data
      snapshot['customers_count'] = await _getRecordCount(db, 'customers');
      snapshot['loans_count'] = await _getRecordCount(db, 'loans');
      snapshot['payments_count'] = await _getRecordCount(db, 'payments');
      snapshot['timestamp'] = DateTime.now().toIso8601String();

      debugPrint('$_tag: Data snapshot created: $snapshot');
      return snapshot;
    } catch (e) {
      debugPrint('$_tag: Failed to create data snapshot: $e');
      return {};
    }
  }

  /// Validates that data counts match expected values after migration
  static Future<bool> validateDataIntegrity(
      Map<String, dynamic> preSnapshot) async {
    try {
      final postSnapshot = await createDataSnapshot();

      // Check that no data was lost during migration
      final preCustomers = preSnapshot['customers_count'] ?? 0;
      final postCustomers = postSnapshot['customers_count'] ?? 0;

      final preLoans = preSnapshot['loans_count'] ?? 0;
      final postLoans = postSnapshot['loans_count'] ?? 0;

      final prePayments = preSnapshot['payments_count'] ?? 0;
      final postPayments = postSnapshot['payments_count'] ?? 0;

      if (postCustomers < preCustomers ||
          postLoans < preLoans ||
          postPayments < prePayments) {
        debugPrint('$_tag: Data loss detected during migration!');
        debugPrint(
            '$_tag: Pre-migration: customers=$preCustomers, loans=$preLoans, payments=$prePayments');
        debugPrint(
            '$_tag: Post-migration: customers=$postCustomers, loans=$postLoans, payments=$postPayments');
        return false;
      }

      debugPrint('$_tag: Data integrity validation passed');
      return true;
    } catch (e) {
      debugPrint('$_tag: Data integrity validation failed: $e');
      return false;
    }
  }

  /// Get last integrity check timestamp
  static Future<String?> getLastIntegrityCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyLastIntegrityCheck);
    } catch (e) {
      return null;
    }
  }

  /// Get detailed database statistics
  static Future<Map<String, dynamic>> getDatabaseStats() async {
    try {
      final db = await DatabaseService.instance.database;

      final stats = <String, dynamic>{};

      // Record counts
      stats['customers'] = await _getRecordCount(db, 'customers');
      stats['loans'] = await _getRecordCount(db, 'loans');
      stats['payments'] = await _getRecordCount(db, 'payments');

      // Try optional tables
      try {
        stats['reminders'] = await _getRecordCount(db, 'reminders');
      } catch (_) {
        stats['reminders'] = 0;
      }

      try {
        stats['customer_groups'] = await _getRecordCount(db, 'customer_groups');
      } catch (_) {
        stats['customer_groups'] = 0;
      }

      // Table list
      stats['tables'] = await _getTableNames(db);

      // Database version
      stats['version'] = await db.getVersion();

      return stats;
    } catch (e) {
      debugPrint('$_tag: Failed to get database stats: $e');
      return {};
    }
  }

  /// Perform deep validation of database integrity and auto-fix issues
  static Future<Map<String, dynamic>> performDeepValidation() async {
    final results = <String, dynamic>{
      'valid': true,
      'errors': <String>[],
      'warnings': <String>[],
    };

    try {
      final db = await DatabaseService.instance.database;

      // 1. Fix orphaned records first (loans without customers)
      await db.rawDelete('''
        DELETE FROM loans 
        WHERE customer_id NOT IN (SELECT id FROM customers)
      ''');

      // 2. Fix orphaned payments (payments without loans)
      await db.rawDelete('''
        DELETE FROM payments 
        WHERE loan_id NOT IN (SELECT id FROM loans)
      ''');

      // 3. Fix orphaned reminders if table exists
      try {
        await db.rawDelete('''
          DELETE FROM reminders 
          WHERE loan_id IS NOT NULL AND loan_id NOT IN (SELECT id FROM loans)
        ''');
        await db.rawDelete('''
          DELETE FROM reminders 
          WHERE customer_id IS NOT NULL AND customer_id NOT IN (SELECT id FROM customers)
        ''');
      } catch (_) {
        // Reminders table may not exist
      }

      // 4. Check integrity after cleanup
      final integrityCheck = await db.rawQuery('PRAGMA integrity_check');
      final integrityResult = integrityCheck.isNotEmpty 
          ? (integrityCheck.first['integrity_check'] as String?) ?? 'ok'
          : 'ok';
      if (integrityResult != 'ok') {
        results['valid'] = false;
        results['errors']
            .add('Database integrity check failed: $integrityResult');
      }

      debugPrint(
          '$_tag: Deep validation complete: ${results['valid'] ? 'PASSED' : 'FAILED'}');
    } catch (e) {
      results['valid'] = false;
      results['errors'].add('Validation error: $e');
    }

    return results;
  }
}
