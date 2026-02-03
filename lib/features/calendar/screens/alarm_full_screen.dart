import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../../core/services/alarm_service.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/services/database_service.dart';
import '../../../main.dart' show globalAuthProvider; // For PIN requirement
import 'calendar_screen.dart'; // For CalendarEventSync

// Channel to check if phone is locked
const _lockScreenChannel = MethodChannel('flu_app/lock_screen');

/// Full-Screen Alarm UI - Matches the design from reference images
/// Displays when alarm triggers - works on lock screen
class AlarmFullScreen extends StatefulWidget {
  final String title;
  final String? description;
  final DateTime scheduledTime;
  final int alarmId;  // Notification ID
  final int? databaseId;  // Original database ID (if different from alarmId)
  final VoidCallback? onDismiss;
  final VoidCallback? onSnooze;

  const AlarmFullScreen({
    super.key,
    required this.title,
    this.description,
    required this.scheduledTime,
    required this.alarmId,
    this.databaseId,  // Pass original DB ID for snoozed alarms
    this.onDismiss,
    this.onSnooze,
  });

  @override
  State<AlarmFullScreen> createState() => _AlarmFullScreenState();
}

class _AlarmFullScreenState extends State<AlarmFullScreen>
    with TickerProviderStateMixin {
  Timer? _timeTimer;
  String _currentTime = '';
  String _period = '';

  // Drag state for the circular button
  double _dragX = 0;
  bool _isDragging = false;
  final double _dragThreshold = 100;

  // Snooze options
  bool _showSnoozeOptions = false;
  int _selectedSnoozeMinutes = 5;
  
  /// The original database ID for database operations
  /// Uses widget.databaseId if provided, otherwise falls back to widget.alarmId
  int get _databaseId => widget.databaseId ?? widget.alarmId;

  // Animation controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Track if we're on lock screen
  bool _isOnLockScreen = false;

  @override
  void initState() {
    super.initState();

    // Keep screen awake and show on lock screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
      ),
    );

    _updateTime();
    _timeTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());

    // Pulse animation for the alarm icon
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Check if we're on lock screen
    _checkIfOnLockScreen();
  }
  
  /// Check if the phone is currently locked
  Future<void> _checkIfOnLockScreen() async {
    try {
      final isLocked = await _lockScreenChannel.invokeMethod<bool>('isDeviceLocked');
      if (mounted) {
        setState(() {
          _isOnLockScreen = isLocked ?? false;
        });
      }
      debugPrint('🔒 Lock screen alarm: isLocked = $_isOnLockScreen');
    } catch (e) {
      debugPrint('⚠️ Could not check lock state: $e');
      // Assume we might be on lock screen if we can't check
      _isOnLockScreen = true;
    }
  }

  void _updateTime() {
    final now = DateTime.now();
    final hour =
        now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    setState(() {
      _currentTime = '$hour:${now.minute.toString().padLeft(2, '0')}';
      _period = now.hour >= 12 ? 'PM' : 'AM';
    });
  }

  @override
  void dispose() {
    _timeTimer?.cancel();
    _pulseController.dispose();
    AlarmService.instance.stopAlarmSound();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _dismiss() async {
    // Stop sound and cancel alarm notification (use widget.alarmId for notification)
    AlarmService.instance.stopAlarmSound();
    AlarmService.instance.cancelAlarm(widget.alarmId);

    // DATABASE SYNC: Delete reminder from database (use _databaseId for database operations)
    try {
      await ReminderService.instance.dismissReminder(_databaseId);
    } catch (e) {
      debugPrint('⚠️ DB sync: $e');
    }

    // CALENDAR SYNC: Delete from SharedPreferences (use _databaseId)
    await CalendarEventSync.deleteEventByAlarmId(_databaseId);

    widget.onDismiss?.call();

    // LOCK SCREEN BEHAVIOR:
    // - Lock Screen: Close app completely, return to lock screen
    // - Phone Unlocked: Require PIN to enter app (security)
    if (mounted) {
      if (_isOnLockScreen) {
        // Close the activity completely - returns to lock screen
        debugPrint('🔒 On lock screen - closing app to return to lock screen');
        await SystemNavigator.pop();
      } else {
        // Phone is unlocked - require PIN to access app
        // This ensures security when alarm is dismissed
        debugPrint('🔓 Phone unlocked - requiring PIN to enter app');
        globalAuthProvider?.logout(); // Force re-authentication
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _snooze() async {
    AlarmService.instance.stopAlarmSound();

    final snoozeTime =
        DateTime.now().add(Duration(minutes: _selectedSnoozeMinutes));

    // DATABASE SYNC: Update reminder time in database with custom snooze duration
    // Use _databaseId to find the correct record regardless of snooze offset
    try {
      await DatabaseService.instance.updateReminderTime(_databaseId, snoozeTime);
      debugPrint('✅ Full Screen: Reminder $_databaseId snoozed to $snoozeTime in DB');
    } catch (e) {
      debugPrint('⚠️ DB sync: $e');
    }

    // CALENDAR SYNC: Update in SharedPreferences (use _databaseId)
    await CalendarEventSync.updateEventTimeByAlarmId(
        _databaseId, snoozeTime);

    // Schedule new alarm notification for snooze time
    // Use _databaseId + 1000 to create consistent snooze offset pattern
    await AlarmService.instance.scheduleAlarm(
      id: _databaseId + 1000,
      databaseId: _databaseId,  // Keep original database ID for next snooze/dismiss
      title: widget.title,
      description: widget.description ?? '',
      scheduledDateTime: snoozeTime,
      playSound: true,
      vibrate: true,
      fullScreenIntent: true,
    );

    debugPrint('✅ Alarm rescheduled for $_selectedSnoozeMinutes minutes later: $snoozeTime');

    widget.onSnooze?.call();

    // LOCK SCREEN BEHAVIOR:
    // - Lock Screen: Close app completely, return to lock screen  
    // - Phone Unlocked: Require PIN to enter app (security)
    if (mounted) {
      if (_isOnLockScreen) {
        // Close the activity completely - returns to lock screen
        debugPrint('🔒 On lock screen - closing app after snooze to return to lock screen');
        await SystemNavigator.pop();
      } else {
        // Phone is unlocked - require PIN to access app
        debugPrint('🔓 Phone unlocked - requiring PIN to enter app');
        globalAuthProvider?.logout(); // Force re-authentication
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _dragX += details.delta.dx;
      _dragX = _dragX.clamp(-_dragThreshold - 50, _dragThreshold + 50);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_dragX < -_dragThreshold) {
      // Dragged left - Snooze
      setState(() => _showSnoozeOptions = true);
    } else if (_dragX > _dragThreshold) {
      // Dragged right - Dismiss
      _dismiss();
    }

    setState(() {
      _dragX = 0;
      _isDragging = false;
    });
  }

  String _getDayName(DateTime date) {
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

  String _formatScheduledTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'pm' : 'am';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    // Get text scale factor to handle system font size changes
    final textScale = MediaQuery.textScalerOf(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                  MediaQuery.of(context).padding.top - 
                  MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.05),

                // Time display (minimized)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _currentTime,
                      style: TextStyle(
                        fontSize: 48 / textScale.scale(1),
                        fontWeight: FontWeight.w300,
                        color: Colors.white54,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _period,
                      style: TextStyle(
                        fontSize: 20 / textScale.scale(1),
                        fontWeight: FontWeight.w300,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Alarm label (smaller)
                Text(
                  'Alarm',
                  style: TextStyle(
                    fontSize: 14 / textScale.scale(1),
                    fontWeight: FontWeight.w400,
                    color: Colors.white38,
                  ),
                ),

                SizedBox(height: MediaQuery.of(context).size.height * 0.05),

                // Schedule Details Card - TASK MAXIMIZED
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pulsing alarm icon at top
                      ScaleTransition(
                        scale: _pulseAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.alarm,
                            color: Colors.amber.shade800,
                            size: 40,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // TASK TITLE - MAXIMIZED (Largest element)
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 28 / textScale.scale(1),
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),

                      if (widget.description != null &&
                          widget.description!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          widget.description!,
                          style: TextStyle(
                            fontSize: 16 / textScale.scale(1),
                            color: Colors.grey.shade700,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Divider
                      Container(
                        height: 1,
                        color: Colors.grey.shade200,
                      ),

                      const SizedBox(height: 16),

                      // Date/Time info (minimized at bottom) - wrap to prevent overflow
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event, size: 16, color: Colors.grey.shade500),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${_getDayName(widget.scheduledTime)}, ${widget.scheduledTime.day} ${_getMonthName(widget.scheduledTime.month)}',
                                  style: TextStyle(
                                    fontSize: 14 / textScale.scale(1),
                                    color: Colors.grey.shade600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time,
                                  size: 16, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                _formatScheduledTime(widget.scheduledTime),
                                style: TextStyle(
                                  fontSize: 14 / textScale.scale(1),
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: MediaQuery.of(context).size.height * 0.05),

                // Snooze options popup
                if (_showSnoozeOptions) ...[
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Snooze for',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16 / textScale.scale(1),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: AlarmService.snoozeDurations.map((mins) {
                            final isSelected = _selectedSnoozeMinutes == mins;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _selectedSnoozeMinutes = mins);
                              },
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.transparent,
                                  border: Border.all(
                                    color:
                                        isSelected ? Colors.white : Colors.white30,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '$mins',
                                    style: TextStyle(
                                      color:
                                          isSelected ? Colors.black : Colors.white,
                                      fontSize: 16 / textScale.scale(1),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'minutes',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12 / textScale.scale(1),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () {
                                  setState(() => _showSnoozeOptions = false);
                                },
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 14 / textScale.scale(1),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _snooze,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                                child: Text(
                                  'Snooze',
                                  style: TextStyle(fontSize: 14 / textScale.scale(1)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.05),
                ],

                // Drag control area (when not showing snooze options)
                if (!_showSnoozeOptions) ...[
                  // Snooze and Dismiss icons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 60),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Snooze icon (left)
                        Opacity(
                          opacity: _dragX < -20 ? 1.0 : 0.5,
                          child: Text(
                            'zzz',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24 / textScale.scale(1),
                              fontWeight: FontWeight.w300,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        // Dismiss icon (right)
                        Opacity(
                          opacity: _dragX > 20 ? 1.0 : 0.5,
                          child: const Icon(
                            Icons.alarm_off,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Draggable alarm button
                  GestureDetector(
                    onHorizontalDragUpdate: _onDragUpdate,
                    onHorizontalDragEnd: _onDragEnd,
                    child: AnimatedContainer(
                      duration: _isDragging
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      transform: Matrix4.translationValues(_dragX, 0, 0),
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF1A1A1A),
                        ),
                        child: Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.alarm,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Instruction text for drag gesture
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      '← Drag left for snooze | Drag right to dismiss →',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11 / textScale.scale(1),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Show full screen alarm
void showAlarmFullScreen(
  BuildContext context, {
  required String title,
  String? description,
  required DateTime scheduledTime,
  required int alarmId,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => AlarmFullScreen(
        title: title,
        description: description,
        scheduledTime: scheduledTime,
        alarmId: alarmId,
      ),
    ),
  );
}
