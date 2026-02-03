enum ReminderType {
  paymentDue,
  loanMaturity,
  followUp,
  custom,
}

enum RecurrencePattern {
  once,
  daily,
  weekly,
  monthly,
}

class Reminder {
  final int? id;
  final int? loanId;
  final int? customerId;
  final int? notificationId; // For reliable notification tracking
  final ReminderType type;
  final String title;
  final String description;
  final DateTime scheduledDate;
  final RecurrencePattern recurrencePattern;
  final bool isActive;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? customerName; // For display purposes
  final String? customerPhone; // For contact purposes

  const Reminder({
    this.id,
    this.loanId,
    this.customerId,
    this.notificationId,
    required this.type,
    required this.title,
    required this.description,
    required this.scheduledDate,
    this.recurrencePattern = RecurrencePattern.once,
    this.isActive = true,
    this.isCompleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.customerName,
    this.customerPhone,
  });

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'] as int?,
      loanId: map['loan_id'] as int?,
      customerId: map['customer_id'] as int?,
      notificationId: map['notification_id'] as int?,
      type: ReminderType.values[map['type'] as int],
      title: map['title'] as String,
      description: map['description'] as String? ?? '',
      scheduledDate: DateTime.parse(map['scheduled_date'] as String),
      recurrencePattern:
          RecurrencePattern.values[map['recurrence_pattern'] as int? ?? 0],
      isActive: (map['is_active'] as int? ?? 1) == 1,
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (loanId != null) 'loan_id': loanId,
      if (customerId != null) 'customer_id': customerId,
      if (notificationId != null) 'notification_id': notificationId,
      'type': type.index,
      'title': title,
      'description': description,
      'scheduled_date': scheduledDate.toIso8601String(),
      'recurrence_pattern': recurrencePattern.index,
      'is_active': isActive ? 1 : 0,
      'is_completed': isCompleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Reminder copyWith({
    int? id,
    int? loanId,
    int? customerId,
    int? notificationId,
    ReminderType? type,
    String? title,
    String? description,
    DateTime? scheduledDate,
    RecurrencePattern? recurrencePattern,
    bool? isActive,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? customerName,
    String? customerPhone,
  }) {
    return Reminder(
      id: id ?? this.id,
      loanId: loanId ?? this.loanId,
      customerId: customerId ?? this.customerId,
      notificationId: notificationId ?? this.notificationId,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      recurrencePattern: recurrencePattern ?? this.recurrencePattern,
      isActive: isActive ?? this.isActive,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
    );
  }

  bool get isDue {
    return DateTime.now().isAfter(scheduledDate);
  }

  bool get isToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final reminderDate =
        DateTime(scheduledDate.year, scheduledDate.month, scheduledDate.day);
    return reminderDate == today;
  }

  bool get isUpcoming {
    final now = DateTime.now();
    return scheduledDate.isAfter(now) &&
        scheduledDate.isBefore(now.add(const Duration(days: 7)));
  }

  String get displayDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final reminderDate =
        DateTime(scheduledDate.year, scheduledDate.month, scheduledDate.day);

    if (reminderDate == today) {
      return 'Today ${scheduledDate.hour.toString().padLeft(2, '0')}:${scheduledDate.minute.toString().padLeft(2, '0')}';
    } else if (reminderDate == today.add(const Duration(days: 1))) {
      return 'Tomorrow ${scheduledDate.hour.toString().padLeft(2, '0')}:${scheduledDate.minute.toString().padLeft(2, '0')}';
    } else if (reminderDate.isBefore(today)) {
      return 'Overdue';
    } else {
      return '${scheduledDate.day}/${scheduledDate.month}/${scheduledDate.year} ${scheduledDate.hour.toString().padLeft(2, '0')}:${scheduledDate.minute.toString().padLeft(2, '0')}';
    }
  }

  String get typeDisplayName {
    switch (type) {
      case ReminderType.paymentDue:
        return 'Payment Due';
      case ReminderType.loanMaturity:
        return 'Loan Maturity';
      case ReminderType.followUp:
        return 'Follow Up';
      case ReminderType.custom:
        return 'Custom Reminder';
    }
  }

  String get recurrenceDisplayName {
    switch (recurrencePattern) {
      case RecurrencePattern.once:
        return 'One Time';
      case RecurrencePattern.daily:
        return 'Daily';
      case RecurrencePattern.weekly:
        return 'Weekly';
      case RecurrencePattern.monthly:
        return 'Monthly';
    }
  }

  @override
  String toString() {
    return 'Reminder(id: $id, title: $title, scheduledDate: $scheduledDate, type: $type, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Reminder && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
