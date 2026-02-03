import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService.instance;

  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastActivityTime;
  DateTime? _pausedTime; // Track when app went to background
  int _autoLockTime = 30; // Default 30 seconds
  Timer? _inactivityTimer; // Timer for in-app inactivity
  Timer? _debounceTimer; // Debounce timer to prevent excessive updates

  AuthProvider() {
    // Load auto-lock time from storage on creation
    _loadAutoLockTime();
  }

  Future<void> _loadAutoLockTime() async {
    try {
      _autoLockTime = await _authService.getAutoLockTime();
      debugPrint('AUTO-LOCK: Loaded auto-lock time: $_autoLockTime seconds');
    } catch (e) {
      debugPrint('AUTO-LOCK: Failed to load auto-lock time: $e');
    }
  }

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastActivityTime => _lastActivityTime;

  /// Start or restart the inactivity timer
  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_isAuthenticated && _autoLockTime > 0) {
      debugPrint('AUTO-LOCK: Starting inactivity timer for $_autoLockTime seconds');
      _inactivityTimer = Timer(Duration(seconds: _autoLockTime), () {
        debugPrint('AUTO-LOCK: Inactivity timer fired! Locking app.');
        logout();
      });
    }
  }

  /// Stop the inactivity timer
  void _stopInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Call this on any user interaction to reset the timer
  /// Debounced to prevent excessive timer restarts during rapid interactions
  void updateActivity() {
    _lastActivityTime = DateTime.now();
    
    // Debounce: Only restart timer after 1 second of no activity
    // This prevents excessive timer restarts during scrolling/rapid interactions
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
      // Restart inactivity timer after debounce period
      if (_isAuthenticated) {
        _startInactivityTimer();
      }
    });
  }

  /// Call this when app goes to background
  void onAppPaused() {
    _pausedTime = DateTime.now();
    debugPrint('AUTO-LOCK: App paused at $_pausedTime, auto-lock time: $_autoLockTime seconds');
  }

  /// Call this when app resumes - returns true if should lock
  bool shouldAutoLock() {
    if (_pausedTime == null || !_isAuthenticated) {
      debugPrint('AUTO-LOCK: pausedTime=$_pausedTime, isAuthenticated=$_isAuthenticated, skip lock');
      return false;
    }
    
    final elapsedSeconds = DateTime.now().difference(_pausedTime!).inSeconds;
    debugPrint('AUTO-LOCK: Elapsed $elapsedSeconds seconds since pause, threshold: $_autoLockTime');
    
    final shouldLock = elapsedSeconds >= _autoLockTime;
    if (shouldLock) {
      debugPrint('AUTO-LOCK: Will lock app!');
      _pausedTime = null; // Reset pause time after locking
    }
    return shouldLock;
  }

  Future<void> checkSetupStatus() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final isSetup = await _authService.isSetupComplete();
      if (!isSetup) {
        _isAuthenticated = false;
      }
    } catch (e) {
      _errorMessage = 'Setup check failed: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> setupPin(String pin) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.setPin(pin);
      _isAuthenticated = true;
      _lastActivityTime = DateTime.now();
      _startInactivityTimer(); // Start timer after login
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'PIN setup failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> authenticateWithPin(String pin) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final isValid = await _authService.verifyPin(pin);
      if (isValid) {
        _isAuthenticated = true;
        _lastActivityTime = DateTime.now();
        // Load auto-lock time from storage on successful login
        _autoLockTime = await _authService.getAutoLockTime();
        _startInactivityTimer(); // Start timer after login
      } else {
        _errorMessage = 'Incorrect PIN. Please try again.';
      }
    } catch (e) {
      _errorMessage = 'Authentication failed: $e';
    }

    _isLoading = false;
    notifyListeners();
    return _isAuthenticated;
  }

  Future<bool> isPinSetup() async {
    return await _authService.isPinSetup();
  }

  // Add missing methods for compatibility
  Future<bool> verifyPin(String pin) async {
    return await _authService.verifyPin(pin);
  }

  Future<bool> setPin(String pin) async {
    return await _authService.setPin(pin);
  }

  Future<bool> changePin(String currentPin, String newPin) async {
    // Prevent notification if provider is disposed
    if (!hasListeners) return false;
    
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Validate inputs
      if (currentPin.length != 4 || newPin.length != 4) {
        _errorMessage = 'PIN must be exactly 4 digits';
        _isLoading = false;
        if (hasListeners) notifyListeners();
        return false;
      }
      
      final isCurrentPinValid = await _authService.verifyPin(currentPin);
      if (isCurrentPinValid) {
        final success = await _authService.changePin(currentPin, newPin);
        if (success) {
          _isLoading = false;
          if (hasListeners) notifyListeners();
          return true;
        } else {
          _errorMessage = 'Failed to update PIN in secure storage';
        }
      } else {
        _errorMessage = 'Current PIN is incorrect.';
      }
    } catch (e) {
      _errorMessage = 'PIN change failed: ${e.toString()}';
      debugPrint('DEBUG: PIN change error: $e');
    }

    _isLoading = false;
    if (hasListeners) notifyListeners();
    return false;
  }

  Future<void> setAutoLockTime(int seconds) async {
    _autoLockTime = seconds;
    await _authService.setAutoLockTime(seconds);
    // Restart timer with new duration
    _startInactivityTimer();
    notifyListeners();
  }

  Future<int> getAutoLockTime() async {
    _autoLockTime = await _authService.getAutoLockTime();
    return _autoLockTime;
  }

  int get autoLockTime => _autoLockTime;

  void logout() {
    _stopInactivityTimer(); // Stop timer on logout
    _debounceTimer?.cancel(); // Also cancel debounce timer
    _isAuthenticated = false;
    _lastActivityTime = null;
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> resetAuthentication() async {
    try {
      _stopInactivityTimer();
      _debounceTimer?.cancel();
      await _authService.resetAuth();
      _isAuthenticated = false;
      _lastActivityTime = null;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Reset failed: $e';
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }
}