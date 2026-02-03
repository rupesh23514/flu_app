import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'dart:async';
import 'dart:io';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'database_service.dart';
import 'reminder_service.dart';
import '../../features/calendar/screens/calendar_screen.dart';
import 'oem_battery_helper.dart';

/// Global navigator key for showing alarm screens from background
GlobalKey<NavigatorState>? alarmNavigatorKey;

/// Set the navigator key from main.dart
void setAlarmNavigatorKey(GlobalKey<NavigatorState> key) {
  alarmNavigatorKey = key;
}

/// 🔔 VIVO BACKUP: Top-level callback for AndroidAlarmManager
/// CRITICAL: Must be a top-level function (not static class method) for release builds!
/// This is called when the backup alarm fires on Vivo/aggressive OEM devices
@pragma('vm:entry-point')
Future<void> vivoBackupAlarmCallback(int alarmId) async {
  // CRITICAL: Initialize Flutter bindings in background isolate
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('🔔 VIVO BACKUP: Alarm callback triggered for ID $alarmId');

  try {
    // Initialize services in the isolate
    await AlarmService.instance.initialize();

    // Get pending notifications to check if the main alarm already fired
    final pendingAlarms = await AlarmService.instance.getPendingAlarms();
    final originalId = alarmId - 100000; // Remove offset to get original ID

    // Check if original alarm is still pending (not fired yet)
    final isStillPending = pendingAlarms.any((a) => a.id == originalId);

    if (isStillPending) {
      // Main alarm didn't fire - show a notification NOW
      debugPrint(
          '🚨 VIVO BACKUP: Main alarm pending, showing fallback notification');

      // Cancel the pending (failed) notification
      await AlarmService.instance.cancelAlarm(originalId);

      // Show immediate notification
      await AlarmService.instance.showInstantAlarmNotification(
        id: originalId,
        title: '⏰ Reminder',
        body: 'You have a scheduled reminder',
      );
    } else {
      debugPrint('✅ VIVO BACKUP: Main alarm already fired, skipping backup');
    }
  } catch (e) {
    debugPrint('❌ VIVO BACKUP callback error: $e');
  }
}

/// 🏆 LEGENDARY Alarm Service - Enterprise-grade reminder system
/// Features:
/// - Exact alarms even when device is idle (Doze mode bypass)
/// - Lock screen display with full-screen intent
/// - Custom alarm sound with volume control
/// - Smart snooze with configurable durations
/// - Automatic alarm recovery after reboot
/// - Permission pre-checking with graceful fallbacks
/// - Battery optimization exemption handling
/// - Comprehensive error handling and logging
@pragma('vm:entry-point')
class AlarmService {
  @pragma('vm:entry-point')
  static final AlarmService _instance = AlarmService._internal();

  @pragma('vm:entry-point')
  static AlarmService get instance => _instance;

  @pragma('vm:entry-point')
  AlarmService._internal();

  /// Stream controller to broadcast alarm events to listeners
  @pragma('vm:entry-point')
  static final StreamController<AlarmData> _alarmStreamController =
      StreamController<AlarmData>.broadcast();

  /// Stream of alarm events
  @pragma('vm:entry-point')
  static Stream<AlarmData> get alarmStream => _alarmStreamController.stream;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;
  bool _isAlarmPlaying = false;
  Timer? _autoStopTimer; // Track timer to prevent memory leaks

  // Volume level (1-5, where 5 is max)
  int _volumeLevel = 5;

  // Snooze duration options in minutes
  static const List<int> snoozeDurations = [5, 10, 15, 30];
  int _defaultSnoozeMins = 5;

  /// Get current volume level (1-5)
  int get volumeLevel => _volumeLevel;

  /// Get default snooze duration
  int get defaultSnoozeMins => _defaultSnoozeMins;

  /// Set volume level (1-5) - only saves the setting, doesn't play sound
  Future<void> setVolumeLevel(int level) async {
    _volumeLevel = level.clamp(1, 5);
    // Save to preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('alarm_volume_level', _volumeLevel);
    } catch (e) {
      debugPrint('Error saving volume level: $e');
    }
    debugPrint('Alarm volume set to level $_volumeLevel');
  }

  /// Load volume level from SharedPreferences
  Future<void> _loadVolumeLevel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _volumeLevel = prefs.getInt('alarm_volume_level') ?? 5;
      _defaultSnoozeMins = prefs.getInt('alarm_snooze_duration') ?? 5;
      debugPrint(
          'Loaded alarm settings: volume=$_volumeLevel, snooze=$_defaultSnoozeMins');
    } catch (e) {
      debugPrint('Error loading alarm settings: $e');
    }
  }

  /// Set default snooze duration
  Future<void> setDefaultSnoozeDuration(int minutes) async {
    _defaultSnoozeMins = minutes;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('alarm_snooze_duration', minutes);
    } catch (e) {
      debugPrint('Error saving snooze duration: $e');
    }
  }

  // Callback for when alarm is triggered
  static Function(String title, String description, DateTime scheduledTime)?
      onAlarmTriggered;

  /// Initialize the alarm service
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Step 1: Initialize timezone data
      tz_data.initializeTimeZones();

      // Step 2: Set local timezone using device offset - CRITICAL FIX!
      _setLocalTimezone();

      // Android settings with full screen intent for alarm
      const androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      // iOS settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final result = await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            _backgroundNotificationHandler,
      );

      // Step 3: Create notification channel - REQUIRED for Android 8.0+
      await _createNotificationChannel();

      // Request notification permission for Android 13+
      await _requestPermissions();

      // Load saved volume level
      await _loadVolumeLevel();

      _isInitialized = result ?? false;
      debugPrint('✅ AlarmService initialized: $_isInitialized');
      return _isInitialized;
    } catch (e) {
      debugPrint('❌ AlarmService initialization error: $e');
      return false;
    }
  }

  /// Create notification channel for Android 8.0+
  Future<void> _createNotificationChannel() async {
    try {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // Create alarm channel with maximum importance and sound
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'alarm_channel_v2',
            'Alarms & Reminders',
            description: 'Scheduled alarms and task reminders with sound',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            showBadge: true,
            enableLights: true,
            ledColor: Colors.amber,
            // Use default notification sound (system alarm sound)
            sound: RawResourceAndroidNotificationSound('alarm_sound'),
          ),
        );
        debugPrint('✅ Notification channel created with sound');
      }
    } catch (e) {
      debugPrint('❌ Error creating notification channel: $e');
    }
  }

  /// Set local timezone based on device offset
  void _setLocalTimezone() {
    try {
      // Get the device's current timezone offset
      final now = DateTime.now();
      final offset = now.timeZoneOffset;

      // Map common Indian timezone offsets to timezone names
      String timezoneName;
      if (offset.inMinutes == 330) {
        // UTC+5:30 - India Standard Time
        timezoneName = 'Asia/Kolkata';
      } else if (offset.inMinutes == 0) {
        timezoneName = 'UTC';
      } else if (offset.inMinutes == -300) {
        timezoneName = 'America/New_York';
      } else if (offset.inMinutes == -480) {
        timezoneName = 'America/Los_Angeles';
      } else if (offset.inMinutes == 60) {
        timezoneName = 'Europe/London';
      } else if (offset.inMinutes == 540) {
        timezoneName = 'Asia/Tokyo';
      } else if (offset.inMinutes == 480) {
        timezoneName = 'Asia/Singapore';
      } else if (offset.inMinutes == 345) {
        timezoneName = 'Asia/Kathmandu';
      } else {
        // Default to India timezone for this app
        timezoneName = 'Asia/Kolkata';
      }

      tz.setLocalLocation(tz.getLocation(timezoneName));
      debugPrint(
          '✅ Timezone configured: $timezoneName (offset: ${offset.inMinutes} mins)');
    } catch (e) {
      // Fallback to India timezone
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      debugPrint('⚠️ Using fallback timezone: Asia/Kolkata (error: $e)');
    }
  }

  /// Request all required permissions
  Future<void> _requestPermissions() async {
    try {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        // Request notification permission (Android 13+)
        final notificationGranted =
            await androidPlugin.requestNotificationsPermission();
        debugPrint('Notification permission: $notificationGranted');

        // Request exact alarm permission (Android 12+)
        final exactAlarmGranted =
            await androidPlugin.requestExactAlarmsPermission();
        debugPrint('Exact alarm permission: $exactAlarmGranted');

        // Verify exact alarms can be scheduled
        final canScheduleExact =
            await androidPlugin.canScheduleExactNotifications();
        if (canScheduleExact != true) {
          debugPrint(
              '⚠️ WARNING: Cannot schedule exact alarms - notifications may be delayed');
        } else {
          debugPrint('✅ Exact alarms can be scheduled');
        }
      }
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
    }
  }

  @pragma('vm:entry-point')
  void _onNotificationResponse(NotificationResponse response) {
    debugPrint(
        'Alarm notification action: ${response.actionId}, payload: ${response.payload}');

    // Handle snooze action
    if (response.actionId == 'snooze_alarm') {
      _handleSnooze(response.payload);
      return;
    }

    // Handle dismiss action - FULL SYNC with database and calendar
    if (response.actionId == 'dismiss_alarm') {
      _handleDismiss(response.payload);
      return;
    }

    // When notification is tapped (not snooze/dismiss), show full screen alarm
    if (response.payload != null) {
      _showAlarmScreen(response.payload!);
    } else {
      stopAlarmSound();
    }
  }

  /// Handle dismiss action from notification - sync with DB and calendar
  @pragma('vm:entry-point')
  Future<void> _handleDismiss(String? payload) async {
    stopAlarmSound();

    if (payload == null) return;

    try {
      // Parse payload: notificationId|databaseId|title|description|datetime
      final parts = payload.split('|');
      if (parts.length >= 2) {
        // Use databaseId (parts[1]) for database operations
        final databaseId =
            int.tryParse(parts[1]) ?? int.tryParse(parts[0]) ?? 0;

        debugPrint('🔴 Notification DISMISS: databaseId=$databaseId');

        // 1. DATABASE SYNC: Delete reminder from database
        try {
          await ReminderService.instance.dismissReminder(databaseId);
          debugPrint(
              '✅ Notification dismiss: Reminder $databaseId removed from DB');
        } catch (e) {
          debugPrint('⚠️ Notification dismiss DB sync: $e');
        }

        // 2. CALENDAR SYNC: Delete from SharedPreferences
        await CalendarEventSync.deleteEventByAlarmId(databaseId);
        debugPrint('✅ Notification dismiss: Event deleted from calendar');
      }
    } catch (e) {
      debugPrint('⚠️ Error in _handleDismiss: $e');
    }
  }

  /// Show the full-screen alarm UI
  @pragma('vm:entry-point')
  void _showAlarmScreen(String payload) {
    try {
      // Parse payload: notificationId|databaseId|title|description|datetime
      final parts = payload.split('|');
      if (parts.length >= 5) {
        final alarmId = int.tryParse(parts[0]) ?? 0;
        final databaseId = int.tryParse(parts[1]) ?? alarmId;
        final title = parts[2];
        final description = parts[3];
        final dateTimeStr = parts[4];
        final scheduledTime = DateTime.tryParse(dateTimeStr) ?? DateTime.now();

        // Play alarm sound when notification triggers
        playAlarmSound(durationSeconds: 60);

        // Emit alarm event to stream with database ID
        final alarmData = AlarmData(
          id: alarmId,
          databaseId: databaseId,
          title: title,
          description: description,
          scheduledTime: scheduledTime,
        );
        _alarmStreamController.add(alarmData);
        debugPrint('🔔 Alarm event emitted: $title (dbId=$databaseId)');
      }
    } catch (e) {
      debugPrint('Error parsing alarm payload: $e');
      stopAlarmSound();
    }
  }

  /// Handle snooze action - reschedule alarm
  @pragma('vm:entry-point')
  Future<void> _handleSnooze(String? payload) async {
    stopAlarmSound();

    if (payload == null) return;

    try {
      // Parse payload: notificationId|databaseId|title|description|datetime
      final parts = payload.split('|');
      if (parts.length >= 5) {
        final databaseId =
            int.tryParse(parts[1]) ?? int.tryParse(parts[0]) ?? 0;
        final title = parts[2];
        final description = parts[3];

        // Schedule new alarm after snooze duration
        final snoozeTime =
            DateTime.now().add(Duration(minutes: _defaultSnoozeMins));

        // 1. DATABASE SYNC: Update reminder time in database
        try {
          await DatabaseService.instance
              .updateReminderTime(databaseId, snoozeTime);
          debugPrint('✅ Snooze: Reminder $databaseId time updated in DB');
        } catch (e) {
          debugPrint('⚠️ Snooze DB sync: $e');
        }

        // 2. CALENDAR SYNC: Update in SharedPreferences
        await CalendarEventSync.updateEventTimeByAlarmId(
            databaseId, snoozeTime);

        // 3. Schedule new alarm with snoozed notification ID but same database ID
        await scheduleAlarm(
          id: databaseId + 1000, // New notification ID for snoozed alarm
          databaseId: databaseId, // Keep original database ID
          title: title,
          description: description,
          scheduledDateTime: snoozeTime,
          playSound: true,
          vibrate: true,
          fullScreenIntent: true,
        );

        debugPrint(
            '✅ Alarm snoozed for $_defaultSnoozeMins minutes (dbId=$databaseId)');
      }
    } catch (e) {
      debugPrint('Error handling snooze: $e');
    }
  }

  @pragma('vm:entry-point')
  static void _backgroundNotificationHandler(NotificationResponse response) {
    debugPrint('Background notification received: ${response.payload}');
    debugPrint('Action ID: ${response.actionId}');

    // Handle dismiss action in background - sync with DB and calendar
    if (response.actionId == 'dismiss_alarm') {
      _handleBackgroundDismiss(response.payload);
      return;
    }

    // Handle snooze action in background
    if (response.actionId == 'snooze_alarm') {
      _handleBackgroundSnooze(response.payload);
      return;
    }

    // For background notifications, we need to trigger the alarm stream
    // This will be picked up by the app when it comes to foreground
    if (response.payload != null) {
      try {
        // Parse payload: notificationId|databaseId|title|description|datetime
        final parts = response.payload!.split('|');
        if (parts.length >= 5) {
          final alarmId = int.tryParse(parts[0]) ?? 0;
          final databaseId = int.tryParse(parts[1]) ?? alarmId;
          final title = parts[2];
          final description = parts[3];
          final dateTimeStr = parts[4];
          final scheduledTime =
              DateTime.tryParse(dateTimeStr) ?? DateTime.now();

          // Emit alarm event to stream - this triggers full screen in app.dart
          final alarmData = AlarmData(
            id: alarmId,
            databaseId: databaseId,
            title: title,
            description: description,
            scheduledTime: scheduledTime,
          );
          _alarmStreamController.add(alarmData);
          debugPrint(
              '🔔 Background alarm event emitted: $title (dbId=$databaseId)');
        }
      } catch (e) {
        debugPrint('Error in background handler: $e');
      }
    }
  }

  /// Handle dismiss action from background notification
  @pragma('vm:entry-point')
  static Future<void> _handleBackgroundDismiss(String? payload) async {
    if (payload == null) return;

    try {
      // Parse payload: notificationId|databaseId|title|description|datetime
      final parts = payload.split('|');
      if (parts.length >= 2) {
        // Use databaseId (parts[1]) for database operations
        final databaseId =
            int.tryParse(parts[1]) ?? int.tryParse(parts[0]) ?? 0;

        debugPrint('🔴 Background DISMISS: databaseId=$databaseId');

        // 1. DATABASE SYNC: Delete reminder from database
        try {
          await ReminderService.instance.dismissReminder(databaseId);
          debugPrint(
              '✅ Background dismiss: Reminder $databaseId removed from DB');
        } catch (e) {
          debugPrint('⚠️ Background dismiss DB sync: $e');
        }

        // 2. CALENDAR SYNC: Delete from SharedPreferences
        await CalendarEventSync.deleteEventByAlarmId(databaseId);
        debugPrint('✅ Background dismiss: Event deleted from calendar');
      }
    } catch (e) {
      debugPrint('⚠️ Error in _handleBackgroundDismiss: $e');
    }
  }

  /// Handle snooze action from background notification
  @pragma('vm:entry-point')
  static Future<void> _handleBackgroundSnooze(String? payload) async {
    if (payload == null) return;

    try {
      // Parse payload: notificationId|databaseId|title|description|datetime
      final parts = payload.split('|');
      if (parts.length >= 5) {
        final databaseId =
            int.tryParse(parts[1]) ?? int.tryParse(parts[0]) ?? 0;
        final title = parts[2];
        final description = parts[3];

        // Use default snooze duration
        const snoozeMins = 5;
        final snoozeTime =
            DateTime.now().add(const Duration(minutes: snoozeMins));

        debugPrint(
            '🔵 Background SNOOZE: databaseId=$databaseId, snoozeTime=$snoozeTime');

        // 1. DATABASE SYNC: Update reminder time in database
        try {
          await DatabaseService.instance
              .updateReminderTime(databaseId, snoozeTime);
          debugPrint(
              '✅ Background snooze: Reminder $databaseId time updated in DB');
        } catch (e) {
          debugPrint('⚠️ Background snooze DB sync: $e');
        }

        // 2. CALENDAR SYNC: Update in SharedPreferences
        await CalendarEventSync.updateEventTimeByAlarmId(
            databaseId, snoozeTime);
        debugPrint('✅ Background snooze: Event updated in calendar');

        // 3. Schedule new alarm for snooze time
        await AlarmService.instance.scheduleAlarm(
          id: databaseId + 1000,
          databaseId: databaseId,
          title: title,
          description: description,
          scheduledDateTime: snoozeTime,
          playSound: true,
          vibrate: true,
          fullScreenIntent: true,
        );
        debugPrint('✅ Background snooze: Alarm rescheduled for $snoozeTime');
      }
    } catch (e) {
      debugPrint('⚠️ Error in _handleBackgroundSnooze: $e');
    }
  }

  /// Schedule an alarm with specific date and time
  Future<bool> scheduleAlarm({
    required int id,
    int? databaseId, // Original database ID (for snoozed alarms)
    required String title,
    required String description,
    required DateTime scheduledDateTime,
    bool playSound = true,
    bool vibrate = true,
    bool fullScreenIntent = true,
  }) async {
    // Use provided databaseId or fall back to notification id
    final dbId = databaseId ?? id;
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // CRITICAL: Check permissions before scheduling
      var hasPermissions = await checkPermissions();

      // AUTO-REQUEST permissions if not granted
      if (!hasPermissions['notification']! || !hasPermissions['exactAlarm']!) {
        debugPrint('🔐 Auto-requesting missing alarm permissions...');
        hasPermissions = await requestPermissions();
      }

      // Final check after requesting
      if (!hasPermissions['notification']!) {
        debugPrint('❌ Notification permission not granted after request');
        return false;
      }
      if (!hasPermissions['exactAlarm']!) {
        debugPrint('❌ Exact alarm permission not granted after request');
        return false;
      }

      // Create notification details with alarm settings for lock screen
      final androidDetails = AndroidNotificationDetails(
        'alarm_channel_v2',
        'Alarms & Reminders',
        channelDescription: 'Scheduled alarms and task reminders with sound',
        importance: Importance.max,
        priority: Priority.max,
        ticker: title,
        icon: '@mipmap/launcher_icon',
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
        playSound: playSound,
        sound: const RawResourceAndroidNotificationSound('alarm_sound'),
        enableVibration: vibrate,
        fullScreenIntent: fullScreenIntent,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        autoCancel: false,
        ongoing: true, // Keep notification until user interacts
        // Show on lock screen
        showWhen: true,
        when: scheduledDateTime.millisecondsSinceEpoch,
        usesChronometer: false,
        chronometerCountDown: false,
        timeoutAfter: 300000, // Auto dismiss after 5 mins if not interacted
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            'dismiss_alarm',
            'Dismiss',
            icon: DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'snooze_alarm',
            'Snooze $_defaultSnoozeMins min',
            icon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
            showsUserInterface: false,
          ),
        ],
        styleInformation: BigTextStyleInformation(
          description.isNotEmpty ? description : title,
          htmlFormatBigText: false,
          contentTitle: title,
          htmlFormatContentTitle: false,
          summaryText: _formatDateTime(scheduledDateTime),
          htmlFormatSummaryText: false,
        ),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Convert to TZDateTime using LOCAL timezone
      final tzScheduledDate = tz.TZDateTime.from(scheduledDateTime, tz.local);
      final now = tz.TZDateTime.now(tz.local);

      debugPrint('📅 Scheduling alarm:');
      debugPrint('   Title: $title');
      debugPrint('   Scheduled DateTime: $scheduledDateTime');
      debugPrint('   TZ Scheduled: $tzScheduledDate');
      debugPrint('   Current TZ time: $now');
      debugPrint('   Local timezone: ${tz.local.name}');

      // Only schedule future notifications
      if (tzScheduledDate.isAfter(now)) {
        // Use safe 32-bit alarm ID
        final safeId = id.abs() % 2147483647;

        await _notificationsPlugin.zonedSchedule(
          safeId,
          '🔔 $title',
          description,
          tzScheduledDate,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          // Payload format: notificationId|databaseId|title|description|scheduledDateTime
          payload:
              '$safeId|$dbId|$title|$description|${scheduledDateTime.toIso8601String()}',
        );

        final diff = tzScheduledDate.difference(now);
        debugPrint('✅ Alarm scheduled successfully!');
        debugPrint(
            '   Will trigger in: ${diff.inMinutes} minutes (${diff.inSeconds} seconds)');

        // 🔔 VIVO FIX: Add AndroidAlarmManager as backup for aggressive OEMs
        // Vivo/iQOO devices may kill flutter_local_notifications even with exact alarms
        // AndroidAlarmManager uses a different system path that's more reliable
        try {
          final isVivo = await OemBatteryHelper.instance.isVivoDevice();
          final isAggressiveOem =
              await OemBatteryHelper.instance.isAggressiveOem();

          if (isVivo || isAggressiveOem) {
            // Schedule backup alarm using AndroidAlarmManager
            // This will call the callback even if notification system is killed
            final backupSuccess = await AndroidAlarmManager.oneShotAt(
              scheduledDateTime,
              safeId + 100000, // Offset ID to avoid conflict
              vivoBackupAlarmCallback, // Top-level function for release builds
              exact: true,
              wakeup: true,
              rescheduleOnReboot: true,
              allowWhileIdle: true,
              alarmClock:
                  true, // Uses AlarmManager.setAlarmClock (highest priority)
            );

            if (backupSuccess) {
              debugPrint(
                  '   🔔 VIVO: Backup AndroidAlarmManager alarm scheduled!');
            } else {
              debugPrint('   ⚠️ VIVO: Backup alarm scheduling failed');
            }
          }
        } catch (e) {
          debugPrint('   ⚠️ Backup alarm scheduling error (non-critical): $e');
        }

        return true;
      } else {
        debugPrint('❌ Cannot schedule alarm for past time');
        debugPrint('   Scheduled: $tzScheduledDate');
        debugPrint('   Now: $now');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error scheduling alarm: $e');
      return false;
    }
  }

  /// 🔔 Show an instant alarm notification (for backup/fallback scenarios)
  /// This is used when scheduled notifications fail to fire
  Future<void> showInstantAlarmNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      const androidDetails = AndroidNotificationDetails(
        'alarm_channel_v2',
        'Alarms & Reminders',
        channelDescription: 'Scheduled alarms and task reminders with sound',
        importance: Importance.max,
        priority: Priority.max,
        ticker: 'Alarm',
        icon: '@mipmap/launcher_icon',
        playSound: true,
        sound: RawResourceAndroidNotificationSound('alarm_sound'),
        enableVibration: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        autoCancel: false,
        ongoing: true,
        timeoutAfter: 300000, // 5 minutes
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        id,
        '🔔 $title',
        body,
        notificationDetails,
        payload: payload,
      );

      // Play alarm sound
      await playAlarmSound(durationSeconds: 60);

      debugPrint('🔔 Instant alarm notification shown: $title');
    } catch (e) {
      debugPrint('❌ Error showing instant alarm: $e');
    }
  }

  // Native alarm player channel - respects ringer mode
  static const _alarmPlayerChannel = MethodChannel('flu_app/alarm_player');
  bool _isNativeAlarmPlaying = false;

  /// 🔔 Play alarm sound - RESPECTS phone's ringer mode
  /// - Normal mode: Sound + Vibrate
  /// - Vibrate mode: Vibrate only (no sound)
  /// - Silent mode: No sound, no vibration (notification only)
  Future<void> playAlarmSound(
      {int durationSeconds = 30, bool bypassSilentMode = false}) async {
    if (_isAlarmPlaying || _isNativeAlarmPlaying) return;

    try {
      // Acquire WakeLock to keep CPU awake during alarm playback
      try {
        await WakelockPlus.enable();
        debugPrint('WakeLock acquired for alarm');
      } catch (e) {
        debugPrint('Could not acquire WakeLock: $e');
      }

      // Check phone's ringer mode
      final ringerMode = await _getRingerMode();
      debugPrint('📱 Phone ringer mode: ${_getRingerModeName(ringerMode)}');

      // Calculate volume (1-5 converted to 0.4-1.0)
      final volume = 0.2 + (_volumeLevel * 0.16);
      final clampedVolume = volume.clamp(0.4, 1.0);

      // Respect ringer mode
      if (ringerMode == 0) {
        // SILENT MODE - No sound, no vibration
        debugPrint('🔕 Phone is in SILENT mode - showing notification only');
        await WakelockPlus.disable();
        return;
      } else if (ringerMode == 1) {
        // VIBRATE MODE - Vibrate only, no sound
        debugPrint('📳 Phone is in VIBRATE mode - vibrating only');
        try {
          await _alarmPlayerChannel.invokeMethod('vibrateAlarm');
          _isNativeAlarmPlaying = true;

          // Auto-stop after duration
          _autoStopTimer?.cancel();
          _autoStopTimer = Timer(Duration(seconds: durationSeconds), () {
            stopAlarmSound();
          });
        } catch (e) {
          debugPrint('Vibration failed: $e');
        }
        return;
      }

      // NORMAL MODE - Play sound + vibrate
      debugPrint('🔔 Phone is in NORMAL mode - playing sound + vibration');

      try {
        await _alarmPlayerChannel
            .invokeMethod('playAlarmSound', {'volume': clampedVolume});
        _isNativeAlarmPlaying = true;

        // Also vibrate in normal mode
        await _alarmPlayerChannel.invokeMethod('vibrateAlarm');

        debugPrint(
            '🔔 Alarm sound + vibration playing at volume: $clampedVolume');

        // Auto-stop after duration
        _autoStopTimer?.cancel();
        _autoStopTimer = Timer(Duration(seconds: durationSeconds), () {
          stopAlarmSound();
        });

        return;
      } catch (e) {
        debugPrint(
            'Native alarm player failed, falling back to just_audio: $e');
        // Fall through to just_audio fallback
      }

      // Fallback to just_audio
      _isAlarmPlaying = true;

      try {
        await _audioPlayer.setAsset('assets/sounds/alarm_sound.mp3');
      } catch (e) {
        debugPrint('Bundled sound not found, trying system default: $e');
        try {
          await _audioPlayer.setUrl('content://settings/system/alarm_alert');
        } catch (e2) {
          debugPrint('Could not load any alarm sound: $e2');
          _isAlarmPlaying = false;
          await WakelockPlus.disable();
          return;
        }
      }

      await _audioPlayer.setLoopMode(LoopMode.one);
      await _audioPlayer.setVolume(clampedVolume);
      await _audioPlayer.play();

      // Auto-stop after duration
      _autoStopTimer?.cancel();
      _autoStopTimer = Timer(Duration(seconds: durationSeconds), () {
        stopAlarmSound();
      });

      debugPrint(
          'Alarm sound playing via just_audio at volume: $clampedVolume');
    } catch (e) {
      debugPrint('Error playing alarm sound: $e');
      _isAlarmPlaying = false;
      _isNativeAlarmPlaying = false;
      await WakelockPlus.disable();
    }
  }

  /// Get ringer mode: 0 = SILENT, 1 = VIBRATE, 2 = NORMAL
  Future<int> _getRingerMode() async {
    try {
      const platform = MethodChannel('flu_app/audio_mode');
      final int ringerMode = await platform.invokeMethod('getRingerMode');
      return ringerMode;
    } catch (e) {
      debugPrint('Could not check ringer mode: $e');
      return 2; // Default to NORMAL mode
    }
  }

  String _getRingerModeName(int mode) {
    switch (mode) {
      case 0:
        return 'SILENT';
      case 1:
        return 'VIBRATE';
      case 2:
        return 'NORMAL';
      default:
        return 'UNKNOWN';
    }
  }

  /// Stop alarm sound (both native and just_audio)
  Future<void> stopAlarmSound() async {
    try {
      // Cancel auto-stop timer to prevent memory leak
      _autoStopTimer?.cancel();
      _autoStopTimer = null;

      // Stop native alarm player if playing
      if (_isNativeAlarmPlaying) {
        try {
          await _alarmPlayerChannel.invokeMethod('stopAlarmSound');
          await _alarmPlayerChannel.invokeMethod('stopVibrate');
          debugPrint('🔕 Native alarm sound stopped');
        } catch (e) {
          debugPrint('Error stopping native alarm: $e');
        }
        _isNativeAlarmPlaying = false;
      }

      // Stop just_audio player
      await _audioPlayer.stop();
      _isAlarmPlaying = false;

      // Release WakeLock when sound stops
      try {
        await WakelockPlus.disable();
        debugPrint('WakeLock released');
      } catch (e) {
        debugPrint('Error releasing WakeLock: $e');
      }
      debugPrint('Alarm sound stopped');
    } catch (e) {
      debugPrint('Error stopping alarm sound: $e');
    }
  }

  /// 🔐 Check if all required permissions are granted - LEGENDARY version
  /// Returns detailed permission status map
  Future<Map<String, bool>> checkPermissions() async {
    final results = <String, bool>{
      'notification': false,
      'exactAlarm': false,
      'batteryOptimization': false,
      'allCritical': false,
    };

    try {
      // Method 1: Use permission_handler (more reliable on Android 12+)
      final notificationPermission = await ph.Permission.notification.status;
      final exactAlarmPermission =
          await ph.Permission.scheduleExactAlarm.status;

      results['notification'] = notificationPermission.isGranted;
      results['exactAlarm'] = exactAlarmPermission.isGranted;

      // Method 2: Double-check with flutter_local_notifications plugin
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // Fallback check if permission_handler reports false
        if (!results['notification']!) {
          final notificationEnabled =
              await androidPlugin.areNotificationsEnabled();
          results['notification'] = notificationEnabled ?? false;
        }

        // Fallback check for exact alarms
        if (!results['exactAlarm']!) {
          final canScheduleExact =
              await androidPlugin.canScheduleExactNotifications();
          results['exactAlarm'] = canScheduleExact ?? false;
        }
      }

      // Check battery optimization
      final batteryStatus =
          await ph.Permission.ignoreBatteryOptimizations.status;
      results['batteryOptimization'] = batteryStatus.isGranted;

      // All critical permissions check
      results['allCritical'] =
          results['notification']! && results['exactAlarm']!;

      debugPrint('🔐 Permission Status:');
      debugPrint(
          '   📱 Notifications: ${results['notification']! ? "✅" : "❌"}');
      debugPrint('   ⏰ Exact Alarms: ${results['exactAlarm']! ? "✅" : "❌"}');
      debugPrint(
          '   🔋 Battery Opt: ${results['batteryOptimization']! ? "✅" : "❌"}');
      debugPrint('   ✨ All Critical: ${results['allCritical']! ? "✅" : "❌"}');
    } catch (e) {
      debugPrint('❌ Error checking permissions: $e');
    }

    return results;
  }

  /// 🚀 Request all required permissions - returns detailed status
  Future<Map<String, bool>> requestPermissions() async {
    debugPrint('🔐 Requesting all alarm permissions...');

    try {
      // Method 1: Use permission_handler for Android 12+ (more reliable)
      final notificationStatus = await ph.Permission.notification.request();
      debugPrint(
          '   📱 Notification (permission_handler): ${notificationStatus.isGranted ? "✅" : "❌"}');

      final scheduleExactStatus =
          await ph.Permission.scheduleExactAlarm.request();
      debugPrint(
          '   ⏰ Schedule Exact Alarm (permission_handler): ${scheduleExactStatus.isGranted ? "✅" : "❌"}');

      // Method 2: Fallback to flutter_local_notifications plugin
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // Request via plugin as backup
        if (!notificationStatus.isGranted) {
          await androidPlugin.requestNotificationsPermission();
          debugPrint('   📱 Notification (plugin fallback) requested');
        }

        // Request exact alarm permission via plugin as backup
        if (!scheduleExactStatus.isGranted) {
          await androidPlugin.requestExactAlarmsPermission();
          debugPrint('   ⏰ Exact alarm (plugin fallback) requested');
        }
      }

      // Request battery optimization exemption
      final batteryStatus =
          await ph.Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted) {
        await ph.Permission.ignoreBatteryOptimizations.request();
        debugPrint('   🔋 Battery optimization requested');
      }
    } catch (e) {
      debugPrint('❌ Error requesting permissions: $e');
    }

    // Return current status after requesting
    return checkPermissions();
  }

  /// 🎯 Open exact alarm permission settings directly (Android 12+)
  /// This opens the "Alarms & reminders" settings page for the app
  Future<bool> openExactAlarmSettings() async {
    if (!Platform.isAndroid) return false;

    try {
      // Try to open the exact alarm permission settings directly
      const intent = AndroidIntent(
        action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
        package: 'com.example.flu_app', // Replace with your package name
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      debugPrint('✅ Opened exact alarm settings');
      return true;
    } catch (e) {
      debugPrint('⚠️ Could not open exact alarm settings: $e');
      // Fallback to general app settings
      await ph.openAppSettings();
      return false;
    }
  }

  /// 🔔 Open notification permission settings directly
  Future<bool> openNotificationSettings() async {
    if (!Platform.isAndroid) return false;

    try {
      // ignore: prefer_const_constructors - arguments map cannot be const
      final intent = AndroidIntent(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: {
          'android.provider.extra.APP_PACKAGE': 'com.example.flu_app',
        },
        flags: const <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      debugPrint('✅ Opened notification settings');
      return true;
    } catch (e) {
      debugPrint('⚠️ Could not open notification settings: $e');
      await ph.openAppSettings();
      return false;
    }
  }

  /// 🔋 Open battery optimization settings
  Future<bool> openBatterySettings() async {
    if (!Platform.isAndroid) return false;

    try {
      const intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:com.example.flu_app',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      debugPrint('✅ Opened battery settings');
      return true;
    } catch (e) {
      debugPrint('⚠️ Could not open battery settings: $e');
      await ph.openAppSettings();
      return false;
    }
  }

  /// 🚀 Smart permission request with automatic settings navigation
  /// Shows dialog and opens correct settings page based on what's missing
  Future<bool> requestPermissionsWithDialog(BuildContext context) async {
    final status = await checkPermissions();

    // If all permissions granted, return true
    if (status['allCritical']!) {
      return true;
    }

    // Check if context is still valid after async operation
    if (!context.mounted) {
      return false;
    }

    // Determine what's missing and show appropriate dialog
    final bool needsNotification = !status['notification']!;
    final bool needsExactAlarm = !status['exactAlarm']!;

    // Build message
    String title = '📱 Permission Required';
    String message = '';

    if (needsNotification && needsExactAlarm) {
      message = 'To set reminders, the app needs:\n\n'
          '• 📱 Notification permission - to show alerts\n'
          '• ⏰ Alarm permission - to trigger at exact times\n\n'
          'Tap "Open Settings" to enable these permissions.';
    } else if (needsNotification) {
      message =
          'To show reminder alerts, please enable notification permission.\n\n'
          'Tap "Open Settings" to enable notifications.';
    } else if (needsExactAlarm) {
      message =
          'To trigger reminders at the exact scheduled time, please enable the "Alarms & reminders" permission.\n\n'
          'Go to: Settings → Apps → Money Lender → Alarms & reminders → Enable\n\n'
          'Tap "Open Settings" to go there directly.';
    }

    // Show dialog
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              needsExactAlarm ? Icons.alarm_off : Icons.notifications_off,
              color: Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 14, height: 1.5)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'After enabling, return to the app to set your reminder.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Open Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      // Open the appropriate settings page
      if (needsExactAlarm) {
        await openExactAlarmSettings();
      } else if (needsNotification) {
        await openNotificationSettings();
      }

      // Wait for user to return and re-check
      await Future.delayed(const Duration(milliseconds: 500));
      final newStatus = await checkPermissions();
      return newStatus['allCritical']!;
    }

    return false;
  }

  /// 🎯 Comprehensive permission check with context for UI feedback
  Future<PermissionCheckResult> checkPermissionsWithDetails() async {
    final status = await checkPermissions();
    final missingPermissions = <String>[];

    if (!status['notification']!) {
      missingPermissions.add('Notifications');
    }
    if (!status['exactAlarm']!) {
      missingPermissions.add('Exact Alarms');
    }
    if (!status['batteryOptimization']!) {
      missingPermissions.add('Battery Optimization');
    }

    return PermissionCheckResult(
      isReady: status['allCritical']!,
      missingPermissions: missingPermissions,
      score: _calculatePermissionScore(status),
      status: status,
    );
  }

  int _calculatePermissionScore(Map<String, bool> status) {
    int score = 0;
    if (status['notification']!) score += 40;
    if (status['exactAlarm']!) score += 40;
    if (status['batteryOptimization']!) score += 20;
    return score;
  }

  /// Open app settings for manual permission configuration
  Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }

  /// Cancel a scheduled alarm
  Future<void> cancelAlarm(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
      debugPrint('Alarm cancelled: $id');
    } catch (e) {
      debugPrint('Error cancelling alarm: $e');
    }
  }

  /// Cancel all scheduled alarms
  Future<void> cancelAllAlarms() async {
    try {
      await _notificationsPlugin.cancelAll();
      debugPrint('All alarms cancelled');
    } catch (e) {
      debugPrint('Error cancelling all alarms: $e');
    }
  }

  /// Get all pending alarms
  Future<List<PendingNotificationRequest>> getPendingAlarms() async {
    try {
      return await _notificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      debugPrint('Error getting pending alarms: $e');
      return [];
    }
  }

  /// Show immediate notification (for testing or triggered alarms)
  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String description,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        'alarm_channel_v2',
        'Alarms & Reminders',
        channelDescription: 'Scheduled alarms and task reminders with sound',
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/launcher_icon',
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm_sound'),
        enableVibration: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        ongoing: true,
        autoCancel: false,
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            'dismiss_alarm',
            'Dismiss',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'snooze_alarm',
            'Snooze $_defaultSnoozeMins min',
            showsUserInterface: false,
          ),
        ],
        styleInformation: BigTextStyleInformation(
          description,
          contentTitle: title,
          summaryText: 'Now',
        ),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final payload =
          '$id|$id|$title|$description|${DateTime.now().toIso8601String()}';
      await _notificationsPlugin
          .show(id, title, description, notificationDetails, payload: payload);
      debugPrint('Immediate notification shown: $title');
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  /// Format date time for display
  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = _getMonthName(dt.month);
    final year = dt.year;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day $month $year, $hour:$minute $period';
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  /// Get day name
  static String getDayName(DateTime date) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return days[date.weekday - 1];
  }

  /// Test alarm - shows alarm screen immediately for testing
  void testAlarm({
    String title = 'Test Alarm',
    String description = 'This is a test alarm',
  }) {
    final alarmData = AlarmData(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: title,
      description: description,
      scheduledTime: DateTime.now(),
    );

    // Play alarm sound
    playAlarmSound(durationSeconds: 60);

    // Emit to stream so app can show the full screen
    _alarmStreamController.add(alarmData);
    debugPrint('Test alarm triggered: $title');
  }

  /// Verify all scheduled alarms and reschedule any missing ones
  /// Call this on app resume and periodically via WorkManager
  Future<int> verifyAndRescheduleAlarms() async {
    try {
      // Get pending notification alarms from system
      final pendingNotifications = await getPendingAlarms();
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
        final safeId = reminderId.abs() % 2147483647;
        final isPending = pendingIds.contains(safeId);

        if (!isPending && scheduledDate.isAfter(now)) {
          // Reschedule missing alarm
          await scheduleAlarm(
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

      return rescheduledCount;
    } catch (e) {
      debugPrint('❌ Error verifying alarms: $e');
      return 0;
    }
  }

  /// Dispose resources
  void dispose() {
    // Cancel any pending timers
    _autoStopTimer?.cancel();
    _autoStopTimer = null;

    // Stop any playing sound
    if (_isAlarmPlaying) {
      stopAlarmSound();
    }

    // Dispose audio player
    try {
      _audioPlayer.dispose();
    } catch (e) {
      debugPrint('Error disposing audio player: $e');
    }

    // Note: StreamController is static and broadcast, should only close on app termination
    // Do not close it here as it may be used across app lifecycle
    debugPrint('AlarmService resources disposed');
  }
}

/// Data class to hold alarm information
class AlarmData {
  final int id; // Notification ID (may change with snooze)
  final int databaseId; // Original database ID (never changes)
  final String title;
  final String description;
  final DateTime scheduledTime;

  AlarmData({
    required this.id,
    int? databaseId, // Optional, defaults to id if not provided
    required this.title,
    required this.description,
    required this.scheduledTime,
  }) : databaseId = databaseId ?? id; // Use id as database ID if not specified

  /// Create a copy with updated notification ID (for snooze)
  AlarmData withSnoozeId(int newNotificationId, DateTime newTime) {
    return AlarmData(
      id: newNotificationId,
      databaseId: databaseId, // Keep original database ID
      title: title,
      description: description,
      scheduledTime: newTime,
    );
  }
}

/// 🔐 Permission check result with detailed status
class PermissionCheckResult {
  final bool isReady;
  final List<String> missingPermissions;
  final int score; // 0-100
  final Map<String, bool> status;

  PermissionCheckResult({
    required this.isReady,
    required this.missingPermissions,
    required this.score,
    required this.status,
  });

  /// Get user-friendly message about missing permissions
  String get message {
    if (isReady) {
      return 'All permissions granted ✅';
    }
    return 'Missing: ${missingPermissions.join(", ")}';
  }

  /// Get emoji status indicator
  String get statusEmoji {
    if (score >= 100) return '🏆';
    if (score >= 80) return '✅';
    if (score >= 60) return '⚠️';
    return '❌';
  }
}
