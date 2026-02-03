class Customer {
  final int? id;
  final String name;
  final String phoneNumber;
  final String? alternatePhone;
  final String? address;
  final String? bookNo;
  final String? panNumber;
  final int? groupId; // Legacy - kept for backward compatibility
  final List<int> groupIds; // NEW: Multiple group support
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  const Customer({
    this.id,
    required this.name,
    required this.phoneNumber,
    this.alternatePhone,
    this.address,
    this.bookNo,
    this.panNumber,
    this.groupId,
    this.groupIds = const [],
    this.latitude,
    this.longitude,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });

  /// Check if customer has saved location
  bool get hasLocation => latitude != null && longitude != null;
  
  /// Check if customer belongs to any group
  bool get hasGroups => groupIds.isNotEmpty || groupId != null;

  /// Get all phone numbers as formatted string (e.g., "9842886668, 9361484462")
  String get allPhoneNumbers {
    if (alternatePhone != null && alternatePhone!.isNotEmpty) {
      return '$phoneNumber, $alternatePhone';
    }
    return phoneNumber;
  }

  /// Check if customer has multiple phone numbers
  bool get hasMultiplePhones => alternatePhone != null && alternatePhone!.isNotEmpty;

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as int?,
      name: map['name'] as String,
      phoneNumber: map['phone_number'] as String,
      alternatePhone: map['alternate_phone'] as String?,
      address: map['address'] as String?,
      bookNo: map['book_no'] as String?,
      panNumber: map['pan_number'] as String?,
      groupId: map['group_id'] as int?,
      groupIds: const [], // Loaded separately from junction table
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isActive: (map['is_active'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone_number': phoneNumber,
      'alternate_phone': alternatePhone,
      'address': address,
      'book_no': bookNo,
      'pan_number': panNumber,
      'group_id': groupId, // Keep for backward compatibility
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_active': isActive ? 1 : 0,
    };
  }

  Customer copyWith({
    int? id,
    String? name,
    String? phoneNumber,
    String? alternatePhone,
    String? address,
    String? bookNo,
    String? panNumber,
    int? groupId,
    List<int>? groupIds,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      alternatePhone: alternatePhone ?? this.alternatePhone,
      address: address ?? this.address,
      bookNo: bookNo ?? this.bookNo,
      panNumber: panNumber ?? this.panNumber,
      groupId: groupId ?? this.groupId,
      groupIds: groupIds ?? this.groupIds,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  String toString() {
    return 'Customer(id: $id, name: $name, phoneNumber: $phoneNumber)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Customer && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}