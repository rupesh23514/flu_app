import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import 'migration_safety_service.dart';

/// Service to handle safe app updates without data loss
/// Ensures database integrity and settings preservation during APK updates
class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._internal();
  AppUpdateService._internal();

  static const String _tag = 'AppUpdateService';
  
  // Current app version - increment when releasing new APK
  static const int currentAppVersion = 2;
  static const String currentAppVersionName = '1.1.0';
  
  // Settings keys for tracking
  static const String _keyLastAppVersion = 'last_app_version';
  static const String _keyLastAppVersionName = 'last_app_version_name';
  static const String _keyLastUpdateDate = 'last_update_date';
  static const String _keyDatabaseBackupPath = 'database_backup_path';
  static const String _keySettingsVersion = 'settings_version';
  static const String _keyUpdateInProgress = 'update_in_progress';

  SharedPreferences? _prefs;
  bool _isInitialized = false;

  /// Initialize the update service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      _isInitialized = true;
      debugPrint('$_tag: Initialized successfully');
    } catch (e) {
      debugPrint('$_tag: Initialization error: $e');
    }
  }

  /// Check if this is a new install or update
  Future<UpdateStatus> checkUpdateStatus() async {
    await initialize();
    
    final lastVersion = _prefs?.getInt(_keyLastAppVersion) ?? 0;
    
    if (lastVersion == 0) {
      debugPrint('$_tag: Fresh install detected');
      return UpdateStatus.freshInstall;
    } else if (lastVersion < currentAppVersion) {
      debugPrint('$_tag: Update detected from version $lastVersion to $currentAppVersion');
      return UpdateStatus.updated;
    } else if (lastVersion == currentAppVersion) {
      debugPrint('$_tag: Same version, normal launch');
      return UpdateStatus.noChange;
    } else {
      debugPrint('$_tag: Downgrade detected from version $lastVersion to $currentAppVersion');
      return UpdateStatus.downgraded;
    }
  }

  /// Perform safe update procedures
  Future<UpdateResult> performSafeUpdate() async {
    await initialize();
    
    final status = await checkUpdateStatus();
    
    try {
      // Mark update in progress
      await _prefs?.setBool(_keyUpdateInProgress, true);
      
      switch (status) {
        case UpdateStatus.freshInstall:
          await _handleFreshInstall();
          break;
        case UpdateStatus.updated:
          await _handleUpdate();
          break;
        case UpdateStatus.downgraded:
          await _handleDowngrade();
          break;
        case UpdateStatus.noChange:
          // Just verify everything is okay
          await _verifyIntegrity();
          break;
      }
      
      // Update version tracking
      await _updateVersionTracking();
      
      // Mark update complete
      await _prefs?.setBool(_keyUpdateInProgress, false);
      
      return UpdateResult(
        success: true,
        status: status,
        message: 'Update completed successfully',
      );
    } catch (e, stackTrace) {
      debugPrint('$_tag: Update error: $e');
      debugPrint('$_tag: Stack trace: $stackTrace');
      
      // Try to recover
      await _attemptRecovery();
      
      return UpdateResult(
        success: false,
        status: status,
        message: 'Update failed: $e',
        error: e.toString(),
      );
    }
  }

  /// Handle fresh install
  Future<void> _handleFreshInstall() async {
    debugPrint('$_tag: Handling fresh install...');
    
    // Initialize default settings
    await _initializeDefaultSettings();
    
    debugPrint('$_tag: Fresh install setup complete');
  }

  /// Handle app update (APK update)
  Future<void> _handleUpdate() async {
    debugPrint('$_tag: Handling app update...');
    
    // Step 1: Create backup before any changes
    await _createDatabaseBackup();
    
    // Step 2: Create settings snapshot
    final preSnapshot = await MigrationSafetyService.createDataSnapshot();
    
    // Step 3: Validate existing data
    final preValidation = await MigrationSafetyService.validateMigrationIntegrity();
    if (!preValidation) {
      debugPrint('$_tag: Pre-update validation failed, attempting repair...');
      await _repairDatabase();
    }
    
    // Step 4: Database migration happens automatically via sqflite onUpgrade
    // Just ensure it's initialized
    await DatabaseService.instance.initializeDatabase();
    
    // Step 5: Validate data integrity after migration
    final postValidation = await MigrationSafetyService.validateDataIntegrity(preSnapshot);
    if (!postValidation) {
      debugPrint('$_tag: WARNING - Post-update validation shows potential data changes');
      // Don't throw - data might just be new/modified legitimately
    }
    
    // Step 6: Migrate settings if needed
    await _migrateSettings();
    
    debugPrint('$_tag: App update handling complete');
  }

  /// Handle app downgrade (rare case)
  Future<void> _handleDowngrade() async {
    debugPrint('$_tag: Handling app downgrade...');
    
    // Create backup first
    await _createDatabaseBackup();
    
    // Downgrade may require careful handling
    // Don't delete any data, just ensure compatibility
    await DatabaseService.instance.initializeDatabase();
    
    debugPrint('$_tag: App downgrade handling complete');
  }

  /// Verify app integrity on normal launch
  Future<void> _verifyIntegrity() async {
    debugPrint('$_tag: Verifying app integrity...');
    
    // Quick validation
    final isValid = await MigrationSafetyService.validateMigrationIntegrity();
    
    if (!isValid) {
      debugPrint('$_tag: Integrity check failed, attempting repair...');
      await _repairDatabase();
    }
    
    debugPrint('$_tag: Integrity verification complete');
  }

  /// Create database backup before updates
  Future<String?> _createDatabaseBackup() async {
    try {
      final dbPath = await DatabaseService.instance.getDatabasePath();
      final dbFile = File(dbPath);
      
      if (!await dbFile.exists()) {
        debugPrint('$_tag: No database file to backup');
        return null;
      }
      
      // Create backup directory
      final appDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${appDir.path}/backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      
      // Create timestamped backup
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final backupPath = '${backupDir.path}/db_backup_$timestamp.db';
      
      // Copy database file
      await dbFile.copy(backupPath);
      
      // Store backup path
      await _prefs?.setString(_keyDatabaseBackupPath, backupPath);
      
      // Clean up old backups (keep last 3)
      await _cleanupOldBackups(backupDir);
      
      debugPrint('$_tag: Database backup created at $backupPath');
      return backupPath;
    } catch (e) {
      debugPrint('$_tag: Backup creation failed: $e');
      return null;
    }
  }

  /// Clean up old backup files, keeping the most recent ones
  Future<void> _cleanupOldBackups(Directory backupDir) async {
    try {
      final files = await backupDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.db'))
          .cast<File>()
          .toList();
      
      if (files.length <= 3) return;
      
      // Sort by modification time (oldest first)
      files.sort((a, b) => 
        a.statSync().modified.compareTo(b.statSync().modified));
      
      // Delete oldest files, keeping last 3
      for (var i = 0; i < files.length - 3; i++) {
        await files[i].delete();
        debugPrint('$_tag: Deleted old backup: ${files[i].path}');
      }
    } catch (e) {
      debugPrint('$_tag: Cleanup failed: $e');
    }
  }

  /// Restore database from backup
  Future<bool> restoreFromBackup() async {
    try {
      final backupPath = _prefs?.getString(_keyDatabaseBackupPath);
      if (backupPath == null) {
        debugPrint('$_tag: No backup path found');
        return false;
      }
      
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        debugPrint('$_tag: Backup file not found: $backupPath');
        return false;
      }
      
      // Close current database
      final dbPath = await DatabaseService.instance.getDatabasePath();
      await deleteDatabase(dbPath);
      
      // Copy backup to database location
      await backupFile.copy(dbPath);
      
      // Reinitialize database
      await DatabaseService.instance.initializeDatabase();
      
      debugPrint('$_tag: Database restored from backup');
      return true;
    } catch (e) {
      debugPrint('$_tag: Restore failed: $e');
      return false;
    }
  }

  /// Initialize default settings for fresh install
  Future<void> _initializeDefaultSettings() async {
    // Default settings that should be set on fresh install
    final defaults = <String, dynamic>{
      'alarm_volume_level': 5,
      'auto_lock_enabled': true,
      'auto_lock_time': 30,
      'language': 'en',
      'notification_enabled': true,
      'sound_enabled': true,
      _keySettingsVersion: 1,
    };
    
    for (final entry in defaults.entries) {
      if (entry.value is int) {
        await _prefs?.setInt(entry.key, entry.value as int);
      } else if (entry.value is bool) {
        await _prefs?.setBool(entry.key, entry.value as bool);
      } else if (entry.value is String) {
        await _prefs?.setString(entry.key, entry.value as String);
      }
    }
    
    debugPrint('$_tag: Default settings initialized');
  }

  /// Migrate settings between versions
  Future<void> _migrateSettings() async {
    final currentSettingsVersion = _prefs?.getInt(_keySettingsVersion) ?? 0;
    
    // Settings migration logic
    if (currentSettingsVersion < 1) {
      // Migrate to version 1: Add default alarm volume
      if (_prefs?.getInt('alarm_volume_level') == null) {
        await _prefs?.setInt('alarm_volume_level', 5);
      }
      await _prefs?.setInt(_keySettingsVersion, 1);
      debugPrint('$_tag: Settings migrated to version 1');
    }
    
    // Add more migrations as needed for future versions
    // if (currentSettingsVersion < 2) { ... }
  }

  /// Update version tracking after successful update
  Future<void> _updateVersionTracking() async {
    await _prefs?.setInt(_keyLastAppVersion, currentAppVersion);
    await _prefs?.setString(_keyLastAppVersionName, currentAppVersionName);
    await _prefs?.setString(_keyLastUpdateDate, DateTime.now().toIso8601String());
    
    debugPrint('$_tag: Version tracking updated to $currentAppVersion ($currentAppVersionName)');
  }

  /// Attempt to repair database issues
  Future<void> _repairDatabase() async {
    try {
      debugPrint('$_tag: Attempting database repair...');
      
      // Force schema update
      await DatabaseService.instance.forceSchemaUpdate();
      
      // Validate again
      final isValid = await MigrationSafetyService.validateMigrationIntegrity();
      
      if (isValid) {
        debugPrint('$_tag: Database repair successful');
      } else {
        debugPrint('$_tag: Database repair may have issues, but continuing...');
      }
    } catch (e) {
      debugPrint('$_tag: Database repair failed: $e');
    }
  }

  /// Attempt recovery from failed update
  Future<void> _attemptRecovery() async {
    debugPrint('$_tag: Attempting recovery...');
    
    // Try to restore from backup
    final restored = await restoreFromBackup();
    
    if (restored) {
      debugPrint('$_tag: Recovery successful - restored from backup');
    } else {
      debugPrint('$_tag: Recovery failed - backup not available');
      // Continue anyway - some data is better than crashing
    }
  }

  /// Get last update information
  Future<Map<String, dynamic>> getUpdateInfo() async {
    await initialize();
    
    return {
      'currentVersion': currentAppVersion,
      'currentVersionName': currentAppVersionName,
      'lastVersion': _prefs?.getInt(_keyLastAppVersion) ?? 0,
      'lastVersionName': _prefs?.getString(_keyLastAppVersionName) ?? 'Unknown',
      'lastUpdateDate': _prefs?.getString(_keyLastUpdateDate),
      'updateInProgress': _prefs?.getBool(_keyUpdateInProgress) ?? false,
    };
  }

  /// Check if recovery is available
  Future<bool> isRecoveryAvailable() async {
    final backupPath = _prefs?.getString(_keyDatabaseBackupPath);
    if (backupPath == null) return false;
    
    return File(backupPath).exists();
  }

  /// Get all available backups
  Future<List<BackupInfo>> getAvailableBackups() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${appDir.path}/backups');
      
      if (!await backupDir.exists()) return [];
      
      final files = await backupDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.db'))
          .cast<File>()
          .toList();
      
      final backups = <BackupInfo>[];
      for (final file in files) {
        final stat = await file.stat();
        backups.add(BackupInfo(
          path: file.path,
          size: stat.size,
          created: stat.modified,
        ));
      }
      
      // Sort by date (newest first)
      backups.sort((a, b) => b.created.compareTo(a.created));
      
      return backups;
    } catch (e) {
      debugPrint('$_tag: Failed to get backups: $e');
      return [];
    }
  }

  /// Restore from specific backup
  Future<bool> restoreFromSpecificBackup(String backupPath) async {
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        return false;
      }
      
      // Close and delete current database
      final dbPath = await DatabaseService.instance.getDatabasePath();
      await deleteDatabase(dbPath);
      
      // Copy backup
      await backupFile.copy(dbPath);
      
      // Reinitialize
      await DatabaseService.instance.initializeDatabase();
      
      return true;
    } catch (e) {
      debugPrint('$_tag: Restore from specific backup failed: $e');
      return false;
    }
  }

  /// Delete all local data (for complete reset)
  Future<void> deleteAllData() async {
    try {
      // Delete database
      final dbPath = await DatabaseService.instance.getDatabasePath();
      await deleteDatabase(dbPath);
      
      // Clear preferences
      await _prefs?.clear();
      
      // Delete backup files
      final appDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${appDir.path}/backups');
      if (await backupDir.exists()) {
        await backupDir.delete(recursive: true);
      }
      
      debugPrint('$_tag: All local data deleted');
    } catch (e) {
      debugPrint('$_tag: Delete all data failed: $e');
    }
  }
}

/// Status of update check
enum UpdateStatus {
  freshInstall,
  updated,
  downgraded,
  noChange,
}

/// Result of update operation
class UpdateResult {
  final bool success;
  final UpdateStatus status;
  final String message;
  final String? error;

  UpdateResult({
    required this.success,
    required this.status,
    required this.message,
    this.error,
  });

  @override
  String toString() => 'UpdateResult(success: $success, status: $status, message: $message)';
}

/// Information about a backup file
class BackupInfo {
  final String path;
  final int size;
  final DateTime created;

  BackupInfo({
    required this.path,
    required this.size,
    required this.created,
  });

  String get fileName => path.split('/').last;
  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
