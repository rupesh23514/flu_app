// Customer Repository - handles all customer-related database operations
// Extracted from DatabaseService to follow Single Responsibility Principle

import 'package:sqflite/sqflite.dart';
import '../../shared/models/customer.dart';
import '../../shared/models/customer_group.dart';
import '../../shared/models/pagination_result.dart';
import 'base_repository.dart';

class CustomerRepository extends BaseRepository {
  // Singleton pattern
  static final CustomerRepository _instance = CustomerRepository._internal();
  static CustomerRepository get instance => _instance;
  CustomerRepository._internal();

  // ==================== Customer CRUD Operations ====================

  /// Insert a new customer
  Future<Result<int>> insert(Customer customer) async {
    return safeExecute(() async {
      final db = await database;
      final map = customer.toMap();
      map.remove('id');
      return await db.insert('customers', map);
    });
  }

  /// Get all active customers
  Future<Result<List<Customer>>> getAll() async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'customers',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'name ASC',
      );
      return maps.map((map) => Customer.fromMap(map)).toList();
    });
  }

  /// Get customers with pagination and optional filters
  Future<Result<PaginationResult<Customer>>> getPaginated({
    int page = 1,
    int pageSize = 20,
    String? searchQuery,
    int? groupId,
  }) async {
    return safeExecute(() async {
      final db = await database;
      final offset = (page - 1) * pageSize;

      String whereClause = 'is_active = 1';
      List<dynamic> whereArgs = [];

      if (searchQuery != null && searchQuery.isNotEmpty) {
        whereClause += ' AND (LOWER(name) LIKE ? OR phone_number LIKE ? OR alternate_phone LIKE ?)';
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
    });
  }

  /// Get customer by ID
  Future<Result<Customer?>> getById(int id) async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'customers',
        where: 'id = ? AND is_active = ?',
        whereArgs: [id, 1],
        limit: 1,
      );
      return maps.isNotEmpty ? Customer.fromMap(maps.first) : null;
    });
  }

  /// Get customer by phone number
  Future<Result<Customer?>> getByPhone(String phoneNumber) async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'customers',
        where: 'phone_number = ? AND is_active = ?',
        whereArgs: [phoneNumber, 1],
        limit: 1,
      );
      return maps.isNotEmpty ? Customer.fromMap(maps.first) : null;
    });
  }

  /// Update customer
  Future<Result<int>> update(Customer customer) async {
    return safeExecute(() async {
      final db = await database;
      return await db.update(
        'customers',
        customer.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [customer.id],
      );
    });
  }

  /// Soft delete customer
  Future<Result<int>> delete(int id) async {
    return safeExecute(() async {
      final db = await database;
      return await db.update(
        'customers',
        {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Permanently delete customer and all related data
  Future<Result<void>> deleteEntirely(int customerId) async {
    return safeTransaction((txn) async {
      // Delete all payments for this customer's loans
      await txn.delete(
        'payments',
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );

      // Delete all loans for this customer
      await txn.delete(
        'loans',
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );

      // Delete all reminders for this customer
      await txn.delete(
        'reminders',
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );

      // Delete the customer
      await txn.delete(
        'customers',
        where: 'id = ?',
        whereArgs: [customerId],
      );
    });
  }

  /// Get customer count
  Future<Result<int>> getCount() async {
    return safeExecute(() async {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM customers WHERE is_active = 1',
      );
      return result.first['count'] as int;
    });
  }

  // ==================== Customer Group Operations ====================

  /// Insert customer group
  Future<Result<int>> insertGroup(CustomerGroup group) async {
    return safeExecute(() async {
      final db = await database;
      final map = group.toMap();
      map.remove('id');
      return await db.insert('customer_groups', map);
    });
  }

  /// Get all customer groups
  Future<Result<List<CustomerGroup>>> getAllGroups() async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'customer_groups',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'name ASC',
      );
      return maps.map((map) => CustomerGroup.fromMap(map)).toList();
    });
  }

  /// Get customer group by ID
  Future<Result<CustomerGroup?>> getGroupById(int id) async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'customer_groups',
        where: 'id = ? AND is_active = ?',
        whereArgs: [id, 1],
        limit: 1,
      );
      return maps.isNotEmpty ? CustomerGroup.fromMap(maps.first) : null;
    });
  }

  /// Update customer group
  Future<Result<int>> updateGroup(CustomerGroup group) async {
    return safeExecute(() async {
      final db = await database;
      return await db.update(
        'customer_groups',
        group.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [group.id],
      );
    });
  }

  /// Delete customer group (soft delete)
  Future<Result<int>> deleteGroup(int id) async {
    return safeTransaction((txn) async {
      // First, set group_id to null for all customers in this group
      await txn.update(
        'customers',
        {'group_id': null, 'updated_at': DateTime.now().toIso8601String()},
        where: 'group_id = ?',
        whereArgs: [id],
      );
      
      // Then soft delete the group
      return await txn.update(
        'customer_groups',
        {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Get customer count in a group
  Future<Result<int>> getCountInGroup(int groupId) async {
    return safeExecute(() async {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM customers WHERE group_id = ? AND is_active = 1',
        [groupId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    });
  }

  /// Get customers by group
  Future<Result<List<Customer>>> getByGroup(int? groupId) async {
    if (groupId == null) {
      return getAll();
    }

    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'customers',
        where: 'group_id = ? AND is_active = ?',
        whereArgs: [groupId, 1],
        orderBy: 'name ASC',
      );
      return maps.map((map) => Customer.fromMap(map)).toList();
    });
  }

  /// Assign customer to group
  Future<Result<int>> assignToGroup(int customerId, int? groupId) async {
    return safeExecute(() async {
      final db = await database;
      return await db.update(
        'customers',
        {'group_id': groupId, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [customerId],
      );
    });
  }
}
