import 'package:decimal/decimal.dart';

enum PaymentType {
  fullPayment,
  partialPayment,
  interestOnly,
  penaltyPayment,
}

enum PaymentMethod {
  cash,
  upi,
  bank,
  other,
}

class Payment {
  final int? id;
  final int loanId;
  final int customerId;
  final Decimal amount;
  final DateTime paymentDate;
  final PaymentType paymentType;
  final PaymentMethod paymentMethod;
  final String? notes;
  final String? receiptNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  const Payment({
    this.id,
    required this.loanId,
    required this.customerId,
    required this.amount,
    required this.paymentDate,
    this.paymentType = PaymentType.partialPayment,
    this.paymentMethod = PaymentMethod.cash,
    this.notes,
    this.receiptNumber,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });

  // Getter alias for compatibility
  DateTime get date => paymentDate;

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'] as int?,
      loanId: map['loan_id'] as int,
      customerId: map['customer_id'] as int,
      amount: Decimal.parse(map['amount'] as String),
      paymentDate: DateTime.parse(map['payment_date'] as String),
      paymentType: PaymentType.values[map['payment_type'] as int],
      paymentMethod: PaymentMethod.values[map['payment_method'] as int? ?? 0],
      notes: map['notes'] as String?,
      receiptNumber: map['receipt_number'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isActive: (map['is_active'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'loan_id': loanId,
      'customer_id': customerId,
      'amount': amount.toString(),
      'payment_date': paymentDate.toIso8601String(),
      'payment_type': paymentType.index,
      'payment_method': paymentMethod.index,
      'notes': notes,
      'receipt_number': receiptNumber,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_active': isActive ? 1 : 0,
    };
  }

  Payment copyWith({
    int? id,
    int? loanId,
    int? customerId,
    Decimal? amount,
    DateTime? paymentDate,
    PaymentType? paymentType,
    PaymentMethod? paymentMethod,
    String? notes,
    String? receiptNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return Payment(
      id: id ?? this.id,
      loanId: loanId ?? this.loanId,
      customerId: customerId ?? this.customerId,
      amount: amount ?? this.amount,
      paymentDate: paymentDate ?? this.paymentDate,
      paymentType: paymentType ?? this.paymentType,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  String toString() {
    return 'Payment(id: $id, loanId: $loanId, amount: $amount, paymentDate: $paymentDate)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Payment && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}