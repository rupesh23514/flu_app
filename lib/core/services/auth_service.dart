import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Authentication status to distinguish between failure modes
enum AuthStatus {
  /// Authentication succeeded
  success,
  /// Authentication failed (wrong PIN)
  failed,
  /// Authentication system unavailable (error state - fail closed)
  unavailable,
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  static AuthService get instance => _instance;
  AuthService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Keys for secure storage
  static const String _pinKey = 'user_pin';
  static const String _setupCompleteKey = 'setup_complete';
  static const String _accountSetupCompleteKey = 'account_setup_complete';
  static const String _autoLockTimeKey = 'auto_lock_time';
  static const String _failedAttemptsKey = 'failed_pin_attempts';
  static const String _lockoutUntilKey = 'lockout_until';

  // Rate limiting constants
  static const int maxFailedAttempts = 5;
  static const int baseLockoutSeconds = 30; // 30 seconds for first lockout
  static const int maxLockoutSeconds = 300; // 5 minutes max lockout

  // Setup completion
  Future<bool> isSetupComplete() async {
    final result = await _storage.read(key: _setupCompleteKey);
    return result == 'true';
  }

  Future<void> markSetupComplete() async {
    await _storage.write(key: _setupCompleteKey, value: 'true');
  }

  // Account setup completion (after PIN creation + account choice)
  Future<bool> isAccountSetupComplete() async {
    final result = await _storage.read(key: _accountSetupCompleteKey);
    return result == 'true';
  }

  Future<void> markAccountSetupComplete() async {
    await _storage.write(key: _accountSetupCompleteKey, value: 'true');
  }

  /// Check if this is a fresh install (no PIN exists)
  Future<bool> isFirstLaunch() async {
    final hasExistingPin = await hasPin();
    return !hasExistingPin;
  }

  /// Check if user needs to complete account setup (PIN created but account choice not made)
  Future<bool> needsAccountSetup() async {
    final pinExists = await hasPin();
    final accountSetupDone = await isAccountSetupComplete();
    return pinExists && !accountSetupDone;
  }

  // PIN authentication
  Future<bool> createPin(String pin) async {
    try {
      await _storage.write(key: _pinKey, value: pin);
      await markSetupComplete();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Verify PIN with rate limiting protection
  /// Returns a record with (status, remainingAttempts, lockoutSeconds)
  /// - status: AuthStatus.success (valid PIN), AuthStatus.failed (wrong PIN), AuthStatus.unavailable (error)
  /// - On AuthStatus.unavailable, remainingAttempts is 0 (fail closed) and callers should show error UI
  Future<({AuthStatus status, int remainingAttempts, int lockoutSeconds})>
      verifyPinWithRateLimit(String pin) async {
    try {
      // Check if currently locked out
      final lockoutInfo = await getLockoutStatus();
      if (lockoutInfo.isLockedOut) {
        return (
          status: AuthStatus.failed,
          remainingAttempts: 0,
          lockoutSeconds: lockoutInfo.remainingSeconds
        );
      }

      final storedPin = await _storage.read(key: _pinKey);
      final isValid = storedPin == pin;

      if (isValid) {
        // Reset failed attempts on successful login
        await _resetFailedAttempts();
        return (
          status: AuthStatus.success,
          remainingAttempts: maxFailedAttempts,
          lockoutSeconds: 0
        );
      } else {
        // Increment failed attempts
        final failedAttempts = await _incrementFailedAttempts();
        final remaining = maxFailedAttempts - failedAttempts;

        if (failedAttempts >= maxFailedAttempts) {
          // Calculate lockout duration with exponential backoff
          final lockoutMultiplier = (failedAttempts / maxFailedAttempts).ceil();
          final lockoutDuration = (baseLockoutSeconds * lockoutMultiplier)
              .clamp(baseLockoutSeconds, maxLockoutSeconds);
          await _setLockout(lockoutDuration);
          return (
            status: AuthStatus.failed,
            remainingAttempts: 0,
            lockoutSeconds: lockoutDuration
          );
        }

        return (
          status: AuthStatus.failed,
          remainingAttempts: remaining,
          lockoutSeconds: 0
        );
      }
    } catch (e) {
      // Fail closed: return unavailable status with 0 remaining attempts
      // Callers must check for AuthStatus.unavailable and show appropriate error UI
      return (status: AuthStatus.unavailable, remainingAttempts: 0, lockoutSeconds: 0);
    }
  }

  /// Simple PIN verification (for backward compatibility)
  Future<bool> verifyPin(String pin) async {
    try {
      final storedPin = await _storage.read(key: _pinKey);
      return storedPin == pin;
    } catch (e) {
      return false;
    }
  }

  /// Get current lockout status
  Future<({bool isLockedOut, int remainingSeconds})> getLockoutStatus() async {
    try {
      final lockoutUntilStr = await _storage.read(key: _lockoutUntilKey);
      if (lockoutUntilStr == null) {
        return (isLockedOut: false, remainingSeconds: 0);
      }

      final lockoutUntil = DateTime.tryParse(lockoutUntilStr);
      if (lockoutUntil == null) {
        return (isLockedOut: false, remainingSeconds: 0);
      }

      final now = DateTime.now();
      if (now.isAfter(lockoutUntil)) {
        // Lockout expired, clear it
        await _storage.delete(key: _lockoutUntilKey);
        return (isLockedOut: false, remainingSeconds: 0);
      }

      final remaining = lockoutUntil.difference(now).inSeconds;
      return (isLockedOut: true, remainingSeconds: remaining);
    } catch (e) {
      return (isLockedOut: false, remainingSeconds: 0);
    }
  }

  /// Get remaining attempts before lockout
  Future<int> getRemainingAttempts() async {
    try {
      final attemptsStr = await _storage.read(key: _failedAttemptsKey);
      final attempts = int.tryParse(attemptsStr ?? '0') ?? 0;
      return (maxFailedAttempts - attempts).clamp(0, maxFailedAttempts);
    } catch (e) {
      return maxFailedAttempts;
    }
  }

  Future<int> _incrementFailedAttempts() async {
    try {
      final attemptsStr = await _storage.read(key: _failedAttemptsKey);
      final attempts = (int.tryParse(attemptsStr ?? '0') ?? 0) + 1;
      await _storage.write(key: _failedAttemptsKey, value: attempts.toString());
      return attempts;
    } catch (e) {
      return 1;
    }
  }

  Future<void> _resetFailedAttempts() async {
    await _storage.delete(key: _failedAttemptsKey);
    await _storage.delete(key: _lockoutUntilKey);
  }

  Future<void> _setLockout(int seconds) async {
    final lockoutUntil = DateTime.now().add(Duration(seconds: seconds));
    await _storage.write(
        key: _lockoutUntilKey, value: lockoutUntil.toIso8601String());
  }

  Future<bool> hasPin() async {
    try {
      final pin = await _storage.read(key: _pinKey);
      return pin != null && pin.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<bool> changePin(String oldPin, String newPin) async {
    try {
      if (await verifyPin(oldPin)) {
        await _storage.write(key: _pinKey, value: newPin);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Auto-lock functionality
  Future<int> getAutoLockTime() async {
    try {
      final timeStr = await _storage.read(key: _autoLockTimeKey);
      return int.parse(timeStr ?? '300'); // Default 5 minutes
    } catch (e) {
      return 300;
    }
  }

  Future<void> setAutoLockTime(int seconds) async {
    await _storage.write(key: _autoLockTimeKey, value: seconds.toString());
  }

  // Cleanup
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  // Alias methods for compatibility
  Future<bool> setPin(String pin) async {
    return await createPin(pin);
  }

  Future<bool> isPinSetup() async {
    return await hasPin();
  }

  Future<void> resetAuth() async {
    await clearAll();
  }
}
