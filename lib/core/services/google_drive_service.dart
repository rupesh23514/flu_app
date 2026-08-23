import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/google_oauth_config.dart';
import 'admin_telemetry_service.dart';
import 'database_service.dart';

/// HTTP Client that dynamically fetches fresh Google Auth headers on each request.
/// This prevents stale/expired OAuth tokens from causing silent 401 failures.
class GoogleAuthClient extends http.BaseClient {
  final GoogleSignInAccount _account;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._account);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Fetch fresh auth headers on every request to avoid expired tokens
    final headers = await _account.authHeaders;
    request.headers.addAll(headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
  }
}

/// Service for Google Drive backup and restore
class GoogleDriveService extends ChangeNotifier {
  static final GoogleDriveService instance = GoogleDriveService._internal();
  GoogleDriveService._internal();

  // drive: full access to read/write all files (needed for cross-device backup/restore)
  // Using full 'drive' scope instead of 'drive.file' to ensure backups created
  // on one device can be accessed by the same app on another device.
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const [
      'https://www.googleapis.com/auth/drive',
    ],
    serverClientId:
        GoogleOAuthConfig.isConfigured ? GoogleOAuthConfig.serverClientId : null,
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  GoogleAuthClient? _authClient;  // Track for proper disposal
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
  static const String _folderIdCacheKeyPrefix = 'gdrive_app_folder_id_';
  
  /// Minimum supported database version for restore
  /// Set to 1 to support ALL versions — old databases are auto-migrated on restore
  static const int minSupportedDbVersion = 1;
  
  String? _appFolderId;
  
  /// Get cache key specific to current user email (avoids cross-account folder ID issues)
  String _getCacheKey() {
    final email = _currentUser?.email ?? 'unknown';
    return '$_folderIdCacheKeyPrefix$email';
  }
  
  /// Cache folder ID persistently per account to avoid redundant API calls
  Future<void> _cacheAppFolderId(String? folderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey();
      if (folderId != null) {
        await prefs.setString(cacheKey, folderId);
      } else {
        await prefs.remove(cacheKey);
      }
    } catch (e) {
      debugPrint('Error caching folder ID: $e');
    }
  }
  
  /// Load cached folder ID for current account on startup
  Future<String?> _loadCachedFolderId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_getCacheKey());
    } catch (e) {
      return null;
    }
  }

  /// Initialize and attempt silent sign-in
  Future<bool> initialize() async {
    try {
      if (!GoogleOAuthConfig.isConfigured) {
        _isInitialized = true;
        _isSignedIn = false;
        _errorMessage = GoogleOAuthConfig.setupHint;
        notifyListeners();
        return false;
      }

      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        final driveReady = await _initializeDriveApi();
        _isSignedIn = driveReady;
        if (!driveReady) {
          _currentUser = null;
          _driveApi = null;
        }
      }
      _isInitialized = true;
      _errorMessage = null;
      notifyListeners();
      if (_isSignedIn && _currentUser != null) {
        unawaited(AdminTelemetryService.instance.syncStats(
          email: _currentUser!.email,
          displayName: _currentUser!.displayName,
        ));
      }
      return _isSignedIn;
    } catch (e) {
      debugPrint('Google Drive init error: $e');
      _isInitialized = true;
      _errorMessage = null; // Don't show error for silent sign-in failure
      notifyListeners();
      return false;
    }
  }

  /// Sign in with Google (shows account picker when switching accounts)
  Future<bool> signIn() async {
    if (!GoogleOAuthConfig.isConfigured) {
      _errorMessage = GoogleOAuthConfig.setupHint;
      notifyListeners();
      return false;
    }

    try {
      _errorMessage = null;
      _isSignedIn = false;
      _driveApi = null;
      _appFolderId = null;
      _currentUser = null;
      notifyListeners();

      // Local sign-out only — lets user pick another account without revoking
      // OAuth (disconnect is reserved for explicit Sign Out in settings).
      await _googleSignIn.signOut();

      _currentUser = await _googleSignIn.signIn();
      if (_currentUser == null) {
        _errorMessage = null;
        notifyListeners();
        return false;
      }

      final driveReady = await _initializeDriveApi();
      if (!driveReady) {
        _currentUser = null;
        _isSignedIn = false;
        _driveApi = null;
        notifyListeners();
        return false;
      }

      _isSignedIn = true;
      _errorMessage = null;
      notifyListeners();
      
      // Track sign-in and check suspension status
      final telemetry = AdminTelemetryService.instance;
      unawaited(telemetry.trackSignIn(
        email: _currentUser!.email,
        displayName: _currentUser!.displayName,
      ));
      
      // Check suspension status immediately after sign-in
      if (telemetry.isEnabled) {
        final status = await telemetry.checkAccountStatus(email: _currentUser!.email);
        if (status.isSuspended) {
          debugPrint('Account suspended: ${status.reason}');
          // Don't sign out - let the app show the suspended screen
          // The UI will be updated via the telemetry service cache
        }
      }
      
      return true;
    } on PlatformException catch (e) {
      debugPrint('PlatformException during sign-in: ${e.code} - ${e.message}');
      _currentUser = null;
      _isSignedIn = false;
      _driveApi = null;
      if (e.code == 'sign_in_failed') {
        _errorMessage = _mapSignInFailedMessage(e.message);
      } else if (e.code == 'network_error') {
        _errorMessage =
            'Network error. Please check your internet connection.';
      } else {
        _errorMessage = 'Sign-in error: ${e.message ?? e.code}';
      }
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('Sign-in error: $e');
      _currentUser = null;
      _isSignedIn = false;
      _driveApi = null;
      _errorMessage = _mapDriveError(e);
      notifyListeners();
      return false;
    }
  }

  String _mapSignInFailedMessage(String? detail) {
    final text = (detail ?? '').toLowerCase();
    if (text.contains('10') ||
        text.contains('developer_error') ||
        text.contains('apiexception')) {
      return 'Google sign-in configuration error. Ensure your Gmail is added as '
          'an OAuth test user in Google Cloud Console, then try again.';
    }
    return 'Sign-in failed. Please check Google Play Services and try again.';
  }

  String _mapDriveError(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('401') || text.contains('unauthenticated')) {
      return 'Google sign-in expired. Please sign in again.';
    }
    if (text.contains('403') || text.contains('permission')) {
      return 'Drive permission denied. Check OAuth scopes in Google Cloud.';
    }
    if (text.contains('network') || text.contains('socket')) {
      return 'Network error. Please check your internet connection.';
    }
    return 'Failed to connect to Google Drive. Please try again.';
  }

  /// Sign out from Google
  Future<void> signOut() async {
    final email = _currentUser?.email;
    // Clear folder ID cache for this account before losing email reference
    if (email != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('$_folderIdCacheKeyPrefix$email');
      } catch (e) {
        debugPrint('Error clearing folder cache: $e');
      }
    }
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
    // Close HTTP client to release connection pool
    _authClient?.close();
    _authClient = null;
    _currentUser = null;
    _driveApi = null;
    _isSignedIn = false;
    _appFolderId = null;
    _errorMessage = null;
    notifyListeners();
    if (email != null) {
      unawaited(AdminTelemetryService.instance.trackSignOut(email: email));
    }
  }

  /// Initialize Drive API with auth client and verify access.
  /// The GoogleAuthClient fetches fresh tokens on each request,
  /// so this only needs to be called once per sign-in session.
  /// Optimized: Uses cached folder ID when available to reduce API calls.
  Future<bool> _initializeDriveApi() async {
    if (_currentUser == null) return false;

    try {
      // Close previous client to release connection pool
      _authClient?.close();
      
      _authClient = GoogleAuthClient(_currentUser!);
      _driveApi = drive.DriveApi(_authClient!);

      // Try to use cached folder ID first (faster startup)
      _appFolderId = await _loadCachedFolderId();
      
      // Verify access and get/create folder in one operation
      // The folder operation also serves as access verification
      await _getOrCreateAppFolder();
      return true;
    } catch (e) {
      debugPrint('Failed to initialize Drive API: $e');
      _driveApi = null;
      _appFolderId = null;
      await _cacheAppFolderId(null);
      _errorMessage = _mapDriveError(e);
      return false;
    }
  }

  /// Get or create app-specific folder in Drive
  /// Optimized: Uses cached folder ID and validates it before searching
  Future<void> _getOrCreateAppFolder() async {
    if (_driveApi == null) return;
    
    try {
      // If we have a cached folder ID, validate it's still accessible
      if (_appFolderId != null) {
        try {
          await _driveApi!.files.get(_appFolderId!, $fields: 'id,trashed');
          // Folder is valid, we're done (fast path)
          return;
        } catch (e) {
          // Cached folder not found or inaccessible, search for it
          debugPrint('Cached folder invalid, searching: $e');
          _appFolderId = null;
        }
      }
      
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
      
      // Cache the folder ID for future sessions
      await _cacheAppFolderId(_appFolderId);
    } catch (e) {
      debugPrint('Error creating app folder: $e');
      _appFolderId = null;
      await _cacheAppFolderId(null);
    }
  }

  /// Check if backup exists in Google Drive
  /// Uses multiple fallback search strategies to find backups across devices
  Future<bool> checkForBackup() async {
    if (!_isSignedIn || _driveApi == null) return false;

    try {
      debugPrint('Checking for backup in Google Drive...');
      
      // Strategy 1: Search for backup file ANYWHERE in Drive first (most reliable for cross-device)
      // This uses the full 'drive' scope to find files regardless of which device created them
      debugPrint('Strategy 1: Searching entire Drive for $_backupFileName');
      final anywhereResult = await _driveApi!.files.list(
        q: "name = '$_backupFileName' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime, parents)',
        orderBy: 'modifiedTime desc',
      );
      
      if (anywhereResult.files != null && anywhereResult.files!.isNotEmpty) {
        final backupFile = anywhereResult.files!.first;
        debugPrint('Found backup via Strategy 1: ${backupFile.id}, modified: ${backupFile.modifiedTime}');
        _lastBackupDate = backupFile.modifiedTime?.toLocal().toString();
        
        // Cache the parent folder ID if available (for faster future access)
        if (backupFile.parents != null && backupFile.parents!.isNotEmpty) {
          _appFolderId = backupFile.parents!.first;
          await _cacheAppFolderId(_appFolderId);
        }
        
        notifyListeners();
        return true;
      }
      debugPrint('Strategy 1: No files found');

      // Strategy 2: Look inside known app folder (if we have the ID)
      if (_appFolderId == null) await _getOrCreateAppFolder();
      
      if (_appFolderId != null) {
        debugPrint('Strategy 2: Searching in folder $_appFolderId');
        final folderResult = await _driveApi!.files.list(
          q: "name = '$_backupFileName' and '$_appFolderId' in parents and trashed = false",
          spaces: 'drive',
          $fields: 'files(id, name, modifiedTime)',
        );
        if (folderResult.files != null && folderResult.files!.isNotEmpty) {
          final backupFile = folderResult.files!.first;
          debugPrint('Found backup via Strategy 2');
          _lastBackupDate = backupFile.modifiedTime?.toLocal().toString();
          notifyListeners();
          return true;
        }
        debugPrint('Strategy 2: No files found in folder');
      }

      // Strategy 3: Search for ALL 'Money Lender' folders and check inside each
      debugPrint('Strategy 3: Searching all Money Lender folders');
      final folderSearch = await _driveApi!.files.list(
        q: "name = '$_appFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      
      if (folderSearch.files != null && folderSearch.files!.isNotEmpty) {
        debugPrint('Found ${folderSearch.files!.length} Money Lender folder(s)');
        for (final folder in folderSearch.files!) {
          final dbSearch = await _driveApi!.files.list(
            q: "'${folder.id}' in parents and trashed = false and name = '$_backupFileName'",
            spaces: 'drive',
            $fields: 'files(id, name, modifiedTime)',
            orderBy: 'modifiedTime desc',
          );
          if (dbSearch.files != null && dbSearch.files!.isNotEmpty) {
            final backupFile = dbSearch.files!.first;
            debugPrint('Found backup in folder ${folder.id}');
            _lastBackupDate = backupFile.modifiedTime?.toLocal().toString();
            // Update our folder reference to this one
            _appFolderId = folder.id;
            await _cacheAppFolderId(_appFolderId);
            notifyListeners();
            return true;
          }
        }
      }
      debugPrint('Strategy 3: No backup found in any folder');

      // Strategy 4: Search for .db files in case the name is slightly different
      debugPrint('Strategy 4: Searching for any .db backup files');
      final dbFilesResult = await _driveApi!.files.list(
        q: "name contains 'backup' and name contains '.db' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime)',
        orderBy: 'modifiedTime desc',
      );
      
      if (dbFilesResult.files != null && dbFilesResult.files!.isNotEmpty) {
        for (final file in dbFilesResult.files!) {
          if (file.name == _backupFileName || file.name == 'loan_app_backup.db') {
            debugPrint('Found backup via Strategy 4: ${file.name}');
            _lastBackupDate = file.modifiedTime?.toLocal().toString();
            notifyListeners();
            return true;
          }
        }
      }

      debugPrint('No backup found with any strategy');
      return false;
    } catch (e) {
      debugPrint('Check backup error: $e');
      _errorMessage = 'Failed to check backup: ${e.toString().split(':').last.trim()}';
      notifyListeners();
      return false;
    }
  }

  /// Upload database to Google Drive
  /// Deletes any existing backup first, then creates a fresh new one.
  /// Automatically retries once with re-authentication on auth errors.
  Future<bool> uploadDatabase(String databasePath) async {
    if (!GoogleOAuthConfig.isConfigured) {
      _errorMessage = GoogleOAuthConfig.setupHint;
      notifyListeners();
      return false;
    }

    if (!_isSignedIn || _driveApi == null) {
      _errorMessage = 'Not signed in to Google';
      notifyListeners();
      return false;
    }

    try {
      final success = await _uploadDatabaseInternal(databasePath);
      if (success) {
        unawaited(AdminTelemetryService.instance.trackBackupSuccess(
          email: _currentUser?.email,
        ));
      } else {
        unawaited(AdminTelemetryService.instance.trackBackupFailed(
          email: _currentUser?.email,
          error: _errorMessage,
        ));
      }
      return success;
    } catch (e) {
      // On auth/permission errors, try re-authenticating once
      final errText = e.toString().toLowerCase();
      if (errText.contains('401') ||
          errText.contains('403') ||
          errText.contains('unauthenticated') ||
          errText.contains('invalid credentials') ||
          errText.contains('token')) {
        debugPrint('Upload auth error — attempting re-authentication: $e');
        final reauthed = await _reAuthenticate();
        if (reauthed) {
          try {
            final retrySuccess = await _uploadDatabaseInternal(databasePath);
            if (retrySuccess) {
              unawaited(AdminTelemetryService.instance.trackBackupSuccess(
                email: _currentUser?.email,
              ));
            } else {
              unawaited(AdminTelemetryService.instance.trackBackupFailed(
                email: _currentUser?.email,
                error: _errorMessage,
              ));
            }
            return retrySuccess;
          } catch (retryError) {
            debugPrint('Upload retry failed: $retryError');
            _errorMessage = 'Upload failed: ${retryError.toString().split(':').last.trim()}';
            notifyListeners();
            return false;
          }
        }
      }
      debugPrint('Upload error: $e');
      _errorMessage = _mapDriveError(e);
      notifyListeners();
      unawaited(AdminTelemetryService.instance.trackBackupFailed(
        email: _currentUser?.email,
        error: e.toString(),
      ));
      return false;
    }
  }

  /// Internal upload logic (extracted for retry)
  /// Uploads new backup first, then deletes old backups to ensure data safety.
  Future<bool> _uploadDatabaseInternal(String databasePath) async {
    final dbFile = File(databasePath);
    if (!await dbFile.exists()) {
      _errorMessage = 'Database file not found';
      notifyListeners();
      return false;
    }

    if (_appFolderId == null) {
      await _getOrCreateAppFolder();
    }

    // Query for existing backups (we'll delete them AFTER successful upload)
    final query = _appFolderId != null 
        ? "name = '$_backupFileName' and '$_appFolderId' in parents and trashed = false"
        : "name = '$_backupFileName' and trashed = false";

    final existingFiles = await _driveApi!.files.list(
      q: query,
      spaces: 'drive',
    );

    // Create new backup file FIRST (before deleting old ones)
    final driveFile = drive.File()..name = _backupFileName;
    if (_appFolderId != null) {
      driveFile.parents = [_appFolderId!];
    }

    final media = drive.Media(
      dbFile.openRead(),
      await dbFile.length(),
    );

    // Upload new backup - if this fails, old backup is preserved
    await _driveApi!.files.create(
      driveFile,
      uploadMedia: media,
    );

    // Upload succeeded - now safe to delete old backup(s)
    if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
      for (final file in existingFiles.files!) {
        try {
          await _driveApi!.files.delete(file.id!);
          debugPrint('Deleted old backup: ${file.name} (${file.id})');
        } catch (e) {
          debugPrint('Failed to delete old backup ${file.id}: $e');
          // Non-critical: old backup remains but new one is uploaded
        }
      }
    }

    _lastBackupDate = DateTime.now().toString();
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  /// Re-authenticate with Google and reinitialize the Drive API.
  /// Used when a request fails due to expired/revoked tokens.
  Future<bool> _reAuthenticate() async {
    try {
      debugPrint('Re-authenticating Google sign-in...');
      // signInSilently refreshes the access token without user interaction
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser == null) {
        // Silent refresh failed — try interactive sign-in
        _currentUser = await _googleSignIn.signIn();
      }
      if (_currentUser == null) {
        _isSignedIn = false;
        _driveApi = null;
        _errorMessage = 'Re-authentication failed. Please sign in again.';
        notifyListeners();
        return false;
      }
      final driveReady = await _initializeDriveApi();
      _isSignedIn = driveReady;
      if (!driveReady) {
        _errorMessage = 'Could not reconnect to Google Drive.';
      }
      notifyListeners();
      return driveReady;
    } catch (e) {
      debugPrint('Re-authentication error: $e');
      _errorMessage = 'Re-authentication failed. Please sign in again.';
      notifyListeners();
      return false;
    }
  }

  /// Download database from Google Drive
  /// Uses multiple fallback search strategies to find backups across devices
  Future<String?> downloadDatabase() async {
    if (!_isSignedIn || _driveApi == null) {
      _errorMessage = 'Not signed in to Google';
      notifyListeners();
      return null;
    }

    try {
      debugPrint('Searching for backup to download...');
      String? fileId;

      // Strategy 1: Search ANYWHERE in Drive first (most reliable for cross-device)
      debugPrint('Download Strategy 1: Global search');
      final anywhereResult = await _driveApi!.files.list(
        q: "name = '$_backupFileName' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime, parents)',
        orderBy: 'modifiedTime desc',
      );
      if (anywhereResult.files != null && anywhereResult.files!.isNotEmpty) {
        fileId = anywhereResult.files!.first.id;
        debugPrint('Found backup via Strategy 1: $fileId');
        
        // Cache the parent folder for future operations
        final parents = anywhereResult.files!.first.parents;
        if (parents != null && parents.isNotEmpty) {
          _appFolderId = parents.first;
          await _cacheAppFolderId(_appFolderId);
        }
      }

      // Strategy 2: Search inside known app folder
      if (fileId == null && _appFolderId == null) {
        await _getOrCreateAppFolder();
      }
      
      if (fileId == null && _appFolderId != null) {
        debugPrint('Download Strategy 2: Folder search in $_appFolderId');
        final folderResult = await _driveApi!.files.list(
          q: "name = '$_backupFileName' and '$_appFolderId' in parents and trashed = false",
          spaces: 'drive',
          $fields: 'files(id)',
          orderBy: 'modifiedTime desc',
        );
        if (folderResult.files != null && folderResult.files!.isNotEmpty) {
          fileId = folderResult.files!.first.id;
          debugPrint('Found backup via Strategy 2: $fileId');
        }
      }

      // Strategy 3: Search all 'Money Lender' folders
      if (fileId == null) {
        debugPrint('Download Strategy 3: Search all Money Lender folders');
        final folderSearch = await _driveApi!.files.list(
          q: "name = '$_appFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
          spaces: 'drive',
          $fields: 'files(id, name)',
        );
        if (folderSearch.files != null && folderSearch.files!.isNotEmpty) {
          for (final folder in folderSearch.files!) {
            final dbSearch = await _driveApi!.files.list(
              q: "'${folder.id}' in parents and trashed = false and name = '$_backupFileName'",
              spaces: 'drive',
              $fields: 'files(id)',
              orderBy: 'modifiedTime desc',
            );
            if (dbSearch.files != null && dbSearch.files!.isNotEmpty) {
              fileId = dbSearch.files!.first.id;
              _appFolderId = folder.id;
              await _cacheAppFolderId(_appFolderId);
              debugPrint('Found backup via Strategy 3 in folder ${folder.id}');
              break;
            }
          }
        }
      }

      // Strategy 4: Broader search for any .db backup file
      if (fileId == null) {
        debugPrint('Download Strategy 4: Broad .db search');
        final dbFilesResult = await _driveApi!.files.list(
          q: "name contains 'backup' and name contains '.db' and trashed = false",
          spaces: 'drive',
          $fields: 'files(id, name)',
          orderBy: 'modifiedTime desc',
        );
        if (dbFilesResult.files != null && dbFilesResult.files!.isNotEmpty) {
          for (final file in dbFilesResult.files!) {
            if (file.name == _backupFileName || file.name == 'loan_app_backup.db') {
              fileId = file.id;
              debugPrint('Found backup via Strategy 4: ${file.name}');
              break;
            }
          }
        }
      }

      if (fileId == null) {
        debugPrint('No backup found with any strategy');
        _errorMessage = 'No backup found in Google Drive';
        notifyListeners();
        return null;
      }
      
      final response = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      // Stream directly to file to avoid memory accumulation for large backups
      final tempDir = await getTemporaryDirectory();
      final tempPath = path.join(tempDir.path, 'restored_backup.db');
      final tempFile = File(tempPath);
      
      final sink = tempFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

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

  /// Check if a backup is compatible with the current app.
  /// Versions v1 through v[DatabaseService.currentVersion] are supported —
  /// old databases auto-migrate on restore. Versions newer than the app are rejected.
  bool isBackupCompatible(int backupVersion) {
    return backupVersion >= minSupportedDbVersion &&
        backupVersion <= DatabaseService.currentVersion;
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
