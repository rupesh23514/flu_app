// ignore_for_file: unused_element
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/google_drive_service.dart';
import '../../../core/services/excel_export_service.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/services/migration_safety_service.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/backup_encryption_service.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/localization/app_localizations.dart';
import '../../authentication/providers/auth_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _autoLockTime = 30;
  bool _isLoading = false;

  // Backup state
  final GoogleDriveService _driveService = GoogleDriveService.instance;
  final ExcelExportService _excelService = ExcelExportService.instance;
  bool _isGoogleSignedIn = false;
  bool _autoBackupEnabled = false;
  String? _lastBackupDate;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool _isExporting = false;
  bool _hasInternet = true;

  // Connectivity subscription to be cancelled on dispose
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadBackupState();
    _checkConnectivity();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    // connectivity_plus checkConnectivity() returns ConnectivityResult
    final ConnectivityResult result = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _hasInternet = result != ConnectivityResult.none;
      });
    }

    // Listen for connectivity changes - returns stream of ConnectivityResult
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      if (mounted) {
        setState(() {
          _hasInternet = result != ConnectivityResult.none;
        });
      }
    });
  }

  Future<void> _loadBackupState() async {
    await _driveService.initialize();

    // Load auto backup preference from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedAutoBackup = prefs.getBool('autoBackupEnabled') ?? false;

    if (mounted) {
      setState(() {
        _isGoogleSignedIn = _driveService.isSignedIn;
        _lastBackupDate = _driveService.lastBackupDate;
        _autoBackupEnabled = savedAutoBackup;
      });

      if (_isGoogleSignedIn) {
        await _driveService.checkForBackup();
        if (mounted) {
          setState(() {
            _lastBackupDate = _driveService.lastBackupDate;
          });
        }
      }
    }
  }

  Future<void> _loadSettings() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    // Load auto-lock time from secure storage, not just in-memory value
    final autoLockTime = await authProvider.getAutoLockTime();

    if (!mounted) return;
    setState(() {
      _autoLockTime = autoLockTime;
    });
  }

  Future<void> _updateAutoLockTime(int seconds) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.setAutoLockTime(seconds);

    if (!mounted) return;
    setState(() {
      _autoLockTime = seconds;
      _isLoading = false;
    });
  }

  Future<void> _signInToGoogle() async {
    if (!_hasInternet) {
      _showNoConnectionMessage();
      return;
    }

    setState(() => _isLoading = true);

    final success = await _driveService.signIn();

    if (mounted) {
      setState(() {
        _isGoogleSignedIn = success;
        _isLoading = false;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signed in to Google successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        await _driveService.checkForBackup();
        if (mounted) {
          setState(() {
            _lastBackupDate = _driveService.lastBackupDate;
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_driveService.errorMessage ?? 'Failed to sign in'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _signOutFromGoogle() async {
    await _driveService.signOut();
    if (mounted) {
      setState(() {
        _isGoogleSignedIn = false;
        _lastBackupDate = null;
      });
    }
  }

  Future<void> _backupNow() async {
    if (!_hasInternet) {
      _showNoConnectionMessage();
      return;
    }

    if (!_isGoogleSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to Google first'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isBackingUp = true);

    try {
      // Initialize encryption service
      final encryptionService = BackupEncryptionService.instance;
      await encryptionService.initialize();
      
      // Create a safe database copy before uploading to avoid corrupting active database
      final dbPath = await DatabaseService.instance.getDatabasePath();
      final tempCopyPath = await DatabaseService.instance.createSafeCopy();
      final safeCopyPath = tempCopyPath ?? dbPath;
      
      // Encrypt the backup before uploading to protect sensitive financial data
      final encryptedPath = await encryptionService.encryptFile(safeCopyPath);
      final pathToUpload = encryptedPath ?? safeCopyPath; // Fallback to unencrypted if encryption fails
      
      final success = await _driveService.uploadDatabase(pathToUpload);
      
      // Clean up temp files
      if (tempCopyPath != null) {
        try {
          await File(tempCopyPath).delete();
        } catch (_) {}
      }
      if (encryptedPath != null) {
        try {
          await File(encryptedPath).delete();
        } catch (_) {}
      }

      if (mounted) {
        if (success) {
          await _driveService.checkForBackup();
          if (mounted) {
            setState(() {
              _lastBackupDate = _driveService.lastBackupDate;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Backup completed successfully!'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_driveService.errorMessage ?? 'Backup failed'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Backup error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup failed. Please try again later.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  Future<void> _restoreFromCloud() async {
    if (!_hasInternet) {
      _showNoConnectionMessage();
      return;
    }

    if (!_isGoogleSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to Google first'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // Check if backup exists
    final hasBackup = await _driveService.checkForBackup();
    if (!hasBackup) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No backup found in Google Drive'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    // Check if there's existing data
    final customerCount = await DatabaseService.instance.getCustomerCount();
    final loanCount = await DatabaseService.instance.getLoanCount();

    String dialogContent =
        'This will replace all current data with the backup from Google Drive. This action cannot be undone.\n\nAre you sure you want to continue?';

    if (customerCount > 0 || loanCount > 0) {
      dialogContent = 'WARNING: You currently have:\n'
          '• $customerCount customers\n'
          '• $loanCount loans\n\n'
          'This restore will DELETE ALL existing data and replace it with the backup from Google Drive.\n\n'
          'This action cannot be undone. Are you absolutely sure?';
    }

    // Show confirmation dialog
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.warning),
            SizedBox(width: 8),
            Text('Restore from Cloud'),
          ],
        ),
        content: Text(dialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) return;

    setState(() => _isRestoring = true);

    try {
      // Download backup from Google Drive
      final tempPath = await _driveService.downloadDatabase();

      if (tempPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_driveService.errorMessage ?? 'No backup found'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      // Decrypt the backup if it's encrypted
      final encryptionService = BackupEncryptionService.instance;
      await encryptionService.initialize();
      
      String pathToRestore = tempPath;
      final isEncrypted = await encryptionService.isFileEncrypted(tempPath);
      
      if (isEncrypted) {
        final decryptedPath = await encryptionService.decryptFile(tempPath);
        if (decryptedPath != null) {
          pathToRestore = decryptedPath;
        }
      }

      // Check backup database version compatibility before restoring
      final backupVersion = await _driveService.getBackupDatabaseVersion(pathToRestore);
      
      if (backupVersion > 0 && !_driveService.isBackupCompatible(backupVersion)) {
        // Clean up temp files
        try {
          await File(tempPath).delete();
          if (pathToRestore != tempPath) {
            await File(pathToRestore).delete();
          }
        } catch (_) {}
        
        if (mounted) {
          setState(() => _isRestoring = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'This backup is from an older app version (database v$backupVersion) and is not compatible. '
                'Minimum required version is ${GoogleDriveService.minSupportedDbVersion}. '
                'Please create a new backup with the latest app.',
              ),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 6),
            ),
          );
        }
        return;
      }

      // Restore database from downloaded/decrypted file
      final success = await DatabaseService.instance.restoreFromFile(pathToRestore);
      
      // Clean up temp files
      try {
        await File(tempPath).delete();
        if (pathToRestore != tempPath) {
          await File(pathToRestore).delete();
        }
      } catch (_) {}

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Data restored successfully! Please restart the app to see changes.'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Failed to restore data. Database may be corrupted.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Restore error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Restore failed. Please try again later.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<void> _exportToExcel() async {
    setState(() => _isExporting = true);

    try {
      final success = await _excelService.exportAndShare();

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Excel file exported successfully!'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to export Excel file'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export failed. Please try again later.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showNoConnectionMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.white),
            SizedBox(width: 8),
            Text('No internet connection'),
          ],
        ),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _showAutoLockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auto Lock Time'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<int>(
                title: const Text('30 seconds',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                value: 30,
                // ignore: deprecated_member_use
                groupValue: _autoLockTime,
                // ignore: deprecated_member_use
                onChanged: (value) {
                  Navigator.pop(context);
                  if (value != null) _updateAutoLockTime(value);
                },
              ),
              RadioListTile<int>(
                title: const Text('1 minute',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                value: 60,
                // ignore: deprecated_member_use
                groupValue: _autoLockTime,
                // ignore: deprecated_member_use
                onChanged: (value) {
                  Navigator.pop(context);
                  if (value != null) _updateAutoLockTime(value);
                },
              ),
              RadioListTile<int>(
                title: const Text('5 minutes',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                value: 300,
                // ignore: deprecated_member_use
                groupValue: _autoLockTime,
                // ignore: deprecated_member_use
                onChanged: (value) {
                  Navigator.pop(context);
                  if (value != null) _updateAutoLockTime(value);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showChangePinDialog() {
    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    // Get scaffoldMessenger from parent context before showing dialog
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    // Get auth provider from parent context before showing dialog
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ChangePinDialog(
        currentPinController: currentPinController,
        newPinController: newPinController,
        confirmPinController: confirmPinController,
        authProvider: authProvider,
        scaffoldMessenger: scaffoldMessenger,
      ),
    );
  }

  String _getAutoLockTimeText() {
    if (_autoLockTime < 60) {
      return '$_autoLockTime seconds';
    } else {
      final minutes = _autoLockTime ~/ 60;
      return '$minutes minute${minutes > 1 ? 's' : ''}';
    }
  }

  String _formatBackupDate(String? dateStr) {
    if (dateStr == null) return 'Never';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes} min ago';
      if (diff.inDays < 1) return '${diff.inHours} hours ago';
      if (diff.inDays < 7) return '${diff.inDays} days ago';

      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Google Drive Backup Section
          _buildBackupSection(),

          const SizedBox(height: 16),

          // Export Section
          _buildExportSection(),

          const SizedBox(height: 16),

          // Security Section
          _buildSecuritySection(),

          const SizedBox(height: 16),

          // App Section
          _buildAppSection(),

          const SizedBox(height: 32),

          // Logout button
          _buildLogoutButton(),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildBackupSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Google Drive Backup',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Connection Status
            if (!_hasInternet)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: AppColors.error, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No internet connection',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),

            // Sign-in Status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isGoogleSignedIn
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isGoogleSignedIn
                      ? AppColors.success.withValues(alpha: 0.3)
                      : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          _isGoogleSignedIn ? AppColors.success : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isGoogleSignedIn ? Icons.check : Icons.cloud_off,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _isGoogleSignedIn ? 'Synced ✓' : 'Not connected',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _isGoogleSignedIn
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (_isGoogleSignedIn &&
                            _driveService.userEmail != null)
                          Text(
                            _driveService.userEmail!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (_isGoogleSignedIn && _lastBackupDate != null)
                          Text(
                            'Last backup: ${_formatBackupDate(_lastBackupDate)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (!_isGoogleSignedIn)
                          const Text(
                            'Sign in to backup your data',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!_isGoogleSignedIn)
                    Flexible(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signInToGoogle,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const FittedBox(child: Text('Sign In')),
                      ),
                    ),
                  if (_isGoogleSignedIn)
                    IconButton(
                      icon: const Icon(Icons.logout,
                          color: AppColors.error, size: 22),
                      onPressed: _signOutFromGoogle,
                      tooltip: 'Sign out',
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Auto Backup Toggle
            SwitchListTile(
              value: _autoBackupEnabled,
              onChanged: _isGoogleSignedIn
                  ? (value) async {
                      setState(() => _autoBackupEnabled = value);
                      // Save preference in shared preferences
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('autoBackupEnabled', value);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(value 
                                ? 'Auto backup enabled - weekly backups scheduled' 
                                : 'Auto backup disabled'),
                            backgroundColor: value ? AppColors.success : AppColors.textSecondary,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  : null,
              title: const Text('Auto Backup'),
              subtitle: const Text('Automatically backup weekly'),
              secondary: Icon(
                Icons.schedule,
                color: _autoBackupEnabled && _isGoogleSignedIn
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),

            const Divider(),

            // Backup Now Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isGoogleSignedIn && !_isBackingUp && _hasInternet)
                    ? _backupNow
                    : null,
                icon: _isBackingUp
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.backup),
                label: Text(_isBackingUp ? 'Backing up...' : 'Backup Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Restore from Cloud Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_isGoogleSignedIn && !_isRestoring && _hasInternet)
                    ? _restoreFromCloud
                    : null,
                icon: _isRestoring
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download),
                label:
                    Text(_isRestoring ? 'Restoring...' : 'Restore from Cloud'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.file_download, color: AppColors.secondary),
                const SizedBox(width: 8),
                Text(
                  'Export Data',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.table_chart, color: Colors.green),
              ),
              title: const Text('Export to Excel'),
              subtitle: const Text('Download loan data as .xlsx file'),
              trailing: _isExporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _isExporting ? null : _exportToExcel,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecuritySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Security',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
            ),
            const SizedBox(height: 16),

            // Auto lock setting
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer, color: AppColors.primary),
              title: const Text('Auto Lock'),
              subtitle: Text(
                  'Lock app after ${_getAutoLockTimeText()} of inactivity'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _isLoading ? null : _showAutoLockDialog,
            ),

            // Change PIN
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock, color: AppColors.primary),
              title: const Text('Change PIN'),
              subtitle: const Text('Update your 4-digit PIN'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showChangePinDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'App Information',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
            ),
            const SizedBox(height: 16),

            // Version
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline, color: AppColors.primary),
              title: Text('Version'),
              subtitle: Text('1.1.0'),
            ),

            const Divider(),

            // Database
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storage, color: AppColors.success),
              title: const Text('Database'),
              subtitle: const Text('View data summary'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showDatabaseHealthDialog,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDatabaseHealthDialog() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Loading data summary...'),
          ],
        ),
      ),
    );

    try {
      // Get database stats
      final stats = await MigrationSafetyService.getDatabaseStats();
      final validation = await MigrationSafetyService.performDeepValidation();

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                validation['valid'] == true
                    ? Icons.check_circle
                    : Icons.warning,
                color: validation['valid'] == true
                    ? AppColors.success
                    : AppColors.warning,
              ),
              const SizedBox(width: 8),
              const Text('Database'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: validation['valid'] == true
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        validation['valid'] == true ? Icons.check : Icons.info,
                        color: validation['valid'] == true
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        validation['valid'] == true
                            ? 'All data is valid'
                            : 'Some issues found',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: validation['valid'] == true
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                const Text('Data Summary:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildStatRow('Customers', '${stats['customers'] ?? 0}'),
                _buildStatRow('Loans', '${stats['loans'] ?? 0}'),
                _buildStatRow('Groups', '${stats['customer_groups'] ?? 0}'),

                // Show errors if any
                if ((validation['errors'] as List?)?.isNotEmpty ?? false) ...[
                  const Divider(),
                  const Text('Issues:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: AppColors.error)),
                  const SizedBox(height: 8),
                  ...((validation['errors'] as List).map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child:
                            Text('• $e', style: const TextStyle(fontSize: 12)),
                      ))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Database health check error: $e');
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to check database health. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _showLocalBackupsDialog() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Loading backups...'),
          ],
        ),
      ),
    );

    try {
      final backups = await AppUpdateService.instance.getAvailableBackups();

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.backup, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Local Backups'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: backups.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No local backups found.\n\nLocal backups are created automatically when you update the app.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      itemCount: backups.length,
                      itemBuilder: (context, index) {
                      final backup = backups[index];
                      return ListTile(
                        leading: const Icon(Icons.file_copy,
                            color: AppColors.primary),
                        title: Text(backup.fileName,
                            style: const TextStyle(fontSize: 12)),
                        subtitle: Text(
                          '${_formatDate(backup.created)} • ${backup.sizeFormatted}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.restore,
                              color: AppColors.warning),
                          onPressed: () => _confirmRestoreBackup(backup.path),
                        ),
                      );
                    },
                  ),
                ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (backups.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await _createManualBackup();
                },
                icon: const Icon(Icons.add),
                label: const Text('Create Backup'),
              ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Error loading backups: $e');
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load backups. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmRestoreBackup(String backupPath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.warning),
            SizedBox(width: 8),
            Text('Restore Backup'),
          ],
        ),
        content: const Text(
          'This will replace all current data with this backup.\n\n'
          'This action cannot be undone. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Restoring backup...'),
          ],
        ),
      ),
    );

    try {
      final success =
          await AppUpdateService.instance.restoreFromSpecificBackup(backupPath);

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Backup restored! Restart app to see changes.'
              : 'Failed to restore backup'),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    } catch (e) {
      debugPrint('Backup restore error: $e');
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to restore backup. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _createManualBackup() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Creating backup...'),
          ],
        ),
      ),
    );

    try {
      // Use BackupService for safe backup (exports data, avoids raw file copy of active database)
      final backupService = BackupService.instance;
      await backupService.initialize();
      final result = await backupService.createBackup();

      if (!mounted) return;
      Navigator.pop(context);

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Manual backup created successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        debugPrint('Backup failed: ${result.error}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup failed. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error creating backup: $e');
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to create backup. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildLogoutButton() {
    // Get AuthProvider from parent context BEFORE showing dialog to avoid disposed context error
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Logout'),
              content: const Text('Are you sure you want to logout?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    authProvider.logout();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  child: const Text('Logout'),
                ),
              ],
            ),
          );
        },
        icon: const Icon(Icons.logout),
        label: const Text('Logout'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  void _showLanguageDialog(
      BuildContext context, LanguageProvider languageProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.language, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(context.tr('language')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('English'),
              subtitle: const Text('Default language'),
              value: 'en',
              // ignore: deprecated_member_use
              groupValue: languageProvider.currentLanguageCode,
              // ignore: deprecated_member_use
              onChanged: (value) {
                if (value != null) {
                  languageProvider.setLanguage(value);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Language changed to English'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              secondary: const Text('🇺🇸', style: TextStyle(fontSize: 24)),
            ),
            const Divider(),
            RadioListTile<String>(
              title: const Text('தமிழ்'),
              subtitle: const Text('Tamil language'),
              value: 'ta',
              // ignore: deprecated_member_use
              groupValue: languageProvider.currentLanguageCode,
              // ignore: deprecated_member_use
              onChanged: (value) {
                if (value != null) {
                  languageProvider.setLanguage(value);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('மொழி தமிழாக மாற்றப்பட்டது'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              secondary: const Text('🇮🇳', style: TextStyle(fontSize: 24)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel')),
          ),
        ],
      ),
    );
  }
}

/// Separate stateful widget for Change PIN dialog to avoid context issues
class _ChangePinDialog extends StatefulWidget {
  final TextEditingController currentPinController;
  final TextEditingController newPinController;
  final TextEditingController confirmPinController;
  final AuthProvider authProvider;
  final ScaffoldMessengerState scaffoldMessenger;

  const _ChangePinDialog({
    required this.currentPinController,
    required this.newPinController,
    required this.confirmPinController,
    required this.authProvider,
    required this.scaffoldMessenger,
  });

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    widget.currentPinController.dispose();
    widget.newPinController.dispose();
    widget.confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _changePin() async {
    final currentPin = widget.currentPinController.text;
    final newPin = widget.newPinController.text;
    final confirmPin = widget.confirmPinController.text;

    // Validation
    if (currentPin.length != 4) {
      setState(() => _errorMessage = 'Current PIN must be 4 digits');
      return;
    }
    if (newPin.length != 4) {
      setState(() => _errorMessage = 'New PIN must be 4 digits');
      return;
    }
    if (newPin != confirmPin) {
      setState(() => _errorMessage = 'New PINs do not match');
      return;
    }
    if (currentPin == newPin) {
      setState(
          () => _errorMessage = 'New PIN must be different from current PIN');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.authProvider.changePin(currentPin, newPin);

      if (!mounted) return;

      if (success) {
        Navigator.pop(context);
        widget.scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('PIN changed successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage =
              widget.authProvider.errorMessage ?? 'Current PIN is incorrect';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to change PIN. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Change PIN'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Current PIN
            TextField(
              controller: widget.currentPinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Current PIN',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                counterText: '',
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 16),

            // New PIN
            TextField(
              controller: widget.newPinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'New PIN',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                counterText: '',
                prefixIcon: const Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 16),

            // Confirm New PIN
            TextField(
              controller: widget.confirmPinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Confirm New PIN',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                counterText: '',
                prefixIcon: const Icon(Icons.lock),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.error, fontSize: 14),
              ),
            ],

            if (_isLoading) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _changePin,
          child: const Text('Change PIN'),
        ),
      ],
    );
  }
}
