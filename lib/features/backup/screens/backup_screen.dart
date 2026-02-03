import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/google_drive_service.dart';
import '../../../core/services/restore_helper_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final BackupService _backupService = BackupService.instance;
  final GoogleDriveService _driveService = GoogleDriveService.instance;
  
  bool _autoBackupEnabled = true;
  bool _isLoading = true;
  bool _isBackingUp = false;
  bool _isGoogleSignedIn = false;
  String? _googleEmail;
  String? _lastBackupDate;
  List<BackupFile> _backups = [];

  @override
  void initState() {
    super.initState();
    _loadBackupData();
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _loadBackupData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    await _backupService.initialize();
    await _driveService.initialize();
    
    _autoBackupEnabled = await _backupService.isAutoBackupEnabled();
    _isGoogleSignedIn = _driveService.isSignedIn;
    _googleEmail = _driveService.userEmail;
    
    final lastBackup = _backupService.lastBackupDate;
    if (lastBackup != null) {
      _lastBackupDate = _formatDate(DateTime.parse(lastBackup));
    }
    
    _backups = await _backupService.listBackups();
    
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _backupToGoogleDrive() async {
    setState(() => _isBackingUp = true);
    
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Uploading to Google Drive...'),
            ],
          ),
        ),
      );
    }
    
    final result = await _backupService.createBackup();
    
    if (result.success && result.filePath != null) {
      final success = await _driveService.uploadDatabase(result.filePath!);
      
      setState(() => _isBackingUp = false);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Uploaded to Google Drive'
                : _driveService.errorMessage ?? 'Upload failed'),
            backgroundColor: success ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      setState(() => _isBackingUp = false);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Backup creation failed'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _selectBackupToRestore() {
    if (_backups.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No backups available'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Backup'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _backups.length,
            itemBuilder: (context, index) {
              final backup = _backups[index];
              return ListTile(
                title: Text(_formatDate(backup.createdAt)),
                subtitle: Text('Size: ${backup.formattedSize}'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.pop(context);
                  _restoreBackup(backup);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _restoreBackup(BackupFile backup) async {
    final success = await _backupService.restoreFromFile(backup.path);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
              ? 'Data restored successfully' 
              : _backupService.errorMessage ?? 'Restore failed'),
          backgroundColor: success ? AppColors.success : AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _restoreFromGoogleDrive() async {
    final hasBackup = await _driveService.checkForBackup();
    
    if (!hasBackup) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No backup found in Google Drive'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    
    if (!mounted) return;
    final shouldRestore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.warning),
            SizedBox(width: 8),
            Text('Restore from Drive'),
          ],
        ),
        content: const Text(
          'This will replace all current data with the backup from Google Drive. '
          'This action cannot be undone. Continue?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    
    if (shouldRestore != true) return;
    
    // Show progress dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Restoring from Google Drive...'),
            ],
          ),
        ),
      );
    }
    
    // Use centralized restore helper to avoid code duplication
    final restoreHelper = RestoreHelperService.instance;
    final result = await restoreHelper.restoreFromGoogleDrive(signInIfNeeded: false);
    
    if (mounted) {
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success 
              ? 'Database restored successfully! Please restart the app.' 
              : result.errorMessage ?? 'Restore failed'),
          backgroundColor: result.success ? AppColors.success : AppColors.error,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _shareViaWhatsApp() async {
    if (!mounted) return;
    setState(() => _isBackingUp = true);
    
    final result = await _backupService.createBackup();
    
    if (!mounted) return;
    setState(() => _isBackingUp = false);
    
    if (result.success && result.filePath != null) {
      await Share.shareXFiles(
        [XFile(result.filePath!)],
        text: 'Financial Manager Backup - ${_formatDate(DateTime.now())}',
        subject: 'Financial Manager Backup',
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to create backup'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _saveToLocal() async {
    if (!mounted) return;
    setState(() => _isBackingUp = true);
    
    final result = await _backupService.exportToLocal();
    
    if (!mounted) return;
    setState(() => _isBackingUp = false);
    await _loadBackupData();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success 
              ? 'Saved to: ${result.filePath}' 
              : result.error ?? 'Export failed'),
          backgroundColor: result.success ? AppColors.success : AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showRestoreDialog() {
    if (_backups.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No backups available to restore'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Data'),
        content: const SingleChildScrollView(
          child: Text(
            'This will replace all current data with a backup. '
            'This action cannot be undone. Continue?'
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _selectBackupToRestore();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
            ),
            child: const Text('Choose Backup'),
          ),
        ],
      ),
    );
  }

  Future<void> _performBackup() async {
    setState(() {
      _isBackingUp = true;
    });
    
    final result = await _backupService.createBackup();
    
    setState(() {
      _isBackingUp = false;
      if (result.success) {
        _lastBackupDate = _formatDate(DateTime.now());
      }
    });

    await _loadBackupData();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success 
              ? 'Backup completed successfully' 
              : result.error ?? 'Backup failed'),
          backgroundColor: result.success ? AppColors.success : AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _setupGoogleDrive() async {
    if (_isGoogleSignedIn) {
      // Show options for signed-in user
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.blue.withValues(alpha: 0.1),
                    child: const Icon(Icons.person, color: Colors.blue, size: 30),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _googleEmail ?? 'Google Account',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload, color: Colors.blue),
                    title: const Text('Backup to Drive', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      Navigator.pop(context);
                      await _backupToGoogleDrive();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.cloud_download, color: Colors.green),
                    title: const Text('Restore from Drive', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      Navigator.pop(context);
                      await _restoreFromGoogleDrive();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Sign Out', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      Navigator.pop(context);
                      await _driveService.signOut();
                      await _loadBackupData();
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      // Sign in
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Signing in...'),
              ],
            ),
          ),
        );
      }
      
      final success = await _driveService.signIn();
      
      if (mounted) {
        Navigator.pop(context);
        
        if (success) {
          await _loadBackupData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Connected to Google Drive'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_driveService.errorMessage ?? 'Sign in failed'),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.get('backup') ?? 'Backup & Restore'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadBackupData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Backup Status Card
                  _buildStatusCard(),
                  
                  const SizedBox(height: 24),
                  
                  // Auto Backup Section
                  _buildSectionHeader(l10n?.get('auto_backup') ?? 'Auto Backup'),
                  Card(
                    child: SwitchListTile(
                      value: _autoBackupEnabled,
                      onChanged: (value) async {
                        await _backupService.setAutoBackupEnabled(value);
                        setState(() {
                          _autoBackupEnabled = value;
                        });
                      },
                      title: const Text('Enable Auto Backup'),
                      subtitle: const Text('Automatically backup weekly'),
                      secondary: Icon(
                        Icons.schedule,
                        color: _autoBackupEnabled ? AppColors.primary : AppColors.textSecondary,
                      ),
                      activeThumbColor: AppColors.primary,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Backup Options
                  _buildSectionHeader('Backup Options'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.cloud, color: Colors.blue),
                          ),
                          title: const Text('Google Drive'),
                          subtitle: const Text('Sync to your Google account'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: _setupGoogleDrive,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.chat, color: Colors.green),
                          ),
                          title: const Text('WhatsApp'),
                          subtitle: const Text('Share backup via WhatsApp'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: _shareViaWhatsApp,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.folder, color: Colors.orange),
                          ),
                          title: const Text('Local Storage'),
                          subtitle: const Text('Save to device storage'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: _saveToLocal,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Manual Backup Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isBackingUp ? null : _performBackup,
                      icon: _isBackingUp
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.backup),
                      label: Text(_isBackingUp ? 'Backing up...' : 'Backup Now'),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Restore Section
                  _buildSectionHeader('Restore'),
                  Card(
                    color: AppColors.warning.withValues(alpha: 0.05),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.restore, color: AppColors.warning),
                      ),
                      title: const Text('Restore from Backup'),
                      subtitle: const Text('This will replace current data'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _showRestoreDialog,
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.primary),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your data is encrypted and secure. Backups include all customers, loans, and payment records.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.cloud_done,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Backup Status',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Last backup: ${_lastBackupDate ?? 'Never'}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Synced',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}