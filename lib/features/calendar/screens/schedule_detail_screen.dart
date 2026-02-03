import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/alarm_service.dart';

/// Professional Schedule/Reminder Detail Screen
/// Similar to the reference design with date, time, and confirmation
class ScheduleDetailScreen extends StatefulWidget {
  final String? eventId;
  final String? title;
  final DateTime? scheduledDateTime;
  final String? description;
  final bool isEditing;

  const ScheduleDetailScreen({
    super.key,
    this.eventId,
    this.title,
    this.scheduledDateTime,
    this.description,
    this.isEditing = false,
  });

  @override
  State<ScheduleDetailScreen> createState() => _ScheduleDetailScreenState();
}

class _ScheduleDetailScreenState extends State<ScheduleDetailScreen> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  bool _confirmationRequired = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.scheduledDateTime ?? DateTime.now().add(const Duration(hours: 1));
    _selectedTime = widget.scheduledDateTime != null
        ? TimeOfDay.fromDateTime(widget.scheduledDateTime!)
        : TimeOfDay.now();
    _titleController = TextEditingController(text: widget.title ?? '');
    _descriptionController = TextEditingController(text: widget.description ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String get _dayName {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[_selectedDate.weekday - 1];
  }

  String get _monthName {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[_selectedDate.month - 1];
  }

  String get _formattedTime {
    final hour = _selectedTime.hourOfPeriod == 0 ? 12 : _selectedTime.hourOfPeriod;
    final minute = _selectedTime.minute.toString().padLeft(2, '0');
    final period = _selectedTime.period == DayPeriod.am ? 'am' : 'pm';
    return '$hour:$minute $period';
  }

  DateTime get _scheduledDateTime => DateTime(
    _selectedDate.year,
    _selectedDate.month,
    _selectedDate.day,
    _selectedTime.hour,
    _selectedTime.minute,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF6366F1), // Purple/Indigo background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Schedule details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _showOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          
          // Main Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Day Name
                    Center(
                      child: Text(
                        _dayName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Date Display with Tap to change
                    GestureDetector(
                      onTap: _selectDate,
                      child: Center(
                        child: Column(
                          children: [
                            Text(
                              _selectedDate.day.toString().padLeft(2, '0'),
                              style: const TextStyle(
                                fontSize: 72,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                                height: 1.0,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD93D), // Yellow badge
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _monthName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Divider
                    Container(
                      height: 1,
                      color: Colors.grey[200],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Title Input
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.event_note,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _titleController,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Add title',
                                  hintStyle: TextStyle(color: Colors.grey[400]),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _descriptionController,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 2,
                                decoration: InputDecoration(
                                  hintText: 'Add description',
                                  hintStyle: TextStyle(color: Colors.grey[400]),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Time Selection
                    GestureDetector(
                      onTap: _selectTime,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.access_time_rounded,
                              color: Colors.orange,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _formattedTime,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Confirmation Required Toggle
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.check_circle_outline,
                            color: Colors.green,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Confirmation required',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _confirmationRequired ? 'yes' : 'no',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: _confirmationRequired,
                          onChanged: (value) {
                            setState(() => _confirmationRequired = value);
                          },
                          activeThumbColor: Colors.green,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Sound Toggle
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.volume_up,
                            color: Colors.blue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Alarm with sound',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.notifications_active,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Scheduled For Summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, color: Colors.grey[600], size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Scheduled for',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  '${DateFormat('EEEE, d MMMM yyyy').format(_selectedDate)} at $_formattedTime',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Confirm Button
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _confirmSchedule,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD93D), // Yellow button
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black54,
                        ),
                      )
                    : const Text(
                        'Confirm',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate() async {
    // Clamp initialDate to ensure it's not before firstDate (prevents crash for past events)
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final clampedInitialDate = _selectedDate.isBefore(firstDate) ? firstDate : _selectedDate;
    
    final picked = await showDatePicker(
      context: context,
      initialDate: clampedInitialDate,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_active, color: Colors.blue),
              title: const Text('Preview Notification'),
              subtitle: const Text('See how your reminder will appear'),
              onTap: () {
                Navigator.pop(context);
                _testAlarm();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Reminder'),
              onTap: () {
                Navigator.pop(context);
                _deleteReminder();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testAlarm() async {
    final alarmService = AlarmService.instance;
    await alarmService.initialize();
    
    final taskTitle = _titleController.text.trim().isNotEmpty 
        ? _titleController.text.trim() 
        : 'Reminder';
    final taskDescription = _descriptionController.text.trim().isNotEmpty
        ? _descriptionController.text.trim()
        : 'Your scheduled task';
        
    await alarmService.showImmediateNotification(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: taskTitle,
      description: taskDescription,
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification sent! Check your notifications.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _confirmSchedule() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a title for your reminder'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if scheduled time is in the future
    final scheduledDT = _scheduledDateTime;
    if (scheduledDT.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a future date and time'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final alarmService = AlarmService.instance;
      await alarmService.initialize();

      // Check mounted before using context after await
      if (!mounted) {
        setState(() => _isLoading = false);
        return;
      }

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
            ),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      // Generate a safe 32-bit alarm ID
      final alarmId = widget.eventId != null 
          ? int.tryParse(widget.eventId!) ?? (DateTime.now().millisecondsSinceEpoch % 100000)
          : (DateTime.now().millisecondsSinceEpoch % 100000);

      final taskTitle = _titleController.text.trim();
      final taskDescription = _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : 'Scheduled reminder';

      final success = await alarmService.scheduleAlarm(
        id: alarmId,
        title: taskTitle,
        description: taskDescription,
        scheduledDateTime: scheduledDT,
        playSound: true,
        vibrate: true,
        fullScreenIntent: true,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Alarm set for ${DateFormat('MMM d, h:mm a').format(scheduledDT)}',
              ),
              backgroundColor: Colors.green,
            ),
          );
          
          Navigator.pop(context, {
            'id': alarmId.toString(),
            'title': taskTitle,
            'description': taskDescription,
            'scheduledDateTime': scheduledDT,
            'hasAlarm': true,
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to schedule alarm. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
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
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _deleteReminder() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reminder?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Capture navigator before async operation
              final navigator = Navigator.of(context);
              
              if (widget.eventId != null) {
                final alarmService = AlarmService.instance;
                await alarmService.cancelAlarm(
                  int.tryParse(widget.eventId!) ?? 0,
                );
              }
              if (mounted) {
                navigator.pop(); // Close dialog
                navigator.pop({'deleted': true}); // Close screen
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
