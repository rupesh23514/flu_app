import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'dart:async' show Completer, unawaited;
import 'dart:io';

import '../di/injection.dart';
import 'database_service.dart';
import 'migration_safety_service.dart';
import 'feature_flags_service.dart';
import 'reminder_service.dart';
import 'alarm_service.dart';
import 'transaction_service.dart';
import 'app_update_service.dart';
import 'workmanager_service.dart';
import 'oem_battery_helper.dart';

/// Bootstrap Service - Centralized app initialization
/// 
/// Separates concerns from main.dart by handling:
/// - Database initialization
/// - Dependency injection
/// - Service initialization (parallelized where possible)
/// - Background service setup
/// 
/// Note: Update checks are deferred to post-UI initialization for faster startup.
class BootstrapService {
  static final BootstrapService _instance = BootstrapService._internal();
  static BootstrapService get instance => _instance;
  BootstrapService._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  /// Prevents concurrent initialization - stores the ongoing Future
  Completer<bool>? _initializationCompleter;

  /// Initialize all app services in optimized order
  /// Returns true if all critical services initialized successfully
  /// Thread-safe: concurrent calls will wait for the first initialization to complete
  Future<bool> initialize() async {
    // Already initialized - return immediately
    if (_isInitialized) return true;
    
    // Initialization in progress - wait for it to complete
    if (_initializationCompleter != null) {
      return _initializationCompleter!.future;
    }
    
    // Start initialization with mutex
    _initializationCompleter = Completer<bool>();

    try {
      // === PHASE 1: Critical sequential initialization ===
      // These must run in order as they have dependencies
      await _initializeCriticalServices();

      // === PHASE 2: Parallel initialization of independent services ===
      await _initializeIndependentServices();

      // === PHASE 3: Notification services (depend on AndroidAlarmManager) ===
      await _initializeNotificationServices();

      // === PHASE 4: Background services (non-blocking) ===
      await _initializeBackgroundServices();

      _isInitialized = true;
      _initializationCompleter!.complete(true);
      if (kDebugMode) debugPrint('✅ All services initialized successfully');
      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Service initialization error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      // Complete with false but reset completer to allow retry
      _initializationCompleter!.complete(false);
      _initializationCompleter = null;  // Reset to allow retry on transient failures
      // Return false but allow app to continue (graceful degradation)
      return false;
    }
  }
  
  /// Perform update check after UI is rendered (non-blocking for startup)
  /// Call this from the splash screen or first frame callback
  Future<void> performDeferredUpdateCheck() async {
    try {
      await AppUpdateService.instance.initialize();
      final updateResult = await AppUpdateService.instance.performSafeUpdate();
      if (kDebugMode) debugPrint('Deferred update check result: $updateResult');
    } catch (e) {
      if (kDebugMode) debugPrint('Update check error (non-critical): $e');
    }
  }

  /// Phase 1: Critical services that must initialize sequentially
  Future<void> _initializeCriticalServices() async {
    // Step 1: Initialize database service (required by most services)
    debugPrint('Initializing database service...');
    await DatabaseService.instance.initializeDatabase();

    // Step 2: Configure dependency injection
    debugPrint('Configuring dependency injection...');
    await configureDependencies();
  }

  /// Phase 2: Independent services that can run in parallel
  Future<void> _initializeIndependentServices() async {
    debugPrint('Initializing independent services in parallel...');
    
    // First: Ensure transaction table exists (schema modification)
    await TransactionService.instance.ensureTransactionTable();
    
    // Then: Run validation and other independent tasks in parallel
    await Future.wait([
      // Feature flags - independent
      FeatureFlagsService.instance.initialize(),
      
      // Migration validation - runs AFTER schema is stable
      MigrationSafetyService.validateMigrationIntegrity().then((valid) {
        if (!valid && kDebugMode) {
          debugPrint('WARNING: Migration validation issues detected');
        }
      }),
      
      // AndroidAlarmManager - must be initialized BEFORE AlarmService (Android only)
      if (!kIsWeb && Platform.isAndroid)
        AndroidAlarmManager.initialize().then((_) {
          if (kDebugMode) debugPrint('✅ AndroidAlarmManager initialized');
        }),
    ]);
  }

  /// Phase 3: Notification services (depend on AndroidAlarmManager)
  Future<void> _initializeNotificationServices() async {
    debugPrint('Initializing notification services...');
    // Both services are independent - run in parallel
    await Future.wait([
      ReminderService.instance.initialize(),
      AlarmService.instance.initialize(),
    ]);
  }

  /// Phase 4: Background services (non-blocking, Android only)
  Future<void> _initializeBackgroundServices() async {
    // These are Android-specific and non-critical - fire and forget
    if (!kIsWeb && Platform.isAndroid) {
      debugPrint('Starting background services (non-blocking)...');
      // Don't await - let them initialize in background
      unawaited(Future.wait([
        WorkManagerService.instance.initialize(),
        OemBatteryHelper.instance.startForegroundService(),
      ]).catchError((e) {
        if (kDebugMode) debugPrint('Background service warning: $e');
        return <void>[];  // Return empty list to satisfy Future.wait return type
      }));
    }
  }
}
