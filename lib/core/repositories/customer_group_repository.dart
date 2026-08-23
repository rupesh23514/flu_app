// Customer Group Repository - handles all customer group database operations
// Supports many-to-many relationship between customers and groups

import 'package:sqflite/sqflite.dart';
import '../../shared/models/customer.dart';
import '../../shared/models/customer_group.dart';
import 'base_repository.dart';

class CustomerGroupRepository extends BaseRepository {
  // Singleton pattern
  static final CustomerGroupRepository _instance =
      CustomerGroupRepository._internal();
  static CustomerGroupRepository get instance => _instance;
  CustomerGroupRepository._internal();

  // ==================== Customer Group CRUD Operations ====================

  /// Insert a new customer group
  Future<Result<int>> insert(CustomerGroup group) async {
    return safeExecute(() async {
      final db = await database;
      final map = group.toMap();
      map.remove('id');
      return await db.insert('customer_groups', map);
    });
  }

  /// Get all active customer groups
  Future<Result<List<CustomerGroup>>> getAll() async {
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
  Future<Result<CustomerGroup?>> getById(int id) async {
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
  Future<Result<int>> update(CustomerGroup group) async {
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

  /// Delete customer group (soft delete).
  /// Note: Junction table entries are preserved to allow group restoration.
  /// If group is restored, customer associations remain intact.
  Future<Result<int>> delete(int id) async {
    return safeTransaction((txn) async {
      // Soft delete the group (keep junction table entries for restorability)
      return await txn.update(
        'customer_groups',
        {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Permanently delete customer group and all associations.
  /// Use this when you want to completely remove the group.
  Future<Result<int>> deleteEntirely(int id) async {
    return safeTransaction((txn) async {
      // Remove all customer-group associations (hard delete)
      await txn.delete(
        'customer_group_members',
        where: 'group_id = ?',
        whereArgs: [id],
      );

      // Hard delete the group
      return await txn.delete(
        'customer_groups',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // ==================== Multi-Group Operations ====================

  /// Get all groups for a customer
  Future<Result<List<CustomerGroup>>> getGroupsForCustomer(
      int customerId) async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.rawQuery('''
        SELECT g.* FROM customer_groups g
        INNER JOIN customer_group_members cgm ON g.id = cgm.group_id
        WHERE cgm.customer_id = ? AND g.is_active = 1
        ORDER BY g.name ASC
      ''', [customerId]);
      return maps.map((map) => CustomerGroup.fromMap(map)).toList();
    });
  }

  /// Get group IDs for a customer
  Future<Result<List<int>>> getGroupIdsForCustomer(int customerId) async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.query(
        'customer_group_members',
        columns: ['group_id'],
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );
      return maps.map((map) => map['group_id'] as int).toList();
    });
  }

  /// Add customer to a group
  Future<Result<int>> addCustomerToGroup(int customerId, int groupId) async {
    return safeExecute(() async {
      final db = await database;
      return await db.insert(
        'customer_group_members',
        {
          'customer_id': customerId,
          'group_id': groupId,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  /// Remove customer from a group
  Future<Result<int>> removeCustomerFromGroup(
      int customerId, int groupId) async {
    return safeExecute(() async {
      final db = await database;
      return await db.delete(
        'customer_group_members',
        where: 'customer_id = ? AND group_id = ?',
        whereArgs: [customerId, groupId],
      );
    });
  }

  /// Remove customer from all groups
  Future<Result<int>> removeCustomerFromAllGroups(int customerId) async {
    return safeExecute(() async {
      final db = await database;
      return await db.delete(
        'customer_group_members',
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );
    });
  }

  /// Update customer's groups (replace all).
  /// Note: For typical use (1-10 groups), individual inserts are fine.
  /// For bulk operations with many groups, consider using Batch.
  Future<Result<void>> setCustomerGroups(
      int customerId, List<int> groupIds) async {
    return safeTransaction((txn) async {
      // Remove all existing associations
      await txn.delete(
        'customer_group_members',
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );

      // Add new associations
      final now = DateTime.now().toIso8601String();
      for (final groupId in groupIds) {
        await txn.insert(
          'customer_group_members',
          {
            'customer_id': customerId,
            'group_id': groupId,
            'created_at': now,
          },
        );
      }
    });
  }

  /// Bulk move customers from one group to another atomically.
  /// Uses transaction to ensure no orphaned customers if operation fails mid-way.
  /// Returns the count of customers actually moved (removed from source AND added to target).
  /// Note: For very large lists (100+ customers), consider batch operations.
  Future<Result<int>> bulkMoveCustomers({
    required List<int> customerIds,
    required int fromGroupId,
    required int toGroupId,
  }) async {
    return safeTransaction((txn) async {
      int successCount = 0;
      final now = DateTime.now().toIso8601String();
      for (final customerId in customerIds) {
        // Remove from source group and check if deletion occurred
        final deleted = await txn.delete(
          'customer_group_members',
          where: 'customer_id = ? AND group_id = ?',
          whereArgs: [customerId, fromGroupId],
        );
        // Only add to target if customer was actually in source group
        if (deleted > 0) {
          final inserted = await txn.insert(
            'customer_group_members',
            {
              'customer_id': customerId,
              'group_id': toGroupId,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          // Only count as success if insert actually created a row (not ignored due to conflict)
          if (inserted > 0) {
            successCount++;
          }
        }
      }
      return successCount;
    });
  }

  /// Bulk add customers to multiple groups atomically.
  /// Note: For very large lists (100+ combinations), consider using Batch.
  /// Returns total number of insert attempts (may include ignored duplicates).
  Future<Result<int>> bulkAddToGroups({
    required List<int> customerIds,
    required List<int> groupIds,
  }) async {
    return safeTransaction((txn) async {
      int totalAdded = 0;
      final now = DateTime.now().toIso8601String();
      for (final customerId in customerIds) {
        for (final groupId in groupIds) {
          await txn.insert(
            'customer_group_members',
            {
              'customer_id': customerId,
              'group_id': groupId,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          totalAdded++;
        }
      }
      return totalAdded;
    });
  }

  /// Bulk remove customers from a group atomically
  Future<Result<int>> bulkRemoveFromGroup({
    required List<int> customerIds,
    required int groupId,
  }) async {
    return safeTransaction((txn) async {
      int successCount = 0;
      for (final customerId in customerIds) {
        final deleted = await txn.delete(
          'customer_group_members',
          where: 'customer_id = ? AND group_id = ?',
          whereArgs: [customerId, groupId],
        );
        if (deleted > 0) successCount++;
      }
      return successCount;
    });
  }

  // ==================== Group Membership Queries ====================

  /// Get count of customers in a group
  Future<Result<int>> getCustomerCount(int groupId) async {
    return safeExecute(() async {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT COUNT(DISTINCT c.id) as count 
        FROM customers c
        INNER JOIN customer_group_members cgm ON c.id = cgm.customer_id
        WHERE cgm.group_id = ? AND c.is_active = 1
      ''', [groupId]);
      return Sqflite.firstIntValue(result) ?? 0;
    });
  }

  /// Get all customers in a group
  Future<Result<List<Customer>>> getCustomers(int? groupId) async {
    return safeExecute(() async {
      final db = await database;
      if (groupId == null) {
        // Get all customers
        final maps = await db.query(
          'customers',
          where: 'is_active = ?',
          whereArgs: [1],
          orderBy: 'name ASC',
        );
        return maps.map((map) => Customer.fromMap(map)).toList();
      }

      final maps = await db.rawQuery('''
        SELECT c.* FROM customers c
        INNER JOIN customer_group_members cgm ON c.id = cgm.customer_id
        WHERE cgm.group_id = ? AND c.is_active = 1
        ORDER BY c.name ASC
      ''', [groupId]);
      return maps.map((map) => Customer.fromMap(map)).toList();
    });
  }

  /// Get all customers not in any group
  Future<Result<List<Customer>>> getCustomersWithoutGroup() async {
    return safeExecute(() async {
      final db = await database;
      final maps = await db.rawQuery('''
        SELECT c.* FROM customers c
        LEFT JOIN customer_group_members cgm ON c.id = cgm.customer_id
        WHERE cgm.customer_id IS NULL AND c.is_active = 1
        ORDER BY c.name ASC
      ''');
      return maps.map((map) => Customer.fromMap(map)).toList();
    });
  }

  // ==================== Legacy Support ====================

  /// Assign customer to group (legacy - uses old group_id column)
  @Deprecated('Use addCustomerToGroup instead')
  Future<Result<int>> assignCustomerToGroup(
      int customerId, int? groupId) async {
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
