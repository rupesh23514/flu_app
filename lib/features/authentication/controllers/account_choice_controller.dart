import 'package:flutter/foundation.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/google_drive_service.dart';
import '../../../core/services/restore_helper_service.dart';

/// Result object for account restore operations
class AccountRestoreResult {
  final bool success;
  final AccountRestoreStatus status;
  final String? errorMessage;
  final String? userEmail;

  const AccountRestoreResult({
    required this.success,
    required this.status,
    this.errorMessage,
    this.userEmail,
  });

  factory AccountRestoreResult.signInCancelled() => const AccountRestoreResult(
        success: false,
        status: AccountRestoreStatus.signInCancelled,
        errorMessage: 'Google sign-in cancelled',
      );

  factory AccountRestoreResult.noBackupFound({String? userEmail}) =>
      AccountRestoreResult(
        success: false,
        status: AccountRestoreStatus.noBackupFound,
        userEmail: userEmail,
      );

  factory AccountRestoreResult.restoreSuccess() => const AccountRestoreResult(
        success: true,
        status: AccountRestoreStatus.restored,
      );

  factory AccountRestoreResult.restoreFailed({String? errorMessage}) =>
      AccountRestoreResult(
        success: false,
        status: AccountRestoreStatus.restoreFailed,
        errorMessage: errorMessage ?? 'Restore failed. Please try again.',
      );

  factory AccountRestoreResult.error({String? errorMessage}) =>
      AccountRestoreResult(
        success: false,
        status: AccountRestoreStatus.error,
        errorMessage: errorMessage ?? 'An error occurred. Please try again.',
      );
}

/// Status enum for restore operation progress
enum AccountRestoreStatus {
  signInCancelled,
  noBackupFound,
  restored,
  restoreFailed,
  error,
}

/// Controller for AccountChoiceScreen business logic
///
/// Separates business workflow orchestration from UI concerns,
/// making the logic testable independently of the Flutter framework.
class AccountChoiceController {
  final AuthService _authService;
  final GoogleDriveService _driveService;
  final RestoreHelperService _restoreHelper;

  /// Callback for state changes during restore process
  final ValueChanged<AccountRestoreState>? onStateChanged;

  AccountChoiceController({
    AuthService? authService,
    GoogleDriveService? driveService,
    RestoreHelperService? restoreHelper,
    this.onStateChanged,
  })  : _authService = authService ?? AuthService.instance,
        _driveService = driveService ?? GoogleDriveService.instance,
        _restoreHelper = restoreHelper ?? RestoreHelperService.instance;

  /// Initialize the controller (sets up drive service)
  Future<void> initialize() async {
    await _driveService.initialize();
  }

  /// Get current user email from Google Drive service
  String? get userEmail => _driveService.userEmail;

  /// Check if user is signed in to Google
  bool get isSignedIn => _driveService.isSignedIn;

  /// Mark account setup as complete (for new accounts)
  Future<void> completeNewAccountSetup() async {
    await _authService.markAccountSetupComplete();
  }

  /// Perform the full restore workflow
  ///
  /// This orchestrates:
  /// 1. Google sign-in (if needed)
  /// 2. Backup existence check
  /// 3. Actual restore operation
  /// 4. Account setup completion
  ///
  /// Returns [AccountRestoreResult] indicating the outcome
  Future<AccountRestoreResult> restoreExistingAccount() async {
    try {
      // Notify: checking for backup
      _notifyState(const AccountRestoreState(isCheckingBackup: true));

      // Step 1: Sign in to Google if needed
      if (!_driveService.isSignedIn) {
        final signedIn = await _driveService.signIn();
        if (!signedIn) {
          _notifyState(const AccountRestoreState());
          final message = _driveService.errorMessage;
          if (message != null && message.isNotEmpty) {
            return AccountRestoreResult.error(errorMessage: message);
          }
          return AccountRestoreResult.signInCancelled();
        }
      }

      // Step 2: Check if backup exists
      final hasBackup = await _driveService.checkForBackup();

      if (!hasBackup) {
        _notifyState(const AccountRestoreState());
        return AccountRestoreResult.noBackupFound(
            userEmail: _driveService.userEmail);
      }

      // Step 3: Perform restore
      _notifyState(const AccountRestoreState(isRestoring: true));

      final result = await _restoreHelper.restoreFromGoogleDrive(
        signInIfNeeded: false, // Already signed in
      );

      _notifyState(const AccountRestoreState());

      if (result.success) {
        // Step 4: Mark account setup as complete
        await _authService.markAccountSetupComplete();
        return AccountRestoreResult.restoreSuccess();
      } else {
        return AccountRestoreResult.restoreFailed(
            errorMessage: result.errorMessage);
      }
    } catch (e, stackTrace) {
      // Log error for debugging
      debugPrint('AccountChoiceController restore error: $e');
      debugPrint('Stack trace: $stackTrace');
      _notifyState(const AccountRestoreState());
      return AccountRestoreResult.error(errorMessage: e.toString());
    }
  }

  /// Sign out from Google Drive (to try different account)
  Future<void> signOut() async {
    await _driveService.signOut();
  }

  void _notifyState(AccountRestoreState state) {
    onStateChanged?.call(state);
  }
}

/// State object for the restore process
class AccountRestoreState {
  final bool isCheckingBackup;
  final bool isRestoring;

  const AccountRestoreState({
    this.isCheckingBackup = false,
    this.isRestoring = false,
  });

  bool get isLoading => isCheckingBackup || isRestoring;
}
