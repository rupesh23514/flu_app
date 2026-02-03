import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  static const String _autoLockTimeKey = 'auto_lock_time';

  // Setup completion
  Future<bool> isSetupComplete() async {
    final result = await _storage.read(key: _setupCompleteKey);
    return result == 'true';
  }

  Future<void> markSetupComplete() async {
    await _storage.write(key: _setupCompleteKey, value: 'true');
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

  Future<bool> verifyPin(String pin) async {
    try {
      final storedPin = await _storage.read(key: _pinKey);
      return storedPin == pin;
    } catch (e) {
      return false;
    }
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