import 'package:flutter/material.dart';
import 'dart:async';
import '../../../core/services/alarm_service.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/services/database_service.dart';
import '../screens/calendar_screen.dart'; // For CalendarEventSync

/// Popup notification that slides down from top when phone is ON
/// Similar to iOS/Android native notification banner
class AlarmPopupNotification extends StatefulWidget {
  final AlarmData alarmData;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final VoidCallback onSnooze;

  const AlarmPopupNotification({
    super.key,
    required this.alarmData,
    required this.onTap,
    required this.onDismiss,
    required this.onSnooze,
  });

  @override
  State<AlarmPopupNotification> createState() => _AlarmPopupNotificationState();
}

class _AlarmPopupNotificationState extends State<AlarmPopupNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  Timer? _autoDismissTimer;

  /// The original database ID for database operations
  /// Uses AlarmData.databaseId which is properly set from the payload
  int get _databaseId => widget.alarmData.databaseId;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Start animation
    _controller.forward();

    // Auto dismiss after 30 seconds - only hides the popup, does NOT delete data
    // This is different from user-initiated dismiss which is destructive
    _autoDismissTimer = Timer(const Duration(seconds: 30), () {
      _autoDismissVisualOnly();
    });

    // Note: Sound is already playing from AlarmService.testAlarm() or scheduled notification
    // Don't play again here to avoid duplicate sounds
  }
  
  /// Auto-dismiss only hides the popup without deleting data
  /// This prevents unintentional data loss when user ignores the popup
  Future<void> _autoDismissVisualOnly() async {
    if (!mounted) return;
    
    // Only stop sound and hide popup - don't delete database records
    AlarmService.instance.stopAlarmSound();
    
    await _controller.reverse();
    if (mounted) {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    debugPrint('🔴 Popup DISMISS called with alarmId: ${widget.alarmData.id} (dbId: $_databaseId)');
    
    // EXACT SAME AS FULL-SCREEN ALARM:
    // 1. Stop sound
    AlarmService.instance.stopAlarmSound();
    
    // 2. Cancel alarm notification (use original alarmData.id)
    AlarmService.instance.cancelAlarm(widget.alarmData.id);

    // 3. DATABASE SYNC: Delete reminder from database (use _databaseId)
    try {
      await ReminderService.instance.dismissReminder(_databaseId);
      debugPrint('✅ Popup: Reminder $_databaseId dismissed from DB');
    } catch (e) {
      debugPrint('⚠️ Popup DB sync: $e');
    }

    // 4. CALENDAR SYNC: Delete from SharedPreferences (use _databaseId)
    debugPrint('🔴 Popup: Calling CalendarEventSync.deleteEventByAlarmId($_databaseId)');
    await CalendarEventSync.deleteEventByAlarmId(_databaseId);
    debugPrint('🔴 Popup: CalendarEventSync.deleteEventByAlarmId completed');

    // Check mounted before using controller (prevents crash if widget disposed during async ops)
    if (!mounted) return;
    
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  Future<void> _snooze() async {
    // EXACT SAME AS FULL-SCREEN ALARM:
    // 1. Stop sound
    AlarmService.instance.stopAlarmSound();

    // Snooze for 5 minutes (popup uses fixed 5 min, full-screen allows selection)
    const snoozeMins = 5;
    final snoozeTime = DateTime.now().add(const Duration(minutes: snoozeMins));

    // 2. DATABASE SYNC: Update reminder time in database (use _databaseId)
    try {
      await DatabaseService.instance.updateReminderTime(_databaseId, snoozeTime);
      debugPrint('✅ Popup: Reminder $_databaseId snoozed to $snoozeTime in DB');
    } catch (e) {
      debugPrint('⚠️ Popup DB sync: $e');
    }

    // 3. CALENDAR SYNC: Update in SharedPreferences (use _databaseId)
    await CalendarEventSync.updateEventTimeByAlarmId(
        _databaseId, snoozeTime);

    // 4. Schedule new alarm notification for snooze time (use _databaseId + 1000)
    await AlarmService.instance.scheduleAlarm(
      id: _databaseId + 1000,
      databaseId: _databaseId,  // Keep original database ID for next snooze/dismiss
      title: widget.alarmData.title,
      description: widget.alarmData.description,
      scheduledDateTime: snoozeTime,
      playSound: true,
      vibrate: true,
      fullScreenIntent: true,
    );

    debugPrint('✅ Popup: Alarm rescheduled for $snoozeMins minutes later: $snoozeTime');

    // Check mounted before using controller (prevents crash if widget disposed during async ops)
    if (!mounted) return;
    
    _controller.reverse().then((_) {
      widget.onSnooze();
    });
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _getDayName(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
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

  @override
  Widget build(BuildContext context) {
    final dt = widget.alarmData.scheduledTime;
    // Get text scale factor to handle system font size changes
    final textScale = MediaQuery.textScalerOf(context);

    return SlideTransition(
      position: _slideAnimation,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
            child: InkWell(
              onTap: () {
                AlarmService.instance.stopAlarmSound();
                widget.onTap();
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.amber.shade300,
                    width: 2,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row with icon and title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.alarm,
                              color: Colors.amber.shade800,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reminder',
                                  style: TextStyle(
                                    fontSize: 12 / textScale.scale(1),
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  widget.alarmData.title,
                                  style: TextStyle(
                                    fontSize: 16 / textScale.scale(1),
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // Close button
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: _dismiss,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Date and time info
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 14, color: Colors.grey.shade700),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${_getDayName(dt)}, ${dt.day} ${_getMonthName(dt.month)}',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12 / textScale.scale(1),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.access_time,
                                size: 14, color: Colors.grey.shade700),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _formatTime(dt),
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12 / textScale.scale(1),
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (widget.alarmData.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.alarmData.description,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12 / textScale.scale(1),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      const SizedBox(height: 10),

                      // Action buttons - Fixed size to prevent overflow
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: OutlinedButton.icon(
                                onPressed: _snooze,
                                icon: const Icon(Icons.snooze, size: 16),
                                label: Text(
                                  'Snooze',
                                  style: TextStyle(fontSize: 12 / textScale.scale(1)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.grey.shade700,
                                  side: BorderSide(color: Colors.grey.shade300),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: ElevatedButton.icon(
                                onPressed: _dismiss,
                                icon: const Icon(Icons.check, size: 16),
                                label: Text(
                                  'Dismiss',
                                  style: TextStyle(fontSize: 12 / textScale.scale(1)),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Overlay entry for showing popup notification
class AlarmPopupOverlay {
  static OverlayEntry? _currentEntry;
  static AlarmData? _currentAlarmData;

  /// Show popup notification overlay
  static void show(
    BuildContext context,
    AlarmData alarmData, {
    required VoidCallback onTapToOpenFullScreen,
    required VoidCallback onSnooze,
  }) {
    // Remove existing overlay if any
    hide();

    _currentAlarmData = alarmData;

    _currentEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: AlarmPopupNotification(
          alarmData: alarmData,
          onTap: () {
            hide();
            onTapToOpenFullScreen();
          },
          onDismiss: () {
            hide();
          },
          onSnooze: () {
            hide();
            onSnooze();
          },
        ),
      ),
    );

    Overlay.of(context).insert(_currentEntry!);
  }

  /// Hide the popup notification
  static void hide() {
    _currentEntry?.remove();
    _currentEntry = null;
    _currentAlarmData = null;
  }

  /// Check if popup is currently showing
  static bool get isShowing => _currentEntry != null;

  /// Get current alarm data
  static AlarmData? get currentAlarmData => _currentAlarmData;
}
