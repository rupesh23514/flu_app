// ignore_for_file: unused_element
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decimal/decimal.dart';
import '../../../core/constants/app_colors.dart';
import 'package:provider/provider.dart';
import '../../loan_management/providers/loan_provider.dart';
import '../../customer_management/providers/customer_provider.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/models/customer.dart';
import '../../../core/services/alarm_service.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/services/database_service.dart';
import 'schedule_detail_screen.dart';

class CalendarEvent {
  final String id;
  final String title;
  final DateTime date;
  final TimeOfDay time;
  final DateTime createdAt;
  final bool hasAlarm;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.time,
    DateTime? createdAt,
    this.hasAlarm = true,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'timeHour': time.hour,
        'timeMinute': time.minute,
        'createdAt': createdAt.toIso8601String(),
        'hasAlarm': hasAlarm,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'],
        title: json['title'],
        date: DateTime.parse(json['date']),
        time: TimeOfDay(
          hour: json['timeHour'] ?? 9,
          minute: json['timeMinute'] ?? 0,
        ),
        createdAt: DateTime.parse(json['createdAt']),
        hasAlarm: json['hasAlarm'] ?? true,
      );

  DateTime get scheduledDateTime => DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

  /// Copy with updated scheduled time (for snooze)
  CalendarEvent copyWithTime(DateTime newDateTime) => CalendarEvent(
        id: id,
        title: title,
        date: DateTime(newDateTime.year, newDateTime.month, newDateTime.day),
        time: TimeOfDay(hour: newDateTime.hour, minute: newDateTime.minute),
        createdAt: createdAt,
        hasAlarm: hasAlarm,
      );
}

/// Static helper for calendar event sync from alarm screens
class CalendarEventSync {
  static const String _eventsKey = 'calendar_events';

  // Notifier to trigger calendar UI refresh after updates
  static final ValueNotifier<int> refreshNotifier = ValueNotifier<int>(0);

  /// Trigger a refresh of calendar UI
  static void _notifyRefresh() {
    refreshNotifier.value++;
  }

  /// Clean up past events from SharedPreferences and database to save storage space
  /// Removes events from previous days (keeps today and future events)
  static Future<int> cleanupPastEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      
      final eventsJson = prefs.getString(_eventsKey);
      int removedCount = 0;
      
      if (eventsJson != null) {
        final List<dynamic> decoded = jsonDecode(eventsJson);
        final events = decoded.map((e) => CalendarEvent.fromJson(e)).toList();
        
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        final originalCount = events.length;
        
        // Remove events from previous days
        final futureEvents = events.where((event) {
          final eventDate = DateTime(event.date.year, event.date.month, event.date.day);
          return !eventDate.isBefore(startOfToday);
        }).toList();
        
        removedCount = originalCount - futureEvents.length;
        if (removedCount > 0) {
          final cleanedJson = jsonEncode(futureEvents.map((e) => e.toJson()).toList());
          await prefs.setString(_eventsKey, cleanedJson);
          debugPrint('🧹 CalendarEventSync: Cleaned up $removedCount past events from SharedPreferences');
          _notifyRefresh();
        }
      }
      
      // Also clean up past reminders from database
      try {
        final dbRemovedCount = await DatabaseService.instance.cleanupPastReminders();
        if (dbRemovedCount > 0) {
          debugPrint('🧹 CalendarEventSync: Cleaned up $dbRemovedCount past reminders from database');
        }
        removedCount += dbRemovedCount;
      } catch (e) {
        debugPrint('⚠️ CalendarEventSync: Error cleaning up database: $e');
      }
      
      return removedCount;
    } catch (e) {
      debugPrint('⚠️ CalendarEventSync: Error cleaning up past events: $e');
      return 0;
    }
  }

  /// Delete event by alarm ID (called when dismiss from alarm)
  /// The alarmId parameter is the original event ID (millisecond timestamp)
  static Future<void> deleteEventByAlarmId(int alarmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // CRITICAL: Force reload to get fresh data from disk
      await prefs.reload();
      
      final eventsJson = prefs.getString(_eventsKey);
      if (eventsJson != null) {
        final List<dynamic> decoded = jsonDecode(eventsJson);
        final events = decoded.map((e) => CalendarEvent.fromJson(e)).toList();

        debugPrint('🔍 CalendarEventSync.deleteEventByAlarmId: Looking for alarmId=$alarmId in ${events.length} events');
        
        // Find and remove event with matching ID
        // Match by: original ID, string comparison, or safe ID calculation
        int removedCount = 0;
        events.removeWhere((e) {
          final eventId = int.tryParse(e.id) ?? 0;
          final safeEventId = eventId.abs() % 2147483647;
          final safeAlarmId = alarmId.abs() % 2147483647;
          // Match original ID directly, or by safe ID calculation for backwards compatibility
          final matches = eventId == alarmId || e.id == alarmId.toString() || safeEventId == safeAlarmId;
          if (matches) {
            debugPrint('✅ CalendarEventSync: Found matching event "${e.title}" (id: ${e.id})');
            removedCount++;
          }
          return matches;
        });

        // Save updated list
        final updatedJson = jsonEncode(events.map((e) => e.toJson()).toList());
        await prefs.setString(_eventsKey, updatedJson);
        debugPrint('✅ CalendarEventSync: Deleted $removedCount event(s) for alarm $alarmId, remaining: ${events.length}');

        // Notify UI to refresh
        _notifyRefresh();
      } else {
        debugPrint('⚠️ CalendarEventSync: No events found in SharedPreferences');
      }
    } catch (e) {
      debugPrint('⚠️ CalendarEventSync: Error deleting event: $e');
    }
  }

  /// Update event time by alarm ID (called when snooze from alarm)
  /// The alarmId parameter is the original event ID (millisecond timestamp)
  static Future<void> updateEventTimeByAlarmId(
      int alarmId, DateTime newTime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // CRITICAL: Force reload to get fresh data from disk
      await prefs.reload();
      
      final eventsJson = prefs.getString(_eventsKey);
      debugPrint('🔍 CalendarEventSync.updateEventTimeByAlarmId: Looking for alarmId=$alarmId, newTime=$newTime');
      debugPrint('🔍 CalendarEventSync: eventsJson has ${eventsJson?.length ?? 0} chars');
      
      if (eventsJson != null) {
        final List<dynamic> decoded = jsonDecode(eventsJson);
        final events = decoded.map((e) => CalendarEvent.fromJson(e)).toList();
        debugPrint('🔍 CalendarEventSync: Found ${events.length} events to search');

        // Find and update event with matching ID
        bool found = false;
        final safeAlarmId = alarmId.abs() % 2147483647;
        for (var i = 0; i < events.length; i++) {
          final eventIdStr = events[i].id;
          final eventId = int.tryParse(eventIdStr) ?? 0;
          final safeEventId = eventId.abs() % 2147483647;
          
          debugPrint('🔍 CalendarEventSync: Checking event[$i] id="$eventIdStr", eventId=$eventId vs alarmId=$alarmId');
          
          // Match by: original ID directly, string comparison, or safe ID calculation
          if (eventId == alarmId || eventIdStr == alarmId.toString() || safeEventId == safeAlarmId) {
            final oldTime = events[i].scheduledDateTime;
            events[i] = events[i].copyWithTime(newTime);
            debugPrint('✅ CalendarEventSync: MATCH FOUND! Updated event "${events[i].title}" from $oldTime to $newTime');
            found = true;
            break;
          }
        }
        
        if (!found) {
          debugPrint('⚠️ CalendarEventSync: No matching event found for alarmId=$alarmId');
        }

        // Save updated list
        final updatedJson = jsonEncode(events.map((e) => e.toJson()).toList());
        await prefs.setString(_eventsKey, updatedJson);

        // Notify UI to refresh
        _notifyRefresh();
      }
    } catch (e) {
      debugPrint('⚠️ CalendarEventSync: Error updating event: $e');
    }
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  // RouteObserver for detecting when CalendarScreen becomes visible
  // Used by MaterialApp to notify when returning from other screens
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with RouteAware {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  List<CalendarEvent> _events = [];
  final TextEditingController _eventController = TextEditingController();
  static const String _eventsKey = 'calendar_events';
  StreamSubscription? _reminderStreamSubscription;

  @override
  void initState() {
    super.initState();
    _loadEvents();

    // Listen to reminder stream for real-time UI updates
    _reminderStreamSubscription =
        ReminderService.instance.remindersStream.listen((_) {
      // Reload events when reminders change
      _loadEvents();
    });

    // Listen to CalendarEventSync for SharedPreferences updates from alarm screens
    CalendarEventSync.refreshNotifier.addListener(_onCalendarEventSyncRefresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    final route = ModalRoute.of(context);
    if (route != null) {
      CalendarScreen.routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    // Called when returning to this screen from another route
    // Reload events to ensure calendar is up to date
    debugPrint('📅 CalendarScreen: Became visible, reloading events...');
    _loadEvents();
  }

  void _onCalendarEventSyncRefresh() {
    // Reload events when CalendarEventSync updates SharedPreferences
    debugPrint('📅 CalendarScreen: Received refreshNotifier callback!');
    _loadEvents();
  }

  @override
  void dispose() {
    CalendarScreen.routeObserver.unsubscribe(this);
    _eventController.dispose();
    _reminderStreamSubscription?.cancel();
    CalendarEventSync.refreshNotifier
        .removeListener(_onCalendarEventSyncRefresh);
    super.dispose();
  }

  Future<void> _loadEvents() async {
    debugPrint('📅 CalendarScreen: _loadEvents() called');
    
    // CRITICAL: Force reload SharedPreferences to get fresh data
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force reload from disk
    
    final eventsJson = prefs.getString(_eventsKey);
    debugPrint('📅 CalendarScreen: eventsJson = ${eventsJson?.substring(0, eventsJson.length > 50 ? 50 : eventsJson.length) ?? "null"}...');
    
    if (eventsJson != null && eventsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(eventsJson);
        debugPrint('📅 CalendarScreen: Loaded ${decoded.length} events from SharedPreferences');
        
        // Parse all events
        List<CalendarEvent> allEvents = decoded.map((e) => CalendarEvent.fromJson(e)).toList();
        
        // Clean up past events (events from previous days) to save storage space
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        final originalCount = allEvents.length;
        
        // Keep only future events and today's events (even if time passed, user may want to see today's)
        allEvents = allEvents.where((event) {
          final eventDate = DateTime(event.date.year, event.date.month, event.date.day);
          return !eventDate.isBefore(startOfToday); // Keep today and future
        }).toList();
        
        final removedCount = originalCount - allEvents.length;
        if (removedCount > 0) {
          debugPrint('🧹 CalendarScreen: Cleaned up $removedCount past events');
          // Save cleaned up list back to SharedPreferences
          final cleanedJson = jsonEncode(allEvents.map((e) => e.toJson()).toList());
          await prefs.setString(_eventsKey, cleanedJson);
        }
        
        if (mounted) {
          setState(() {
            _events = allEvents;
          });
        }
      } catch (e) {
        debugPrint('📅 CalendarScreen: Error parsing events JSON: $e');
        if (mounted) {
          setState(() {
            _events = [];
          });
        }
      }
    } else {
      // No events in SharedPreferences - clear the list
      debugPrint('📅 CalendarScreen: No events in SharedPreferences, clearing list');
      if (mounted) {
        setState(() {
          _events = [];
        });
      }
    }
  }

  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final eventsJson = jsonEncode(_events.map((e) => e.toJson()).toList());
    await prefs.setString(_eventsKey, eventsJson);
  }

  Future<void> _addEvent(String title, TimeOfDay time) async {
    final eventId = DateTime.now().millisecondsSinceEpoch.toString();
    final event = CalendarEvent(
      id: eventId,
      title: title,
      date: _selectedDate,
      time: time,
      hasAlarm: true,
    );

    // Check if scheduled time is in the future
    final scheduledDateTime = event.scheduledDateTime;
    final now = DateTime.now();

    if (scheduledDateTime.isBefore(now) ||
        scheduledDateTime.isAtSameMomentAs(now)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '❌ Cannot set alarm for past time. Please select a future date/time.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _events.add(event);
    });
    await _saveEvents();

    // Schedule alarm notification using new AlarmService
    await _scheduleTaskAlarm(event);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✅ Alarm set for ${_formatTime(time)} on ${_formatDate(_selectedDate)}'),
          duration: const Duration(seconds: 3),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _scheduleTaskAlarm(CalendarEvent event) async {
    try {
      final alarmService = AlarmService.instance;
      await alarmService.initialize();

      // Check mounted before using context after await
      if (!mounted) return;

      // 🚀 PRO Permission Check - Opens settings dialog directly if needed
      final hasPermission = await alarmService.requestPermissionsWithDialog(context);
      
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⏰ Please enable permissions to set reminders',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'TRY AGAIN',
                textColor: Colors.white,
                onPressed: () {
                  _scheduleTaskAlarm(event);
                },
              ),
            ),
          );
        }
        return;
      }

      // Generate safe 32-bit alarm ID (same calculation used in cancelAlarm)
      final alarmId =
          int.tryParse(event.id) ?? DateTime.now().millisecondsSinceEpoch;
      final safeAlarmId =
          alarmId.abs() % 2147483647; // Keep within 32-bit range

      final success = await alarmService.scheduleAlarm(
        id: safeAlarmId,
        databaseId: alarmId,  // CRITICAL: Pass original event ID for snooze/dismiss matching
        title: event.title,
        description: 'Scheduled reminder',
        scheduledDateTime: event.scheduledDateTime,
        playSound: true,
        vibrate: true,
        fullScreenIntent: true,
      );

      if (success && mounted) {
        debugPrint(
            '✅ Alarm scheduled for: ${event.title} at ${event.scheduledDateTime}');

        // Show confirmation snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '⏰ Reminder set for ${_formatDateTime(event.scheduledDateTime)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else if (!success && mounted) {
        debugPrint('❌ Failed to schedule alarm for: ${event.title}');
        // Check if the time is in the past
        if (event.scheduledDateTime.isBefore(DateTime.now())) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Cannot set reminder for past time.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          // Re-check permissions and show dialog if needed
          final hasPermission = await alarmService.requestPermissionsWithDialog(context);
          if (!hasPermission && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('⚠️ Enable permissions to set reminders'),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'RETRY',
                  textColor: Colors.white,
                  onPressed: () => _scheduleTaskAlarm(event),
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error scheduling alarm: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day/$month at $hour:$minute $period';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  void _deleteEvent(String id) async {
    // Cancel the alarm using the SAME safe ID calculation used during scheduling
    try {
      final alarmService = AlarmService.instance;
      final alarmId = int.tryParse(id) ?? 0;
      final safeAlarmId =
          alarmId.abs() % 2147483647; // Same calculation as scheduleAlarm
      await alarmService.cancelAlarm(safeAlarmId);
    } catch (e) {
      debugPrint('Error cancelling alarm: $e');
    }

    setState(() {
      _events.removeWhere((e) => e.id == id);
    });
    _saveEvents();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Check if any loan has a weekly payment due on this date
  bool _hasPaymentsDue(DateTime date) {
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    return loanProvider.loans.any((loan) {
      if (loan.status == LoanStatus.closed ||
          loan.status == LoanStatus.completed) {
        return false;
      }
      // Check all weekly due dates for this loan
      final weeklyDueDates = loanProvider.getWeeklyDueDates(loan);
      return weeklyDueDates.any((dueDate) => _isSameDay(dueDate, date));
    });
  }

  /// Check if any loan has an OVERDUE payment on this date (past due date not fully paid)
  bool _hasOverduePayments(DateTime date) {
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    final now = DateTime.now();

    // Only check if date is in the past
    if (date.isAfter(now)) return false;

    return loanProvider.loans.any((loan) {
      // Skip closed/completed loans
      if (loan.status == LoanStatus.closed ||
          loan.status == LoanStatus.completed) {
        return false;
      }

      // Skip if loan is fully paid (remaining amount is 0)
      if (loan.remainingAmount <= Decimal.zero) {
        return false;
      }

      // Check if this date was a due date
      final weeklyDueDates = loanProvider.getWeeklyDueDates(loan);
      final isDueDate =
          weeklyDueDates.any((dueDate) => _isSameDay(dueDate, date));

      if (!isDueDate) return false;

      // Calculate expected payment count up to this date
      final weekNumber =
          weeklyDueDates.indexWhere((d) => _isSameDay(d, date)) + 1;
      final expectedPayments = weekNumber;
      final actualPayments = loan.payments
          .where((p) =>
              p.paymentDate.isBefore(date.add(const Duration(days: 1))) ||
              _isSameDay(p.paymentDate, date))
          .length;

      // If we have enough payments up to this date, it's not overdue for this date
      if (actualPayments >= expectedPayments) {
        return false;
      }

      // It's overdue only if loan status is overdue
      return loan.status == LoanStatus.overdue;
    });
  }

  /// Check if payment was collected on this date
  bool _hasPaymentCollected(DateTime date) {
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    return loanProvider.loans.any((loan) {
      final payments = loan.payments;
      return payments.any((payment) =>
          _isSameDay(payment.paymentDate, date) && payment.isActive);
    });
  }

  /// Get loans that have a weekly payment due on this date
  List<Loan> _getLoansWithPaymentDue(DateTime date) {
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    return loanProvider.loans.where((loan) {
      if (loan.status == LoanStatus.closed ||
          loan.status == LoanStatus.completed) {
        return false;
      }
      final weeklyDueDates = loanProvider.getWeeklyDueDates(loan);
      return weeklyDueDates.any((dueDate) => _isSameDay(dueDate, date));
    }).toList();
  }

  bool _hasEvents(DateTime date) {
    return _events.any((event) => _isSameDay(event.date, date));
  }

  List<CalendarEvent> _getEventsForDate(DateTime date) {
    return _events.where((event) => _isSameDay(event.date, date)).toList();
  }

  String _formatDate(DateTime date) {
    final months = [
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
    return '${date.day} ${months[date.month - 1]}, ${date.year}';
  }

  String _getMonthName(int month) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
  }

  void _showMonthYearPicker() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _focusedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Select Month and Year',
      fieldLabelText: 'Month/Year',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.primary,
                ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() {
        _focusedMonth = DateTime(date.year, date.month, 1);
        // Clamp day to valid range for the selected month to prevent overflow
        final today = DateTime.now().day;
        final lastDayOfMonth = DateTime(date.year, date.month + 1, 0).day;
        final safeDay = today.clamp(1, lastDayOfMonth);
        _selectedDate = DateTime(date.year, date.month, safeDay);
      });
    }
  }

  void _refreshData() {
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    final customerProvider =
        Provider.of<CustomerProvider>(context, listen: false);
    loanProvider.loadLoans();
    customerProvider.loadCustomers();
    _loadEvents();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calendar refreshed'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _showAddEventDialog() {
    _eventController.clear();
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add Task for ${_formatDate(_selectedDate)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _eventController,
                autofocus: true,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Task Title',
                  hintText: 'Enter task or reminder',
                  border: OutlineInputBorder(),
                  counterText: '',
                  prefixIcon: Icon(Icons.task_alt),
                ),
              ),
              const SizedBox(height: 16),
              // Time Picker
              InkWell(
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: selectedTime,
                    helpText: 'Select Alarm Time',
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: AppColors.primary,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (time != null) {
                    setDialogState(() {
                      selectedTime = time;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary),
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.primary.withValues(alpha: 0.05),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.alarm, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Alarm Time',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            _formatTime(selectedTime),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Icon(Icons.edit,
                          color: AppColors.primary, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.notifications_active,
                      size: 16, color: AppColors.success),
                  SizedBox(width: 4),
                  Text(
                    'You will be reminded with alarm',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (_eventController.text.trim().isNotEmpty) {
                  _addEvent(_eventController.text.trim(), selectedTime);
                  _eventController.clear();
                  Navigator.pop(dialogContext);
                }
              },
              icon: const Icon(Icons.alarm_add, size: 18),
              label: const Text('Set Alarm'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Open professional schedule detail screen
  void _openScheduleDetailScreen({CalendarEvent? event}) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleDetailScreen(
          eventId: event?.id,
          title: event?.title ?? _eventController.text.trim(),
          scheduledDateTime: event?.scheduledDateTime ??
              DateTime(
                _selectedDate.year,
                _selectedDate.month,
                _selectedDate.day,
                TimeOfDay.now().hour,
                TimeOfDay.now().minute,
              ),
          description: '',
          isEditing: event != null,
        ),
      ),
    );

    if (result != null && result['deleted'] != true) {
      // Add the event from schedule detail screen
      final newEvent = CalendarEvent(
        id: result['id'],
        title: result['title'],
        date: (result['scheduledDateTime'] as DateTime),
        time: TimeOfDay.fromDateTime(result['scheduledDateTime'] as DateTime),
        hasAlarm: result['hasAlarm'] ?? true,
      );

      // Remove existing event if editing and cancel its alarm
      if (event != null) {
        // Cancel the old alarm before removing the event
        try {
          final alarmService = AlarmService.instance;
          final alarmId = int.tryParse(event.id) ?? 0;
          final safeAlarmId = alarmId.abs() % 2147483647;
          await alarmService.cancelAlarm(safeAlarmId);
          debugPrint('🔔 Cancelled old alarm $safeAlarmId for edited event');
        } catch (e) {
          debugPrint('Error cancelling old alarm: $e');
        }
        _events.removeWhere((e) => e.id == event.id);
      }

      setState(() {
        _events.add(newEvent);
      });
      await _saveEvents();

      // Schedule the new/updated alarm if hasAlarm is true
      if (newEvent.hasAlarm) {
        await _scheduleTaskAlarm(newEvent);
        debugPrint('🔔 Scheduled new alarm for event ${newEvent.id}');
      }
    } else if (result?['deleted'] == true && event != null) {
      // Event was deleted - cancel the alarm
      try {
        final alarmService = AlarmService.instance;
        final alarmId = int.tryParse(event.id) ?? 0;
        final safeAlarmId = alarmId.abs() % 2147483647;
        await alarmService.cancelAlarm(safeAlarmId);
        debugPrint('🔔 Cancelled alarm $safeAlarmId for deleted event');
      } catch (e) {
        debugPrint('Error cancelling alarm for deleted event: $e');
      }

      setState(() {
        _events.removeWhere((e) => e.id == event.id);
      });
      await _saveEvents();
    }
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final firstWeekday = firstDay.weekday % 7;

    final days = <Widget>[];

    // Empty cells for days before the first day of month
    for (int i = 0; i < firstWeekday; i++) {
      days.add(const SizedBox());
    }

    // Days of the month
    for (int day = 1; day <= lastDay.day; day++) {
      final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
      final isSelected = _isSameDay(date, _selectedDate);
      final isToday = _isSameDay(date, DateTime.now());
      final hasPayments = _hasPaymentsDue(date);
      final hasEvents = _hasEvents(date);
      final hasOverdue = _hasOverduePayments(date);
      final hasPaid = _hasPaymentCollected(date);

      days.add(
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = date;
            });
          },
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary
                  : isToday
                      ? AppColors.primaryLight.withValues(alpha: 0.3)
                      : hasOverdue && !hasPaid
                          ? AppColors.error.withValues(alpha: 0.15)
                          : hasPaid
                              ? AppColors.success.withValues(alpha: 0.1)
                              : null,
              borderRadius: BorderRadius.circular(12),
              border: isToday && !isSelected
                  ? Border.all(color: AppColors.primary, width: 2)
                  : hasOverdue && !hasPaid && !isSelected
                      ? Border.all(color: AppColors.error, width: 2)
                      : hasPayments && !isSelected
                          ? Border.all(
                              color: AppColors.warning.withValues(alpha: 0.5),
                              width: 1)
                          : hasEvents && !isSelected
                              ? Border.all(
                                  color: Colors.blue.withValues(alpha: 0.5),
                                  width: 1)
                              : null,
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    day.toString(),
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : hasOverdue && !hasPaid
                              ? AppColors.error
                              : isToday
                                  ? AppColors.primary
                                  : hasPaid
                                      ? AppColors.success
                                      : AppColors.textPrimary,
                      fontWeight: isSelected ||
                              isToday ||
                              hasPayments ||
                              hasEvents ||
                              hasOverdue ||
                              hasPaid
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 16,
                    ),
                  ),
                ),
                // Overdue indicator (red dot - top right)
                if (hasOverdue && !hasPaid)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.priority_high,
                        size: 6,
                        color: Colors.white,
                      ),
                    ),
                  ),
                // Payment collected indicator (green checkmark - top left)
                if (hasPaid)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                // Payment due indicator (orange dot - bottom right)
                if (hasPayments && !hasPaid)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                // Event indicator (blue dot)
                if (hasEvents)
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: days,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to LoanProvider changes so calendar updates when loans change
    return Consumer<LoanProvider>(
      builder: (context, loanProvider, _) {
        final customerProvider =
            Provider.of<CustomerProvider>(context, listen: false);
        final dayEvents = _getEventsForDate(_selectedDate);
        // Get loans with weekly payment due on selected date
        final dueLoans = _getLoansWithPaymentDue(_selectedDate);

        return Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: _showMonthYearPicker,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_getMonthName(_focusedMonth.month)} ${_focusedMonth.year}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refreshData,
                tooltip: 'Refresh Calendar',
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _showAddEventDialog,
            backgroundColor: AppColors.primary,
            child: const Icon(Icons.add, color: Colors.white),
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Month navigation
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () {
                          setState(() {
                            _focusedMonth = DateTime(
                              _focusedMonth.year,
                              _focusedMonth.month - 1,
                              1,
                            );
                          });
                        },
                      ),
                      Text(
                        '${_getMonthName(_focusedMonth.month)} ${_focusedMonth.year}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          setState(() {
                            _focusedMonth = DateTime(
                              _focusedMonth.year,
                              _focusedMonth.month + 1,
                              1,
                            );
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Weekday headers
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('Sun',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Mon',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Tue',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Wed',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Thu',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Fri',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Sat',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Calendar grid
                  _buildCalendarGrid(),
                  const SizedBox(height: 24),
                  // Selected date info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDate(_selectedDate),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          if (dayEvents.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${dayEvents.length} task${dayEvents.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: dueLoans.isNotEmpty
                                  ? AppColors.warning.withValues(alpha: 0.2)
                                  : AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${dueLoans.length} due',
                              style: TextStyle(
                                color: dueLoans.isNotEmpty
                                    ? AppColors.warning
                                    : AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Tasks/Events for selected date
                  if (dayEvents.isNotEmpty) ...[
                    const Text(
                      'Tasks & Reminders',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...dayEvents.map((event) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.alarm,
                                  color: Colors.blue, size: 20),
                            ),
                            title: Text(
                              event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Row(
                              children: [
                                const Icon(Icons.access_time,
                                    size: 14, color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  _formatTime(event.time),
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (event.hasAlarm) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.notifications_active,
                                      size: 14, color: AppColors.success),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Alarm set',
                                    style: TextStyle(
                                        fontSize: 11, color: AppColors.success),
                                  ),
                                ],
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppColors.error),
                              onPressed: () => _deleteEvent(event.id),
                            ),
                          ),
                        )),
                    const SizedBox(height: 16),
                  ],

                  // Due loans section
                  if (dueLoans.isNotEmpty) ...[
                    const Text(
                      'Due Payments',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height:
                          110, // Fixed height that accommodates content without overflow
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: dueLoans.length,
                        itemBuilder: (context, index) {
                          final loan = dueLoans[index];
                          if (customerProvider.customers.isEmpty) {
                            return const SizedBox();
                          }
                          final customer =
                              customerProvider.customers.firstWhere(
                            (c) => c.id == loan.customerId,
                            orElse: () => Customer(
                              id: 0,
                              name: 'Unknown',
                              phoneNumber: '',
                              address: '',
                              createdAt: DateTime.now(),
                              updatedAt: DateTime.now(),
                            ),
                          );
                          // Calculate weekly EMI (Principal / 10)
                          final weeklyEmi = loan.principal.toDouble() / 10;
                          final isOverdue = loan.status == LoanStatus.overdue;

                          return Container(
                            width: 130,
                            margin: const EdgeInsets.only(right: 12),
                            child: Card(
                              margin: EdgeInsets.zero,
                              color: isOverdue
                                  ? AppColors.error.withValues(alpha: 0.1)
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Customer name row
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            customer.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isOverdue)
                                          const Icon(Icons.warning,
                                              color: AppColors.error, size: 14),
                                      ],
                                    ),
                                    // Amount
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        CurrencyFormatter.format(weeklyEmi),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isOverdue
                                              ? AppColors.error
                                              : AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    // Label
                                    Text(
                                      isOverdue ? 'Overdue' : 'Weekly EMI',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isOverdue
                                            ? AppColors.error
                                            : AppColors.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  // Empty state
                  if (dayEvents.isEmpty && dueLoans.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.event_available,
                              size: 48,
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No tasks or payments due',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _showAddEventDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Add a task'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
