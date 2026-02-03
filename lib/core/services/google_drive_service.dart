import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// HTTP Client that adds Google Auth headers
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

/// Service for Google Drive backup and restore
class GoogleDriveService extends ChangeNotifier {
  static final GoogleDriveService instance = GoogleDriveService._internal();
  GoogleDriveService._internal();

  // Use drive.file scope instead of appdata for better compatibility
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  bool _isInitialized = false;
  bool _isSignedIn = false;
  String? _lastBackupDate;
  String? _errorMessage;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isSignedIn => _isSignedIn;
  String? get lastBackupDate => _lastBackupDate;
  String? get errorMessage => _errorMessage;
  String? get userEmail => _currentUser?.email;
  String? get userName => _currentUser?.displayName;

  static const String _backupFileName = 'loan_app_backup.db';
  static const String _appFolderName = 'Money Lender';
  
  /// Minimum supported database version for restore
  /// Backups with lower versions will be rejected as incompatible
  static const int minSupportedDbVersion = 10;
  
  String? _appFolderId;

  /// Initialize and attempt silent sign-in
  Future<bool> initialize() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        await _initializeDriveApi();
        _isSignedIn = true;
      }
      _isInitialized = true;
      _errorMessage = null;
      notifyListeners();
      return _isSignedIn;
    } catch (e) {
      debugPrint('Google Drive init error: $e');
      _isInitialized = true;
      _errorMessage = null; // Don't show error for silent sign-in failure
      notifyListeners();
      return false;
    }
  }

  /// Sign in with Google
  Future<bool> signIn() async {
    try {
      _errorMessage = null;
      notifyListeners();
      
      // Disconnect first to force account picker
      await _googleSignIn.signOut();
      
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser != null) {
        await _initializeDriveApi();
        _isSignedIn = true;
        _errorMessage = null;
        notifyListeners();
        return true;
      }
      // User cancelled
      _errorMessage = null;
      notifyListeners();
      return false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException during sign-in: ${e.code} - ${e.message}');
      if (e.code == 'sign_in_failed') {
        _errorMessage = 'Sign-in failed. Please check your Google Play Services and try again.';
      } else if (e.code == 'network_error') {
        _errorMessage = 'Network error. Please check your internet connection.';
      } else {
        _errorMessage = 'Sign-in error: ${e.message ?? e.code}';
      }
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('Sign-in error: $e');
      _errorMessage = 'Failed to sign in. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// Sign out from Google
  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
    _currentUser = null;
    _driveApi = null;
    _isSignedIn = false;
    _appFolderId = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Initialize Drive API with auth headers
  Future<void> _initializeDriveApi() async {
    try {
      final authHeaders = await _currentUser!.authHeaders;
      final client = GoogleAuthClient(authHeaders);
      _driveApi = drive.DriveApi(client);
      // Get or create app folder
      await _getOrCreateAppFolder();
    } catch (e) {
      debugPrint('Failed to initialize Drive API: $e');
      throw Exception('Failed to initialize Drive API');
    }
  }

  /// Get or create app-specific folder in Drive
  Future<void> _getOrCreateAppFolder() async {
    if (_driveApi == null) return;
    
    try {
      // Search for existing folder
      final folderList = await _driveApi!.files.list(
        q: "name = '$_appFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (folderList.files != null && folderList.files!.isNotEmpty) {
        _appFolderId = folderList.files!.first.id;
      } else {
        // Create new folder
        final folder = drive.File()
          ..name = _appFolderName
          ..mimeType = 'application/vnd.google-apps.folder';
        
        final createdFolder = await _driveApi!.files.create(folder);
        _appFolderId = createdFolder.id;
      }
    } catch (e) {
      debugPrint('Error creating app folder: $e');
      _appFolderId = null;
    }
  }

  /// Check if backup exists in Google Drive
  Future<bool> checkForBackup() async {
    if (!_isSignedIn || _driveApi == null) return false;

    try {
      if (_appFolderId == null) await _getOrCreateAppFolder();
      
      final query = _appFolderId != null 
          ? "name = '$_backupFileName' and '$_appFolderId' in parents and trashed = false"
          : "name = '$_backupFileName' and trashed = false";
      
      final fileList = await _driveApi!.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime)',
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        final backupFile = fileList.files!.first;
        _lastBackupDate = backupFile.modifiedTime?.toLocal().toString();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Check backup error: $e');
      _errorMessage = 'Failed to check backup';
      notifyListeners();
      return false;
    }
  }

  /// Upload database to Google Drive
  /// Deletes any existing backup first, then creates a fresh new one
  Future<bool> uploadDatabase(String databasePath) async {
    if (!_isSignedIn || _driveApi == null) {
      _errorMessage = 'Not signed in to Google';
      notifyListeners();
      return false;
    }

    try {
      final dbFile = File(databasePath);
      if (!await dbFile.exists()) {
        _errorMessage = 'Database file not found';
        notifyListeners();
        return false;
      }

      if (_appFolderId == null) await _getOrCreateAppFolder();

      // Delete existing backup(s) first to ensure a fresh upload
      final query = _appFolderId != null 
          ? "name = '$_backupFileName' and '$_appFolderId' in parents and trashed = false"
          : "name = '$_backupFileName' and trashed = false";
      
      final existingFiles = await _driveApi!.files.list(
        q: query,
        spaces: 'drive',
      );

      // Delete all existing backups with this name
      if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
        for (final file in existingFiles.files!) {
          try {
            await _driveApi!.files.delete(file.id!);
            debugPrint('Deleted old backup: ${file.name} (${file.id})');
          } catch (e) {
            debugPrint('Failed to delete old backup ${file.id}: $e');
            // Continue even if delete fails - we'll still try to create new backup
          }
        }
      }

      // Create fresh new backup file
      final driveFile = drive.File()..name = _backupFileName;
      if (_appFolderId != null) {
        driveFile.parents = [_appFolderId!];
      }

      final media = drive.Media(
        dbFile.openRead(),
        await dbFile.length(),
      );

      await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
      );

      _lastBackupDate = DateTime.now().toString();
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Upload error: $e');
      _errorMessage = 'Failed to upload backup';
      notifyListeners();
      return false;
    }
  }

  /// Download database from Google Drive
  Future<String?> downloadDatabase() async {
    if (!_isSignedIn || _driveApi == null) {
      _errorMessage = 'Not signed in to Google';
      notifyListeners();
      return null;
    }

    try {
      if (_appFolderId == null) await _getOrCreateAppFolder();
      
      final query = _appFolderId != null 
          ? "name = '$_backupFileName' and '$_appFolderId' in parents and trashed = false"
          : "name = '$_backupFileName' and trashed = false";

      final fileList = await _driveApi!.files.list(
        q: query,
        spaces: 'drive',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        _errorMessage = 'No backup found';
        notifyListeners();
        return null;
      }

      final fileId = fileList.files!.first.id!;
      
      final response = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      // Save to temp directory first
      final tempDir = await getTemporaryDirectory();
      final tempPath = path.join(tempDir.path, 'restored_backup.db');
      final tempFile = File(tempPath);

      final List<int> dataStore = [];
      await for (final data in response.stream) {
        dataStore.addAll(data);
      }
      await tempFile.writeAsBytes(dataStore);

      _errorMessage = null;
      notifyListeners();
      return tempPath;
    } catch (e) {
      debugPrint('Download error: $e');
      _errorMessage = 'Failed to download backup';
      notifyListeners();
      return null;
    }
  }

  /// Check the database version of a downloaded backup file
  /// Returns the version number, or -1 if unable to determine
  Future<int> getBackupDatabaseVersion(String dbPath) async {
    try {
      final db = await openDatabase(dbPath, readOnly: true);
      final version = await db.getVersion();
      await db.close();
      debugPrint('Backup database version: $version');
      return version;
    } catch (e) {
      debugPrint('Error checking backup version: $e');
      return -1;
    }
  }

  /// Check if a backup is compatible with the current app
  bool isBackupCompatible(int backupVersion) {
    return backupVersion >= minSupportedDbVersion;
  }
  /// Delete backup from Google Drive
  Future<bool> deleteBackup() async {
    if (!_isSignedIn || _driveApi == null) return false;

    try {
      if (_appFolderId == null) await _getOrCreateAppFolder();
      
      final query = _appFolderId != null 
          ? "name = '$_backupFileName' and '$_appFolderId' in parents and trashed = false"
          : "name = '$_backupFileName' and trashed = false";

      final fileList = await _driveApi!.files.list(
        q: query,
        spaces: 'drive',
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        await _driveApi!.files.delete(fileList.files!.first.id!);
        _lastBackupDate = null;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Delete backup error: $e');
      _errorMessage = 'Failed to delete backup';
      notifyListeners();
      return false;
    }
  }

  /// Get backup info
  Future<Map<String, dynamic>?> getBackupInfo() async {
    if (!_isSignedIn || _driveApi == null) return null;

    try {
      if (_appFolderId == null) await _getOrCreateAppFolder();
      
      final query = _appFolderId != null 
          ? "name = '$_backupFileName' and '$_appFolderId' in parents and trashed = false"
          : "name = '$_backupFileName' and trashed = false";

      final fileList = await _driveApi!.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name, size, modifiedTime)',
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        final file = fileList.files!.first;
        return {
          'name': file.name,
          'size': file.size,
          'modifiedTime': file.modifiedTime?.toLocal(),
        };
      }
      return null;
    } catch (e) {
      debugPrint('Get backup info error: $e');
      return null;
    }
  }
}
