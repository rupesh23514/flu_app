import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'database_service.dart';

/// Service for backup and restore functionality.
///
/// All backups use the raw SQLite .db format for consistency with Google Drive
/// backups. This ensures any backup can be restored from any source (local,
/// Drive, WhatsApp) using the same `DatabaseService.restoreFromFile()` method,
/// which handles auto-migration from any database version (v1–v12).
class BackupService extends ChangeNotifier {
  static final BackupService instance = BackupService._internal();

  final DatabaseService _databaseService = DatabaseService.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool _isBackingUp = false;
  bool _isRestoring = false;
  String? _lastBackupDate;
  String? _errorMessage;
  double _progress = 0.0;

  BackupService._internal();

  // Getters
  bool get isBackingUp => _isBackingUp;
  bool get isRestoring => _isRestoring;
  String? get lastBackupDate => _lastBackupDate;
  String? get errorMessage => _errorMessage;
  double get progress => _progress;

  // Keys for secure storage
  static const String _lastBackupKey = 'last_backup_date';
  static const String _autoBackupKey = 'auto_backup_enabled';
  static const String _backupIntervalKey = 'backup_interval_hours';

  /// Initialize the backup service
  Future<void> initialize() async {
    _lastBackupDate = await _secureStorage.read(key: _lastBackupKey);
    notifyListeners();
  }

  /// Check if auto backup is enabled
  Future<bool> isAutoBackupEnabled() async {
    final value = await _secureStorage.read(key: _autoBackupKey);
    return value == 'true';
  }

  /// Set auto backup enabled
  Future<void> setAutoBackupEnabled(bool enabled) async {
    await _secureStorage.write(
      key: _autoBackupKey,
      value: enabled.toString(),
    );
  }

  /// Get backup interval in hours
  Future<int> getBackupInterval() async {
    final value = await _secureStorage.read(key: _backupIntervalKey);
    return int.tryParse(value ?? '24') ?? 24;
  }

  /// Set backup interval
  Future<void> setBackupInterval(int hours) async {
    await _secureStorage.write(
      key: _backupIntervalKey,
      value: hours.toString(),
    );
  }

  /// Create a backup of all data as a raw .db file.
  /// Uses SQLite WAL checkpoint + file copy for data safety.
  Future<BackupResult> createBackup() async {
    _isBackingUp = true;
    _progress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      // Step 1: Create a safe copy of the live database
      _progress = 0.3;
      notifyListeners();

      final safeCopyPath = await _databaseService.createSafeCopy();

      // Step 2: Move the copy to the backups directory with a timestamped name
      _progress = 0.6;
      notifyListeners();

      final directory = await getApplicationDocumentsDirectory();
      final backupDir = Directory(path.join(directory.path, 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = path.join(backupDir.path, 'backup_$timestamp.db');

      await File(safeCopyPath).copy(filePath);

      // Clean up the temp copy
      try {
        await File(safeCopyPath).delete();
      } catch (_) {}

      // Step 3: Generate SHA-256 checksum and store alongside
      _progress = 0.8;
      notifyListeners();

      final checksumValue = await _computeFileChecksum(filePath);
      final checksumFile = File('$filePath.sha256');
      await checksumFile.writeAsString(checksumValue);

      // Step 4: Update last backup date
      _progress = 1.0;
      _lastBackupDate = DateTime.now().toIso8601String();
      await _secureStorage.write(key: _lastBackupKey, value: _lastBackupDate);

      _isBackingUp = false;
      notifyListeners();

      final file = File(filePath);
      return BackupResult(
        success: true,
        filePath: filePath,
        timestamp: DateTime.now(),
        sizeBytes: await file.length(),
      );
    } catch (e) {
      _errorMessage = 'Backup failed: $e';
      _isBackingUp = false;
      notifyListeners();

      return BackupResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Share backup via any app (WhatsApp, email, etc.)
  Future<bool> shareViaWhatsApp() async {
    try {
      final result = await createBackup();

      if (!result.success || result.filePath == null) {
        _errorMessage = 'Failed to create backup for sharing';
        notifyListeners();
        return false;
      }

      await Share.shareXFiles(
        [XFile(result.filePath!)],
        text: 'Financial Manager Backup - ${_formatDateTime(result.timestamp!)}',
        subject: 'Financial Manager Backup',
      );

      return true;
    } catch (e) {
      _errorMessage = 'Failed to share: $e';
      notifyListeners();
      return false;
    }
  }

  /// Export data to local storage
  Future<BackupResult> exportToLocal() async {
    try {
      final result = await createBackup();

      if (result.success) {
        try {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            final downloadsPath = path.join(externalDir.path, 'FinancialManager');
            final downloadsDir = Directory(downloadsPath);
            if (!await downloadsDir.exists()) {
              await downloadsDir.create(recursive: true);
            }

            final sourceFile = File(result.filePath!);
            final destPath = path.join(
              downloadsPath,
              'backup_${DateTime.now().millisecondsSinceEpoch}.db',
            );
            await sourceFile.copy(destPath);

            return BackupResult(
              success: true,
              filePath: destPath,
              timestamp: result.timestamp,
              sizeBytes: result.sizeBytes,
            );
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Could not save to external storage: $e');
          }
        }
      }

      return result;
    } catch (e) {
      _errorMessage = 'Export failed: $e';
      notifyListeners();
      return BackupResult(success: false, error: e.toString());
    }
  }

  /// List available backup files (both .db and legacy .json)
  Future<List<BackupFile>> listBackups() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final backupDir = Directory(path.join(directory.path, 'backups'));

      if (!await backupDir.exists()) {
        return [];
      }

      final files = await backupDir.list().toList();
      final backups = <BackupFile>[];

      for (final entity in files) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          // Include .db backups and legacy .json backups
          if (ext == '.db' || ext == '.json') {
            final stat = await entity.stat();
            final name = path.basename(entity.path);

            backups.add(BackupFile(
              path: entity.path,
              name: name,
              createdAt: stat.modified,
              sizeBytes: stat.size,
              isLegacyFormat: ext == '.json',
            ));
          }
        }
      }

      // Sort by date descending
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return backups;
    } catch (e) {
      _errorMessage = 'Failed to list backups: $e';
      notifyListeners();
      return [];
    }
  }

  /// Restore from a backup file.
  /// Supports .db files (current format) via DatabaseService.restoreFromFile().
  /// Legacy .json files are NOT restorable (returns error with helpful message).
  ///
  /// On failure, check [errorMessage] for a user-friendly explanation.
  Future<bool> restoreFromFile(String filePath) async {
    _isRestoring = true;
    _progress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      // Step 1: Validate the file exists
      _progress = 0.2;
      notifyListeners();

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Backup file not found');
      }

      // Step 2: Check file type
      _progress = 0.3;
      notifyListeners();

      final ext = path.extension(filePath).toLowerCase();
      if (ext == '.json') {
        throw Exception(
          'This is a legacy JSON backup and cannot be restored. '
          'Please use a .db backup or restore from Google Drive.',
        );
      }

      // Step 3: Verify SHA-256 checksum if available
      _progress = 0.4;
      notifyListeners();

      final checksumFile = File('$filePath.sha256');
      if (await checksumFile.exists()) {
        final storedChecksum = (await checksumFile.readAsString()).trim();
        final actualChecksum = await _computeFileChecksum(filePath);
        if (storedChecksum != actualChecksum) {
          throw Exception('Backup file integrity check failed — file may be corrupted');
        }
      }

      // Step 4: Restore via DatabaseService (handles migration from any version)
      _progress = 0.6;
      notifyListeners();

      final success = await DatabaseService.instance.restoreFromFile(filePath);

      if (!success) {
        // Use the detailed error from DatabaseService when available
        final detailedError = DatabaseService.instance.lastRestoreError;
        throw Exception(detailedError ?? 'Database restore failed — file may be corrupted or incompatible');
      }

      // Step 5: Done
      _progress = 1.0;
      _isRestoring = false;
      notifyListeners();

      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _isRestoring = false;
      notifyListeners();
      return false;
    }
  }

  /// Delete a backup file and its checksum
  Future<bool> deleteBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      // Also delete checksum file if exists
      final checksumFile = File('$filePath.sha256');
      if (await checksumFile.exists()) {
        await checksumFile.delete();
      }
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete backup: $e';
      notifyListeners();
      return false;
    }
  }

  /// Compute SHA-256 checksum of a file
  Future<String> _computeFileChecksum(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Format datetime for display
  String _formatDateTime(DateTime dateTime) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dateTime.day} ${months[dateTime.month - 1]}, ${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

/// Result of a backup operation
class BackupResult {
  final bool success;
  final String? filePath;
  final DateTime? timestamp;
  final int? sizeBytes;
  final String? error;

  BackupResult({
    required this.success,
    this.filePath,
    this.timestamp,
    this.sizeBytes,
    this.error,
  });
}

/// Represents a backup file
class BackupFile {
  final String path;
  final String name;
  final DateTime createdAt;
  final int sizeBytes;
  final bool isLegacyFormat;

  BackupFile({
    required this.path,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
    this.isLegacyFormat = false,
  });

  String get formattedSize {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    } else if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
