class CalendarEvent {
  final String id;
  final String title;
  final DateTime date;
  final String? description;
  final bool isCompleted;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    this.description,
    this.isCompleted = false,
  });

  CalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? date,
    String? description,
    bool? isCompleted,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'date': date.toIso8601String(),
      'description': description,
      'isCompleted': isCompleted,
    };
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'],
      title: json['title'],
      date: DateTime.parse(json['date']),
      description: json['description'],
      isCompleted: json['isCompleted'] ?? false,
    );
  }
}