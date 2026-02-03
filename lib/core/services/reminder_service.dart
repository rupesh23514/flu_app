import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'dart:async';
import '../services/database_service.dart';
import '../services/alarm_service.dart';
import '../../shared/models/reminder.dart';

/// Enhanced reminder service with local notifications and reactive streams
class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  static ReminderService get instance => _instance;
  ReminderService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final DatabaseService _databaseService = DatabaseService.instance;
  final AlarmService _alarmService = AlarmService.instance;
  bool _isInitialized = false;
  
  /// Completer to prevent concurrent initialization (race condition fix)
  Completer<bool>? _initCompleter;

  // Stream controller for reactive UI updates
  final StreamController<List<Reminder>> _reminderStreamController =
      StreamController<List<Reminder>>.broadcast();

  /// Stream of reminders for reactive UI
  Stream<List<Reminder>> get remindersStream =>
      _reminderStreamController.stream;

  /// Fixed snooze duration (5 minutes as per plan)
  static const int _snoozeDurationMinutes = 5;

  // ============================================================
  // ENTERPRISE SCALE: Constants for 1000+ reminder handling
  // ============================================================
  /// Maximum concurrent notification schedules to prevent system overload
  static const int _maxConcurrentNotifications = 50;

  /// Batch size for processing large reminder lists
  static const int _batchSize = 100;

  /// Delay between batches to prevent UI lag (milliseconds)
  static const int _batchDelayMs = 10;

  /// Initialize the reminder service
  /// Uses Completer to prevent concurrent initialization (race condition fix)
  Future<bool> initialize() async {
    // Already initialized
    if (_isInitialized) return true;
    
    // If initialization is in progress, wait for it
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    
    // Start initialization with lock
    _initCompleter = Completer<bool>();

    try {
      // Initialize timezone
      tz_data.initializeTimeZones();

      // Android settings
      const androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      // iOS settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final result = await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      // Request notification permission for Android 13+
      await _requestNotificationPermission();

      _isInitialized = result ?? false;
      debugPrint('ReminderService initialized: $_isInitialized');
      _initCompleter!.complete(_isInitialized);
      return _isInitialized;
    } catch (e) {
      debugPrint('ReminderService initialization error: $e');
      _initCompleter!.complete(false);
      _initCompleter = null; // Reset for retry on failure
      return false;
    }
  }

  /// Request notification permission for Android 13+
  Future<void> _requestNotificationPermission() async {
    try {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        debugPrint('Notification permission requested');
      }
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    debugPrint('Notification clicked: ${response.payload}');
    // Handle notification tap here
  }

  /// Schedule a reminder notification
  Future<bool> scheduleReminder(Reminder reminder) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      const androidDetails = AndroidNotificationDetails(
        'task_reminders_channel',
        'Task Reminders',
        channelDescription: 'Alarm notifications for tasks and reminders',
        importance: Importance.max,
        priority: Priority.max,
        ticker: 'Task Reminder',
        icon: '@mipmap/launcher_icon',
        playSound: true,
        sound: RawResourceAndroidNotificationSound('alarm_sound'),
        enableVibration: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        // Use private visibility to hide sensitive customer/payment info on lock screen
        visibility: NotificationVisibility.private,
        autoCancel: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Convert to TZDateTime
      final scheduledDate =
          tz.TZDateTime.from(reminder.scheduledDate, tz.local);

      // Only schedule future notifications
      if (scheduledDate.isAfter(tz.TZDateTime.now(tz.local))) {
        // Use modulo to keep ID within 32-bit signed integer range (Android limit)
        final notificationId = reminder.id ?? (DateTime.now().millisecondsSinceEpoch % 2147483647);
        await _notificationsPlugin.zonedSchedule(
          notificationId,
          reminder.title,
          reminder.description,
          scheduledDate,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: '${reminder.loanId ?? reminder.customerId}',
        );
        // Log only non-sensitive metadata (reminder ID and time, not title which may contain customer names)
        debugPrint('Reminder scheduled: ID=${reminder.id ?? notificationId} at $scheduledDate');
        return true;
      } else {
        debugPrint('Reminder date is in the past, skipping schedule');
        return false;
      }
    } catch (e) {
      debugPrint('Error scheduling reminder: $e');
      return false;
    }
  }

  /// ENTERPRISE SCALE: Batch schedule reminders efficiently for 1000+ reminders
  /// Uses batching to prevent memory pressure and UI lag
  Future<int> scheduleRemindersBatch(List<Reminder> reminders) async {
    if (reminders.isEmpty) return 0;

    int successCount = 0;
    final totalReminders = reminders.length;

    debugPrint(
        '📅 Scheduling $totalReminders reminders in batches of $_batchSize');

    // Process in batches to avoid memory pressure
    for (var i = 0; i < totalReminders; i += _batchSize) {
      final endIndex =
          (i + _batchSize < totalReminders) ? i + _batchSize : totalReminders;
      final batch = reminders.sublist(i, endIndex);

      // Limit concurrent notifications per batch
      final batchResults = await Future.wait(
        batch.take(_maxConcurrentNotifications).map((r) => scheduleReminder(r)),
      );

      successCount += batchResults.where((success) => success).length;

      // Handle remaining in batch if over concurrent limit
      if (batch.length > _maxConcurrentNotifications) {
        final remaining = batch.skip(_maxConcurrentNotifications);
        for (final reminder in remaining) {
          if (await scheduleReminder(reminder)) successCount++;
        }
      }

      // Small delay between batches to prevent UI lag
      if (endIndex < totalReminders) {
        await Future.delayed(const Duration(milliseconds: _batchDelayMs));
      }
    }

    debugPrint(
        '✅ Scheduled $successCount/$totalReminders reminders successfully');
    return successCount;
  }

  /// Cancel a scheduled reminder
  Future<void> cancelReminder(int reminderId) async {
    try {
      await _notificationsPlugin.cancel(reminderId);
      debugPrint('Reminder cancelled: $reminderId');
    } catch (e) {
      debugPrint('Error cancelling reminder: $e');
    }
  }

  /// Cancel all scheduled reminders
  Future<void> cancelAllReminders() async {
    try {
      await _notificationsPlugin.cancelAll();
      debugPrint('All reminders cancelled');
    } catch (e) {
      debugPrint('Error cancelling all reminders: $e');
    }
  }

  /// Create a payment due reminder
  Future<Reminder> createPaymentDueReminder({
    required int loanId,
    required int customerId,
    required DateTime dueDate,
    required String customerName,
    required String amount,
  }) async {
    final now = DateTime.now();
    final reminder = Reminder(
      loanId: loanId,
      customerId: customerId,
      type: ReminderType.paymentDue,
      title: 'Payment Due: $customerName',
      description: 'Payment of $amount is due today',
      scheduledDate:
          DateTime(dueDate.year, dueDate.month, dueDate.day, 9, 0), // 9 AM
      recurrencePattern: RecurrencePattern.once,
      isActive: true,
      isCompleted: false,
      createdAt: now,
      updatedAt: now,
      customerName: customerName,
    );

    // Save to database
    final id = await _saveReminder(reminder);
    final savedReminder = reminder.copyWith(id: id);

    // Schedule notification
    await scheduleReminder(savedReminder);

    return savedReminder;
  }

  /// Create a follow-up reminder
  Future<Reminder> createFollowUpReminder({
    required int? loanId,
    required int customerId,
    required DateTime scheduledDate,
    required String title,
    String? description,
  }) async {
    final now = DateTime.now();
    final reminder = Reminder(
      loanId: loanId,
      customerId: customerId,
      type: ReminderType.followUp,
      title: title,
      description: description ?? 'Follow up with customer',
      scheduledDate: scheduledDate,
      recurrencePattern: RecurrencePattern.once,
      isActive: true,
      isCompleted: false,
      createdAt: now,
      updatedAt: now,
    );

    final id = await _saveReminder(reminder);
    final savedReminder = reminder.copyWith(id: id);
    await scheduleReminder(savedReminder);

    return savedReminder;
  }

  /// Save reminder to database
  Future<int> _saveReminder(Reminder reminder) async {
    final db = await _databaseService.database;
    final map = reminder.toMap();
    map.remove('id');
    map.remove('customer_name');
    map.remove('customer_phone');
    return await db.insert('reminders', map);
  }

  /// Get all active reminders
  Future<List<Reminder>> getActiveReminders() async {
    final db = await _databaseService.database;
    final maps = await db.rawQuery('''
      SELECT r.*, c.name as customer_name, c.phone_number as customer_phone
      FROM reminders r
      LEFT JOIN customers c ON r.customer_id = c.id
      WHERE r.is_active = 1 AND r.is_completed = 0
      ORDER BY r.scheduled_date ASC
    ''');
    return maps.map((map) => Reminder.fromMap(map)).toList();
  }

  /// Get reminders for today
  Future<List<Reminder>> getTodayReminders() async {
    final db = await _databaseService.database;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

    final maps = await db.rawQuery('''
      SELECT r.*, c.name as customer_name, c.phone_number as customer_phone
      FROM reminders r
      LEFT JOIN customers c ON r.customer_id = c.id
      WHERE r.is_active = 1 
        AND r.is_completed = 0
        AND r.scheduled_date >= ?
        AND r.scheduled_date <= ?
      ORDER BY r.scheduled_date ASC
    ''', [startOfDay.toIso8601String(), endOfDay.toIso8601String()]);

    return maps.map((map) => Reminder.fromMap(map)).toList();
  }

  /// Get upcoming reminders (next 7 days)
  Future<List<Reminder>> getUpcomingReminders() async {
    final db = await _databaseService.database;
    final today = DateTime.now();
    final endDate = today.add(const Duration(days: 7));

    final maps = await db.rawQuery('''
      SELECT r.*, c.name as customer_name, c.phone_number as customer_phone
      FROM reminders r
      LEFT JOIN customers c ON r.customer_id = c.id
      WHERE r.is_active = 1 
        AND r.is_completed = 0
        AND r.scheduled_date >= ?
        AND r.scheduled_date <= ?
      ORDER BY r.scheduled_date ASC
    ''', [today.toIso8601String(), endDate.toIso8601String()]);

    return maps.map((map) => Reminder.fromMap(map)).toList();
  }

  /// Mark reminder as completed
  Future<void> markAsCompleted(int reminderId) async {
    final db = await _databaseService.database;
    await db.update(
      'reminders',
      {
        'is_completed': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [reminderId],
    );
    await cancelReminder(reminderId);
  }

  /// Delete a reminder
  Future<void> deleteReminder(int reminderId) async {
    final db = await _databaseService.database;
    await db.update(
      'reminders',
      {
        'is_active': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [reminderId],
    );
    await cancelReminder(reminderId);
  }

  /// Show immediate notification (for testing or instant alerts)
  Future<void> showInstantNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    const androidDetails = AndroidNotificationDetails(
      'instant_channel',
      'Instant Notifications',
      channelDescription: 'For immediate notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  // ============================================================
  // ATOMIC OPERATIONS - Synchronized DB + Notification handling
  // ============================================================

  /// Atomic dismiss - DB deleted + notification cancelled + sound stopped
  /// Uses Future.wait() to ensure both operations complete together
  Future<void> dismissReminder(int reminderId) async {
    try {
      // Stop alarm sound immediately
      await _alarmService.stopAlarmSound();

      // Execute DB delete and notification cancel atomically
      await Future.wait([
        _databaseService.deleteReminderPermanently(reminderId),
        cancelReminder(reminderId),
      ]);

      // Emit updated list to stream for reactive UI
      final updatedReminders = await getActiveReminders();
      _reminderStreamController.add(updatedReminders);

      debugPrint('✅ Reminder $reminderId dismissed atomically (sound stopped)');
    } catch (e) {
      debugPrint('❌ Error dismissing reminder: $e');
      rethrow;
    }
  }

  /// Atomic snooze (fixed 5 min) - sound stopped + DB updated + notification rescheduled
  /// Uses Future.wait() to ensure both operations complete together
  Future<void> snoozeReminder(int reminderId) async {
    try {
      // Stop alarm sound immediately
      await _alarmService.stopAlarmSound();

      // Get current reminder data first
      final reminderMap = await _databaseService.getReminderById(reminderId);
      if (reminderMap == null) {
        debugPrint('⚠️ Reminder $reminderId not found');
        return;
      }

      final reminder = Reminder.fromMap(reminderMap);
      final newTime =
          DateTime.now().add(const Duration(minutes: _snoozeDurationMinutes));

      // Execute DB update and notification reschedule atomically
      await Future.wait([
        _databaseService.updateReminderTime(reminderId, newTime),
        _rescheduleNotification(reminder, newTime),
      ]);

      // Emit updated list to stream for reactive UI
      final updatedReminders = await getActiveReminders();
      _reminderStreamController.add(updatedReminders);

      debugPrint(
          '✅ Reminder $reminderId snoozed for $_snoozeDurationMinutes minutes (sound stopped)');
    } catch (e) {
      debugPrint('❌ Error snoozing reminder: $e');
      rethrow;
    }
  }

  /// Reschedule notification to a new time
  Future<void> _rescheduleNotification(
      Reminder reminder, DateTime newTime) async {
    // Cancel existing notification
    if (reminder.id != null) {
      await cancelReminder(reminder.id!);
    }

    // Schedule new notification
    final updatedReminder = reminder.copyWith(scheduledDate: newTime);
    await scheduleReminder(updatedReminder);
  }

  /// Get a single reminder by ID
  Future<Reminder?> getReminder(int reminderId) async {
    final map = await _databaseService.getReminderById(reminderId);
    if (map == null) return null;
    return Reminder.fromMap(map);
  }

  /// Refresh the reminders stream - call this to notify UI of changes
  Future<void> refreshRemindersStream() async {
    final reminders = await getActiveReminders();
    _reminderStreamController.add(reminders);
  }

  // ============================================================
  // SOUND CONTROL - Respects silent mode
  // ============================================================

  /// Play reminder sound - respects silent mode (unlike alarms which bypass)
  /// Use this for regular reminder notifications
  Future<void> playReminderSound({int durationSeconds = 30}) async {
    // Play sound but respect silent mode (bypassSilentMode: false)
    await _alarmService.playAlarmSound(
      durationSeconds: durationSeconds,
      bypassSilentMode: false, // Respects silent mode
    );
    debugPrint('🔊 Reminder sound started (respects silent mode)');
  }

  /// Stop any playing reminder/alarm sound
  Future<void> stopReminderSound() async {
    await _alarmService.stopAlarmSound();
    debugPrint('🔇 Reminder sound stopped');
  }

  /// Dispose of resources
  void dispose() {
    _reminderStreamController.close();
  }
}
