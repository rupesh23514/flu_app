import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'database_service.dart';

/// Service for backup and restore functionality
class BackupService extends ChangeNotifier {
  static final BackupService instance = BackupService._internal();
  
  final DatabaseService _databaseService = DatabaseService.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

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

  /// Create a backup of all data
  Future<BackupResult> createBackup() async {
    _isBackingUp = true;
    _progress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      // Step 1: Export data from database
      _progress = 0.2;
      notifyListeners();
      
      final exportData = await _databaseService.exportData();
      
      // Step 2: Create backup metadata
      _progress = 0.4;
      notifyListeners();
      
      final backupData = {
        'version': '1.0.0',
        'timestamp': DateTime.now().toIso8601String(),
        'data': exportData,
        'checksum': _generateChecksum(exportData),
      };

      // Step 3: Convert to JSON
      _progress = 0.6;
      notifyListeners();
      
      final jsonData = jsonEncode(backupData);

      // Step 4: Save to file
      _progress = 0.8;
      notifyListeners();
      
      final directory = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${directory.path}/backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${backupDir.path}/backup_$timestamp.json';
      final file = File(filePath);
      await file.writeAsString(jsonData);

      // Step 5: Update last backup date
      _progress = 1.0;
      _lastBackupDate = DateTime.now().toIso8601String();
      await _secureStorage.write(key: _lastBackupKey, value: _lastBackupDate);
      
      _isBackingUp = false;
      notifyListeners();

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

  /// Share backup via WhatsApp
  Future<bool> shareViaWhatsApp() async {
    try {
      // First create the backup
      final result = await createBackup();
      
      if (!result.success || result.filePath == null) {
        _errorMessage = 'Failed to create backup for sharing';
        notifyListeners();
        return false;
      }

      // Share the file
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
        // Also copy to downloads folder if possible
        try {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            final downloadsPath = '${externalDir.path}/FinancialManager';
            final downloadsDir = Directory(downloadsPath);
            if (!await downloadsDir.exists()) {
              await downloadsDir.create(recursive: true);
            }
            
            final sourceFile = File(result.filePath!);
            final destPath = '$downloadsPath/backup_${DateTime.now().millisecondsSinceEpoch}.json';
            await sourceFile.copy(destPath);
            
            return BackupResult(
              success: true,
              filePath: destPath,
              timestamp: result.timestamp,
              sizeBytes: result.sizeBytes,
            );
          }
        } catch (e) {
          // External storage not available, use internal
          if (kDebugMode) {
            print('Could not save to external storage: $e');
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

  /// List available backup files
  Future<List<BackupFile>> listBackups() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${directory.path}/backups');
      
      if (!await backupDir.exists()) {
        return [];
      }

      final files = await backupDir.list().toList();
      final backups = <BackupFile>[];

      for (final entity in files) {
        if (entity is File && entity.path.endsWith('.json')) {
          final stat = await entity.stat();
          final name = entity.path.split('/').last;
          
          backups.add(BackupFile(
            path: entity.path,
            name: name,
            createdAt: stat.modified,
            sizeBytes: stat.size,
          ));
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

  /// Restore from a backup file
  Future<bool> restoreFromFile(String filePath) async {
    _isRestoring = true;
    _progress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      // Step 1: Read backup file
      _progress = 0.2;
      notifyListeners();
      
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Backup file not found');
      }

      final jsonData = await file.readAsString();
      
      // Step 2: Parse and validate backup
      _progress = 0.4;
      notifyListeners();
      
      final backupData = jsonDecode(jsonData) as Map<String, dynamic>;
      
      // Verify checksum
      final data = backupData['data'];
      final storedChecksum = backupData['checksum'];
      final calculatedChecksum = _generateChecksum(data.toString());
      
      if (storedChecksum != calculatedChecksum) {
        throw Exception('Backup file is corrupted');
      }

      // Step 3: Restore data (TODO: Implement actual restore logic)
      _progress = 0.8;
      notifyListeners();
      
      // Note: Actual restore logic would need to:
      // 1. Clear existing data
      // 2. Insert customers
      // 3. Insert loans
      // 4. Insert payments
      // This would require additional methods in DatabaseService

      _progress = 1.0;
      _isRestoring = false;
      notifyListeners();
      
      return true;
    } catch (e) {
      _errorMessage = 'Restore failed: $e';
      _isRestoring = false;
      notifyListeners();
      return false;
    }
  }

  /// Delete a backup file
  Future<bool> deleteBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      _errorMessage = 'Failed to delete backup: $e';
      notifyListeners();
      return false;
    }
  }

  /// Generate a simple checksum for data integrity
  String _generateChecksum(String data) {
    int hash = 0;
    for (int i = 0; i < data.length; i++) {
      hash = ((hash << 5) - hash) + data.codeUnitAt(i);
      hash = hash & hash; // Convert to 32bit integer
    }
    return hash.toRadixString(16);
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

  BackupFile({
    required this.path,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
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
