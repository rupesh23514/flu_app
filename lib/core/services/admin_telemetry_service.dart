import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/admin_api_config.dart';
import 'database_service.dart';
import 'google_drive_service.dart';

/// Suspension status result from server
class SuspensionStatus {
  final bool isSuspended;
  final String? reason;
  final DateTime? checkedAt;

  const SuspensionStatus({
    required this.isSuspended,
    this.reason,
    this.checkedAt,
  });

  static const notSuspended = SuspensionStatus(isSuspended: false);
}

/// Sends anonymized usage telemetry to the admin dashboard backend.
/// Non-blocking: failures are logged in debug mode only.
/// Optimized with debouncing to avoid redundant stats collection.
/// Also handles account suspension status checking and local caching.
class AdminTelemetryService {
  static final AdminTelemetryService instance = AdminTelemetryService._();
  AdminTelemetryService._();

  static const _deviceIdKey = 'admin_telemetry_device_id';
  static const _backupCountKey = 'admin_telemetry_backup_count';
  static const _suspendedKey = 'admin_telemetry_suspended';
  static const _suspendedReasonKey = 'admin_telemetry_suspended_reason';
  static const _suspendedCheckedAtKey = 'admin_telemetry_suspended_checked_at';
  static const _appVersion = '1.1.0';
  
  /// Minimum interval between stats syncs to avoid redundant DB queries
  static const _statsSyncDebounceMs = 5000;

  String? _deviceId;
  bool _initialized = false;
  Future<void>? _initializingFuture;
  final List<Map<String, dynamic>> _pendingEvents = [];
  int _backupCount = 0;
  
  /// Cached suspension status (loaded from SharedPreferences on init)
  bool _cachedSuspended = false;
  String? _cachedSuspendedReason;
  DateTime? _cachedSuspendedCheckedAt;
  
  /// Timestamp of last stats sync (for debouncing)
  int _lastStatsSyncMs = 0;
  
  /// Cached stats to avoid redundant DB queries
  Map<String, dynamic>? _cachedStats;

  bool get isEnabled => AdminApiConfig.isConfigured;
  
  /// Returns true if the account is currently suspended (from local cache)
  bool get isSuspended => _cachedSuspended;
  
  /// Returns the suspension reason (from local cache)
  String? get suspendedReason => _cachedSuspendedReason;
  
  /// Returns when suspension status was last verified online
  DateTime? get suspendedCheckedAt => _cachedSuspendedCheckedAt;

  Future<void> initialize() async {
    if (!isEnabled || _initialized) return;
    
    // Guard against concurrent initialization
    if (_initializingFuture != null) {
      return _initializingFuture;
    }
    
    _initializingFuture = _doInitialize();
    try {
      await _initializingFuture;
    } finally {
      _initializingFuture = null;
    }
  }
  
  Future<void> _doInitialize() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_deviceIdKey);
    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, _deviceId!);
    }
    _backupCount = prefs.getInt(_backupCountKey) ?? 0;
    
    // Load cached suspension status (for offline enforcement)
    _cachedSuspended = prefs.getBool(_suspendedKey) ?? false;
    _cachedSuspendedReason = prefs.getString(_suspendedReasonKey);
    final checkedAtStr = prefs.getString(_suspendedCheckedAtKey);
    if (checkedAtStr != null) {
      _cachedSuspendedCheckedAt = DateTime.tryParse(checkedAtStr);
    }
    
    _initialized = true;

    unawaited(sendHeartbeat());
  }

  Future<String?> get deviceId async {
    if (_deviceId != null) return _deviceId;
    await initialize();
    return _deviceId;
  }

  Future<void> trackSignIn({
    required String email,
    String? displayName,
  }) async {
    // Queue event immediately (fast)
    await _enqueueEvent('sign_in', {
      'email': email,
      if (displayName != null) 'displayName': displayName,
    });
    
    // Defer HTTP and stats work to avoid blocking sign-in UI
    Future.delayed(const Duration(milliseconds: 100), () async {
      await _flushEvents(email: email, displayName: displayName);
      syncStats(email: email, displayName: displayName);
    });
  }

  Future<void> trackSignOut({String? email}) async {
    await _enqueueEvent('sign_out', {});
    // Defer flush to avoid blocking sign-out
    Future.microtask(() => _flushEvents(email: email));
  }

  Future<void> trackBackupSuccess({String? email}) async {
    // Increment local backup count (fast)
    _backupCount++;
    
    await _enqueueEvent('backup_success', {
      'backupCount': _backupCount,
    });
    
    // Defer heavy operations to avoid blocking backup completion UI
    Future.delayed(const Duration(milliseconds: 200), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_backupCountKey, _backupCount);
      await _flushEvents(email: email);
      syncStats(email: email);
    });
  }

  Future<void> trackBackupFailed({
    String? email,
    String? error,
  }) async {
    await _enqueueEvent('backup_failed', {
      if (error != null) 'error': error,
    });
    // Defer flush
    Future.microtask(() => _flushEvents(email: email));
  }

  Future<void> trackError(String message, {StackTrace? stackTrace}) async {
    // Sanitize and truncate error message to avoid sending sensitive data
    final sanitizedMessage = _sanitizeErrorMessage(message);
    final truncatedStack = stackTrace != null 
        ? _truncateString(stackTrace.toString(), 500) 
        : null;
    
    await _enqueueEvent('error', {
      'message': sanitizedMessage,
      if (truncatedStack != null) 'stack': truncatedStack,
    });
    // Defer flush - avoid sending identifiable user data
    Future.microtask(() => _flushEvents());
  }
  
  /// Sanitize error message to remove potential sensitive data
  String _sanitizeErrorMessage(String message) {
    // Truncate to reasonable length
    var sanitized = _truncateString(message, 200);
    // Remove potential email addresses
    sanitized = sanitized.replaceAll(RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'), '[email]');
    // Remove potential file paths
    sanitized = sanitized.replaceAll(RegExp(r'/[\w/.-]+'), '[path]');
    return sanitized;
  }
  
  String _truncateString(String str, int maxLength) {
    if (str.length <= maxLength) return str;
    return '${str.substring(0, maxLength)}...';
  }

  Future<void> sendHeartbeat() async {
    if (!isEnabled || !_initialized || _deviceId == null) return;

    // Defer heartbeat to avoid blocking app startup
    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        final stats = await _collectStats();
        final drive = GoogleDriveService.instance;

        final response = await _post(
          AdminApiConfig.telemetryHeartbeatUrl,
          {
            'deviceId': _deviceId,
            'email': drive.userEmail,
            'displayName': drive.userName,
            'appVersion': _appVersion,
            'platform': Platform.isAndroid ? 'android' : 'unknown',
            'stats': stats,
          },
        );
        
        // Check for suspension status in response
        await _handleSuspensionResponse(response);
      } catch (e) {
        if (kDebugMode) debugPrint('Telemetry heartbeat failed: $e');
      }
    });
  }

  Future<void> syncStats({String? email, String? displayName, bool force = false}) async {
    if (!isEnabled || !_initialized || _deviceId == null) return;

    // Debounce: skip if we synced recently (unless forced)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force && (nowMs - _lastStatsSyncMs) < _statsSyncDebounceMs) {
      if (kDebugMode) debugPrint('Telemetry sync debounced');
      return;
    }
    _lastStatsSyncMs = nowMs;

    // Defer the heavy work to avoid blocking UI
    Future.microtask(() async {
      try {
        final stats = await _collectStats();
        await _enqueueEvent('stats_sync', stats);
        await _flushEvents(
          email: email ?? GoogleDriveService.instance.userEmail,
          displayName: displayName ?? GoogleDriveService.instance.userName,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('Telemetry stats sync failed: $e');
      }
    });
  }

  /// Collect comprehensive stats for telemetry (optimized - single DB query)
  Future<Map<String, dynamic>> _collectStats() async {
    final db = DatabaseService.instance;
    
    // Use the optimized telemetry stats method (single SQL query for most stats)
    final stats = await db.getTelemetryStats();
    final drive = GoogleDriveService.instance;

    // totalOutstanding from DB is the sum of remaining_amount (principal portion).
    // We send it as both totalOutstanding and totalPrincipalOutstanding so the
    // server dashboard can display the correct "Total Outstanding" metric.
    final totalOutstanding = (stats['totalOutstanding'] as num?)?.toDouble() ?? 0.0;
    final monthlyInterestDue = (stats['monthlyInterestDue'] as num?)?.toDouble() ?? 0.0;

    // Cache the stats for potential reuse
    _cachedStats = {
      // Basic counts (paymentCount is now included in getTelemetryStats)
      'customerCount': stats['customerCount'],
      'loanCount': stats['loanCount'],
      'paymentCount': stats['paymentCount'],
      
      // Loan status breakdown
      'activeLoanCount': stats['activeLoanCount'],
      'overdueLoanCount': stats['overdueLoanCount'],
      
      // Financial aggregates
      'totalOutstanding': totalOutstanding,
      // FIX: send both principal and interest outstanding separately
      // so the admin dashboard shows correct per-field figures.
      'totalPrincipalOutstanding': totalOutstanding,
      'totalInterestOutstanding': monthlyInterestDue,
      'monthlyInterestDue': monthlyInterestDue,
      'monthlyCollectionThisMonth': stats['monthlyCollectionThisMonth'],
      
      // Loan type breakdown
      'loanTypeBreakdown': stats['loanTypeBreakdown'],
      
      // Backup info
      'backupCount': _backupCount,
      'lastBackupAt': drive.lastBackupDate,
    };
    
    return _cachedStats!;
  }

  Future<void> _enqueueEvent(String type, Map<String, dynamic> payload) async {
    _pendingEvents.add({
      'type': type,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    });
    if (_pendingEvents.length > 25) {
      _pendingEvents.removeRange(0, _pendingEvents.length - 25);
    }
  }

  Future<void> _flushEvents({String? email, String? displayName}) async {
    if (!isEnabled || !_initialized || _deviceId == null || _pendingEvents.isEmpty) {
      return;
    }

    final batch = List<Map<String, dynamic>>.from(_pendingEvents);
    _pendingEvents.clear();

    try {
      final response = await _post(
        AdminApiConfig.telemetryEventsUrl,
        {
          'deviceId': _deviceId,
          'email': email,
          'displayName': displayName,
          'appVersion': _appVersion,
          'platform': Platform.isAndroid ? 'android' : 'unknown',
          'events': batch,
        },
      );
      
      // Check for suspension status in response
      await _handleSuspensionResponse(response);
    } catch (e) {
      _pendingEvents.insertAll(0, batch);
      if (kDebugMode) debugPrint('Telemetry flush failed: $e');
    }
  }

  /// POST request that returns parsed JSON response
  Future<Map<String, dynamic>?> _post(String url, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'X-Telemetry-Key': AdminApiConfig.telemetryApiKey,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode >= 400) {
      throw HttpException('Telemetry HTTP ${response.statusCode}: ${response.body}');
    }
    
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
  
  /// Handle suspension status from server response and update local cache
  Future<void> _handleSuspensionResponse(Map<String, dynamic>? response) async {
    if (response == null) return;
    
    final suspended = response['suspended'] as bool? ?? false;
    final reason = response['suspendedReason'] as String?;
    
    // Only update cache if status changed or we're now suspended
    if (suspended != _cachedSuspended || suspended) {
      await _updateSuspensionCache(suspended, reason);
    }
  }
  
  /// Update local suspension cache in SharedPreferences
  Future<void> _updateSuspensionCache(bool suspended, String? reason) async {
    _cachedSuspended = suspended;
    _cachedSuspendedReason = reason;
    _cachedSuspendedCheckedAt = DateTime.now();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_suspendedKey, suspended);
    
    if (reason != null && suspended) {
      await prefs.setString(_suspendedReasonKey, reason);
    } else {
      await prefs.remove(_suspendedReasonKey);
    }
    
    await prefs.setString(_suspendedCheckedAtKey, _cachedSuspendedCheckedAt!.toIso8601String());
  }
  
  /// Check account suspension status with the server
  /// Returns the status and updates local cache for offline enforcement
  Future<SuspensionStatus> checkAccountStatus({String? email}) async {
    if (!isEnabled || !_initialized || _deviceId == null) {
      // If telemetry not configured, use cached status
      return SuspensionStatus(
        isSuspended: _cachedSuspended,
        reason: _cachedSuspendedReason,
        checkedAt: _cachedSuspendedCheckedAt,
      );
    }
    
    try {
      final userEmail = email ?? GoogleDriveService.instance.userEmail;
      
      final response = await _post(
        AdminApiConfig.telemetryStatusUrl,
        {
          'deviceId': _deviceId,
          'email': userEmail,
        },
      );
      
      if (response != null) {
        await _handleSuspensionResponse(response);
      }
      
      return SuspensionStatus(
        isSuspended: _cachedSuspended,
        reason: _cachedSuspendedReason,
        checkedAt: _cachedSuspendedCheckedAt,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Status check failed: $e');
      
      // On network error, return cached status (secure default: stay blocked if was blocked)
      return SuspensionStatus(
        isSuspended: _cachedSuspended,
        reason: _cachedSuspendedReason,
        checkedAt: _cachedSuspendedCheckedAt,
      );
    }
  }
  
  /// Get cached suspension status synchronously (for UI checks)
  SuspensionStatus getCachedSuspensionStatus() {
    return SuspensionStatus(
      isSuspended: _cachedSuspended,
      reason: _cachedSuspendedReason,
      checkedAt: _cachedSuspendedCheckedAt,
    );
  }
  
  /// Clear suspension cache (used when status is restored via unsuspend)
  Future<void> clearSuspensionCache() async {
    _cachedSuspended = false;
    _cachedSuspendedReason = null;
    _cachedSuspendedCheckedAt = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_suspendedKey);
    await prefs.remove(_suspendedReasonKey);
    await prefs.remove(_suspendedCheckedAtKey);
  }
}
