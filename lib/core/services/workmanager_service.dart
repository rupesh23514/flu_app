import 'dart:io';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'alarm_service.dart';
import 'backup_service.dart';
import 'database_service.dart';
import 'google_drive_service.dart';

/// WorkManager Service for reliable background tasks:
/// - Periodic alarm verification (ensures alarms are never missed)
/// - Periodic auto-backup to Google Drive (if enabled)
class WorkManagerService {
  static final WorkManagerService _instance = WorkManagerService._internal();
  static WorkManagerService get instance => _instance;
  WorkManagerService._internal();

  // Task names
  static const String alarmCheckTask = 'alarm_verification_task';
  static const String periodicAlarmCheck = 'periodic_alarm_check';
  static const String autoBackupTask = 'auto_backup_task';
  static const String periodicAutoBackup = 'periodic_auto_backup';

  bool _isInitialized = false;

  /// Initialize WorkManager with callback dispatcher
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );

      // Register periodic task to verify alarms every 15 minutes
      await Workmanager().registerPeriodicTask(
        periodicAlarmCheck,
        alarmCheckTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 5),
      );

      // Register periodic auto-backup (runs daily, checks if due)
      await Workmanager().registerPeriodicTask(
        periodicAutoBackup,
        autoBackupTask,
        frequency: const Duration(hours: 24),
        constraints: Constraints(
          networkType: NetworkType.connected, // Requires internet for Drive upload
          requiresBatteryNotLow: true, // Don't drain battery
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: true,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 30),
      );

      _isInitialized = true;
      debugPrint('✅ WorkManager initialized with alarm check + auto-backup');
    } catch (e) {
      debugPrint('❌ WorkManager initialization error: $e');
    }
  }

  /// Cancel all WorkManager tasks
  Future<void> cancelAll() async {
    await Workmanager().cancelAll();
    _isInitialized = false;
    debugPrint('All WorkManager tasks cancelled');
  }

  /// Trigger immediate alarm verification (one-time task)
  Future<void> triggerImmediateVerification() async {
    try {
      await Workmanager().registerOneOffTask(
        'immediate_alarm_check_${DateTime.now().millisecondsSinceEpoch}',
        alarmCheckTask,
        constraints: Constraints(
          networkType: NetworkType.not_required,
        ),
      );
      debugPrint('🔄 Immediate alarm verification triggered');
    } catch (e) {
      debugPrint('Error triggering immediate verification: $e');
    }
  }
}

/// Top-level callback dispatcher for WorkManager
/// Must be a top-level function (not a class method)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('🔔 WorkManager task executing: $task');

    try {
      if (task == WorkManagerService.alarmCheckTask) {
        await _verifyAndRescheduleAlarms();
      } else if (task == WorkManagerService.autoBackupTask) {
        await _performAutoBackup();
      }
      return true;
    } catch (e) {
      debugPrint('❌ WorkManager task error: $e');
      return false;
    }
  });
}

/// Verify all scheduled alarms are still pending and reschedule if missing
Future<void> _verifyAndRescheduleAlarms() async {
  try {
    // Initialize services in background isolate
    await DatabaseService.instance.initializeDatabase();
    await AlarmService.instance.initialize();

    // Get pending notification alarms from system
    final pendingNotifications = await AlarmService.instance.getPendingAlarms();
    final pendingIds = pendingNotifications.map((n) => n.id).toSet();

    debugPrint('📋 System has ${pendingNotifications.length} pending alarms');

    // Get scheduled reminders from database
    final db = await DatabaseService.instance.database;
    final now = DateTime.now();
    
    final reminders = await db.query(
      'reminders',
      where: 'is_active = ? AND is_completed = ? AND scheduled_date > ?',
      whereArgs: [1, 0, now.toIso8601String()],
    );

    debugPrint('📋 Database has ${reminders.length} active future reminders');

    int rescheduledCount = 0;

    for (final reminder in reminders) {
      final reminderId = reminder['id'] as int;
      final title = reminder['title'] as String;
      final description = reminder['description'] as String? ?? '';
      final scheduledDateStr = reminder['scheduled_date'] as String;
      final scheduledDate = DateTime.parse(scheduledDateStr);

      // Check if this alarm is missing from system
      // Use safe 32-bit ID matching
      final safeId = reminderId.abs() % 2147483647;
      final isPending = pendingIds.contains(safeId);

      if (!isPending && scheduledDate.isAfter(now)) {
        // Reschedule missing alarm
        await AlarmService.instance.scheduleAlarm(
          id: safeId,
          title: title,
          description: description,
          scheduledDateTime: scheduledDate,
        );
        rescheduledCount++;
        debugPrint('🔄 Rescheduled missing alarm: $title (ID: $safeId)');
      }
    }

    if (rescheduledCount > 0) {
      debugPrint('✅ Rescheduled $rescheduledCount missing alarms');
    } else {
      debugPrint('✅ All alarms are properly scheduled');
    }
  } catch (e) {
    debugPrint('❌ Error verifying alarms: $e');
  }
}

/// Perform auto-backup to Google Drive if enabled
Future<void> _performAutoBackup() async {
  try {
    // Check if auto-backup is enabled
    final backupService = BackupService.instance;
    await backupService.initialize();

    final isEnabled = await backupService.isAutoBackupEnabled();
    if (!isEnabled) {
      debugPrint('📦 Auto-backup is disabled — skipping');
      return;
    }

    // Initialize services
    await DatabaseService.instance.initializeDatabase();
    final driveService = GoogleDriveService.instance;
    await driveService.initialize();

    if (!driveService.isSignedIn) {
      debugPrint('📦 Not signed in to Google Drive — skipping auto-backup');
      return;
    }

    // Create a safe copy and upload to Drive
    String tempCopyPath;
    try {
      tempCopyPath = await DatabaseService.instance.createSafeCopy();
    } catch (e) {
      debugPrint('❌ Auto-backup: Could not create database copy: $e');
      return;
    }

    final success = await driveService.uploadDatabase(tempCopyPath);

    // Clean up temp file
    try {
      await File(tempCopyPath).delete();
    } catch (_) {}

    if (success) {
      debugPrint('✅ Auto-backup to Google Drive completed successfully');
    } else {
      debugPrint('❌ Auto-backup failed: ${driveService.errorMessage}');
    }
  } catch (e) {
    debugPrint('❌ Auto-backup error: $e');
  }
}
