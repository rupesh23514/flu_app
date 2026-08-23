import 'dart:io';
import 'package:flutter/foundation.dart';
import 'google_drive_service.dart';
import 'backup_encryption_service.dart';
import 'database_service.dart';

/// Result of a restore operation
class RestoreResult {
  final bool success;
  final String? errorMessage;
  final bool versionIncompatible;
  final int? backupVersion;

  const RestoreResult({
    required this.success,
    this.errorMessage,
    this.versionIncompatible = false,
    this.backupVersion,
  });

  factory RestoreResult.success() => const RestoreResult(success: true);

  factory RestoreResult.failure(String message) => RestoreResult(
        success: false,
        errorMessage: message,
      );

  factory RestoreResult.incompatibleVersion(int version) => RestoreResult(
        success: false,
        errorMessage:
            'This backup was created by a newer version of the app '
            '(database v$version, app supports up to v${DatabaseService.currentVersion}). '
            'Please update the app to the latest version and try again.',
        versionIncompatible: true,
        backupVersion: version,
      );
}

/// Centralized service for restoring data from Google Drive
/// Used by both BackupScreen and AppLockScreen to avoid code duplication
class RestoreHelperService {
  static final RestoreHelperService instance = RestoreHelperService._internal();
  RestoreHelperService._internal();

  final GoogleDriveService _driveService = GoogleDriveService.instance;
  final BackupEncryptionService _encryptionService = BackupEncryptionService.instance;

  /// Restore data from Google Drive
  /// Returns a RestoreResult indicating success or failure with details
  Future<RestoreResult> restoreFromGoogleDrive({
    bool signInIfNeeded = true,
  }) async {
    String? downloadPath;
    String? pathToRestore;

    try {
      // Initialize services
      await _driveService.initialize();
      await _encryptionService.initialize();

      // Sign in if not already signed in
      if (!_driveService.isSignedIn) {
        if (!signInIfNeeded) {
          return RestoreResult.failure('Not signed in to Google');
        }
        final signedIn = await _driveService.signIn();
        if (!signedIn) {
          return RestoreResult.failure(
            _driveService.errorMessage ?? 'Failed to sign in to Google',
          );
        }
      }

      // Check for backup
      final hasBackup = await _driveService.checkForBackup();
      if (!hasBackup) {
        return RestoreResult.failure('No backup found in Google Drive');
      }

      // Download backup
      downloadPath = await _driveService.downloadDatabase();
      if (downloadPath == null) {
        return RestoreResult.failure(
          _driveService.errorMessage ?? 'Download failed',
        );
      }

      pathToRestore = downloadPath;

      // Decrypt if encrypted (backward compat for older encrypted backups)
      final isEncrypted = await _encryptionService.isFileEncrypted(downloadPath);
      if (isEncrypted) {
        final decryptedPath = await _encryptionService.decryptFile(downloadPath);
        if (decryptedPath == null) {
          // Decryption failed — likely wrong key (different device)
          return RestoreResult.failure(
            'This backup was encrypted on a different device and cannot be '
            'decrypted here. Please open the app on your old device, '
            'backup again (the new version uploads without encryption), '
            'then restore on this device.',
          );
        }
        pathToRestore = decryptedPath;
      }

      // Check backup version BEFORE restoring — give user-friendly error
      final backupVersion = await _driveService.getBackupDatabaseVersion(pathToRestore);
      debugPrint('Backup database version: $backupVersion (app supports v1-v${DatabaseService.currentVersion})');

      if (!_driveService.isBackupCompatible(backupVersion)) {
        if (backupVersion > DatabaseService.currentVersion) {
          return RestoreResult.incompatibleVersion(backupVersion);
        }
        return RestoreResult.failure(
          'Backup has an invalid database version ($backupVersion). '
          'The file may be corrupted.',
        );
      }

      // Restore database — handles migration from any version automatically
      final success = await DatabaseService.instance.restoreFromFile(pathToRestore);

      if (success) {
        return RestoreResult.success();
      } else {
        // Use the detailed error from DatabaseService if available
        final detailedError = DatabaseService.instance.lastRestoreError;
        return RestoreResult.failure(
          detailedError ?? 'Restore failed. Database may be corrupted.',
        );
      }
    } catch (e) {
      debugPrint('RestoreHelperService error: $e');
      return RestoreResult.failure(
        'Restore failed: ${e.toString().split(':').last.trim()}',
      );
    } finally {
      // Robust cleanup of temp files - always attempt cleanup
      await _cleanupTempFiles(downloadPath, pathToRestore);
    }
  }

  /// Securely cleanup temporary files used during restore
  /// Logs errors instead of silently ignoring them
  Future<void> _cleanupTempFiles(String? downloadPath, String? pathToRestore) async {
    if (downloadPath != null) {
      try {
        final downloadFile = File(downloadPath);
        if (await downloadFile.exists()) {
          await downloadFile.delete();
          debugPrint('🧹 Cleaned up temp download file: $downloadPath');
        }
      } catch (e) {
        debugPrint('⚠️ Failed to delete temp download file: $downloadPath, error: $e');
        // Attempt to overwrite with zeros before failing (secure delete)
        try {
          final file = File(downloadPath);
          if (await file.exists()) {
            await file.writeAsBytes(List.filled(1024, 0));
            await file.delete();
          }
        } catch (_) {
          debugPrint('⚠️ Could not securely delete temp file: $downloadPath');
        }
      }
    }

    if (pathToRestore != null && pathToRestore != downloadPath) {
      try {
        final restoreFile = File(pathToRestore);
        if (await restoreFile.exists()) {
          await restoreFile.delete();
          debugPrint('🧹 Cleaned up decrypted temp file: $pathToRestore');
        }
      } catch (e) {
        debugPrint('⚠️ Failed to delete decrypted temp file: $pathToRestore, error: $e');
        // Attempt secure delete for decrypted file (contains sensitive data)
        try {
          final file = File(pathToRestore);
          if (await file.exists()) {
            // Overwrite with zeros before deleting
            final length = await file.length();
            await file.writeAsBytes(List.filled(length.clamp(0, 1024 * 1024), 0));
            await file.delete();
          }
        } catch (_) {
          debugPrint('⚠️ Could not securely delete decrypted temp file: $pathToRestore');
        }
      }
    }
  }
}
