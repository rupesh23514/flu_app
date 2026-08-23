import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/alarm_service.dart';
import '../controllers/account_choice_controller.dart';

/// Account Choice Screen - Shown after PIN creation on fresh install
/// Allows user to choose between New Account or Restore Existing Account
class AccountChoiceScreen extends StatefulWidget {
  const AccountChoiceScreen({super.key});

  @override
  State<AccountChoiceScreen> createState() => _AccountChoiceScreenState();
}

class _AccountChoiceScreenState extends State<AccountChoiceScreen> {
  late final AccountChoiceController _controller;

  bool _isRestoring = false;
  bool _isCheckingBackup = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = AccountChoiceController(
      onStateChanged: _handleStateChanged,
    );
    _initializeController();
  }

  @override
  void dispose() {
    // Controller cleanup (no resources to dispose currently, but good practice)
    super.dispose();
  }

  Future<void> _initializeController() async {
    try {
      await _controller.initialize();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to initialize: $e';
      });
    }
  }

  /// Handle state changes from controller (with mounted check)
  void _handleStateChanged(AccountRestoreState state) {
    if (!mounted) return;
    setState(() {
      _isCheckingBackup = state.isCheckingBackup;
      _isRestoring = state.isRestoring;
    });
  }

  /// Start fresh with new account - no restore needed
  Future<void> _startNewAccount() async {
    HapticFeedback.lightImpact();

    // Mark account setup as complete
    await _controller.completeNewAccountSetup();

    if (!mounted) return;

    // Navigate to dashboard/home
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/dashboard',
      (route) => false,
    );
  }

  /// Restore from existing Google Drive backup
  Future<void> _restoreExistingAccount() async {
    HapticFeedback.lightImpact();

    if (!mounted) return;
    setState(() {
      _errorMessage = null;
    });

    final result = await _controller.restoreExistingAccount();

    if (!mounted) return;

    switch (result.status) {
      case AccountRestoreStatus.signInCancelled:
        setState(() {
          _errorMessage = result.errorMessage;
        });
        break;

      case AccountRestoreStatus.noBackupFound:
        _showNoBackupDialog(userEmail: result.userEmail);
        break;

      case AccountRestoreStatus.restored:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Data restored successfully!'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );

        // Reschedule alarms from the restored reminders
        try {
          await AlarmService.instance.verifyAndRescheduleAlarms();
        } catch (_) {}

        // Navigate to dashboard — HomeScreen.initState reloads providers
        if (!mounted) break;
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/dashboard',
          (route) => false,
        );
        break;

      case AccountRestoreStatus.restoreFailed:
      case AccountRestoreStatus.error:
        setState(() {
          _errorMessage = result.errorMessage;
        });
        break;
    }
  }

  /// Show dialog when no backup found
  void _showNoBackupDialog({String? userEmail}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.warning, size: 28),
            SizedBox(width: 12),
            Text('No Backup Found'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No backup was found in your Google Drive account${userEmail != null ? ' ($userEmail)' : ''}.',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            const Text(
              'Would you like to:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text('• Start with a new account'),
            const Text('• Try a different Google account'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _tryDifferentAccount();
            },
            child: const Text('Try Different Account'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _startNewAccount();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Start New'),
          ),
        ],
      ),
    );
  }

  /// Sign out and try different Google account
  Future<void> _tryDifferentAccount() async {
    await _controller.signOut();
    if (!mounted) return;
    await _restoreExistingAccount();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Header
              _buildHeader(),

              const Spacer(),

              // Account Options
              if (_isRestoring || _isCheckingBackup)
                _buildLoadingState()
              else
                _buildAccountOptions(),

              // Error Message
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(flex: 2),

              // Footer note
              Text(
                'Your PIN is stored locally and never backed up',
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Success checkmark
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.check,
            size: 48,
            color: Colors.white,
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'PIN Created!',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 8),

        const Text(
          'How would you like to continue?',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Column(
      children: [
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 24),
        Text(
          _isCheckingBackup
              ? 'Checking for backup...'
              : 'Restoring your data...',
          style: const TextStyle(
            fontSize: 16,
            color: AppColors.textSecondary,
          ),
        ),
        if (_controller.userEmail != null) ...[
          const SizedBox(height: 8),
          Text(
            _controller.userEmail!,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAccountOptions() {
    return Column(
      children: [
        // New Account Option
        _buildOptionCard(
          icon: Icons.add_circle_outline,
          iconColor: AppColors.primary,
          title: 'New Account',
          subtitle: 'Start fresh with a clean slate',
          onTap: _startNewAccount,
          isPrimary: true,
        ),

        const SizedBox(height: 16),

        // Existing Account Option
        _buildOptionCard(
          icon: Icons.cloud_download_outlined,
          iconColor: AppColors.secondary,
          title: 'Existing Account',
          subtitle: 'Restore data from Google Drive',
          onTap: _restoreExistingAccount,
          isPrimary: false,
        ),
      ],
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isPrimary
                ? AppColors.primary.withValues(alpha: 0.05)
                : AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPrimary
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : AppColors.outline.withValues(alpha: 0.3),
              width: isPrimary ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: iconColor,
                ),
              ),

              const SizedBox(width: 16),

              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isPrimary
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
