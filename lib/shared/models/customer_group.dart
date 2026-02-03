import 'package:flutter/material.dart';

class CustomerGroup {
  final int? id;
  final String name;
  final int colorValue;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  const CustomerGroup({
    this.id,
    required this.name,
    required this.colorValue,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });

  /// Get the Color object from stored color value
  Color get color => Color(colorValue);

  factory CustomerGroup.fromMap(Map<String, dynamic> map) {
    return CustomerGroup(
      id: map['id'] as int?,
      name: map['name'] as String,
      colorValue: map['color_value'] as int,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isActive: (map['is_active'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color_value': colorValue,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_active': isActive ? 1 : 0,
    };
  }

  CustomerGroup copyWith({
    int? id,
    String? name,
    int? colorValue,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return CustomerGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  String toString() {
    return 'CustomerGroup(id: $id, name: $name, color: $colorValue)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomerGroup && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Predefined group colors for easy selection
class GroupColors {
  static const List<int> presetColors = [
    0xFFE53935, // Red
    0xFFD81B60, // Pink
    0xFF8E24AA, // Purple
    0xFF5E35B1, // Deep Purple
    0xFF3949AB, // Indigo
    0xFF1E88E5, // Blue
    0xFF039BE5, // Light Blue
    0xFF00ACC1, // Cyan
    0xFF00897B, // Teal
    0xFF43A047, // Green
    0xFF7CB342, // Light Green
    0xFFC0CA33, // Lime
    0xFFFDD835, // Yellow
    0xFFFFB300, // Amber
    0xFFFB8C00, // Orange
    0xFFF4511E, // Deep Orange
    0xFF6D4C41, // Brown
    0xFF757575, // Grey
    0xFF546E7A, // Blue Grey
  ];

  static Color getColor(int index) {
    return Color(presetColors[index % presetColors.length]);
  }
}
