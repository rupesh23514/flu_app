import 'package:decimal/decimal.dart';
import 'payment.dart';

enum InterestType {
  simple,
  compound,
}

enum InterestPeriod {
  daily,
  weekly,
  monthly,
}

enum LoanStatus {
  pending,
  active,
  completed,
  defaulted,
  cancelled,
  overdue,
  closed,
}

/// Loan type to differentiate weekly and monthly interest loans
enum LoanType {
  weekly,           // Regular weekly collection (no interest, principal/10 per week)
  monthlyInterest,  // Monthly interest loan (principal + monthly interest collection)
}

class Loan {
  final int? id;
  final int customerId;
  final Decimal principal;
  final String? bookNo;  // Book number for this loan
  final DateTime loanDate;
  final DateTime dueDate;
  final Decimal totalAmount;
  final Decimal totalPaid;
  final Decimal remainingAmount;
  final LoanStatus status;
  final DateTime? lastPaymentDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final String? notes;
  final List<Payment> payments;
  final Decimal? penaltyRate;
  final int tenure;
  final LoanType loanType;
  final Decimal? monthlyInterestAmount;  // Fixed monthly interest amount (manually entered)
  final Decimal? totalInterestCollected; // Total interest collected so far

  Loan({
    this.id,
    required this.customerId,
    required this.principal,
    this.bookNo,
    required this.loanDate,
    required this.dueDate,
    required this.totalAmount,
    Decimal? totalPaid,
    required this.remainingAmount,
    this.status = LoanStatus.pending,
    this.lastPaymentDate,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
    this.notes,
    this.payments = const [],
    this.penaltyRate,
    this.tenure = 10,
    this.loanType = LoanType.weekly,
    this.monthlyInterestAmount,
    this.totalInterestCollected,
  }) : totalPaid = totalPaid ?? Decimal.zero;

  // Getter aliases for compatibility
  Decimal get principalAmount => principal;
  Decimal get paidAmount => totalPaid;
  
  // Check if this is a monthly interest loan
  bool get isMonthlyInterest => loanType == LoanType.monthlyInterest;
  
  // Get the monthly interest for monthly interest loans
  Decimal get monthlyEMI => monthlyInterestAmount ?? Decimal.zero;
  
  // Get outstanding principal (for monthly interest loans, this is what's left to repay)
  Decimal get outstandingPrincipal => remainingAmount;

  factory Loan.fromJson(Map<String, dynamic> json) {
    return Loan(
      id: json['id'] as int?,
      customerId: json['customer_id'] as int,
      principal: Decimal.parse(json['principal_amount'].toString()),
      bookNo: json['book_no'] as String?,
      loanDate: DateTime.parse(json['loan_date']),
      dueDate: DateTime.parse(json['due_date']),
      totalAmount: Decimal.parse(json['total_amount'].toString()),
      totalPaid: Decimal.parse(json['paid_amount']?.toString() ?? '0'),
      remainingAmount: Decimal.parse(json['remaining_amount'].toString()),
      status: LoanStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => LoanStatus.pending,
      ),
      lastPaymentDate: json['last_payment_date'] != null
          ? DateTime.parse(json['last_payment_date'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      isActive: json['is_active'] == 1,
      notes: json['notes'],
      tenure: json['tenure'] ?? 10,
      loanType: LoanType.values.firstWhere(
        (e) => e.index == (json['loan_type'] ?? 0),
        orElse: () => LoanType.weekly,
      ),
      monthlyInterestAmount: json['monthly_interest_amount'] != null 
          ? Decimal.parse(json['monthly_interest_amount'].toString()) 
          : null,
      totalInterestCollected: json['total_interest_collected'] != null 
          ? Decimal.parse(json['total_interest_collected'].toString()) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'principal_amount': principal.toString(),
      'book_no': bookNo,
      'loan_date': loanDate.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'total_amount': totalAmount.toString(),
      'paid_amount': totalPaid.toString(),
      'remaining_amount': remainingAmount.toString(),
      'status': status.name,
      'last_payment_date': lastPaymentDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_active': isActive ? 1 : 0,
      'notes': notes,
      'tenure': tenure,
      'loan_type': loanType.index,
      'monthly_interest_amount': monthlyInterestAmount?.toString(),
      'total_interest_collected': totalInterestCollected?.toString(),
    };
  }

  // Add toMap/fromMap methods for database service compatibility
  Map<String, dynamic> toMap() => toJson();
  factory Loan.fromMap(Map<String, dynamic> map) => Loan.fromJson(map);

  Loan copyWith({
    int? id,
    int? customerId,
    Decimal? principal,
    String? bookNo,
    DateTime? loanDate,
    DateTime? dueDate,
    Decimal? totalAmount,
    Decimal? totalPaid,
    Decimal? remainingAmount,
    LoanStatus? status,
    DateTime? lastPaymentDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    String? notes,
    List<Payment>? payments,
    int? tenure,
    LoanType? loanType,
    Decimal? monthlyInterestAmount,
    Decimal? totalInterestCollected,
  }) {
    return Loan(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      principal: principal ?? this.principal,
      bookNo: bookNo ?? this.bookNo,
      loanDate: loanDate ?? this.loanDate,
      dueDate: dueDate ?? this.dueDate,
      totalAmount: totalAmount ?? this.totalAmount,
      totalPaid: totalPaid ?? this.totalPaid,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      status: status ?? this.status,
      lastPaymentDate: lastPaymentDate ?? this.lastPaymentDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      payments: payments ?? this.payments,
      tenure: tenure ?? this.tenure,
      loanType: loanType ?? this.loanType,
      monthlyInterestAmount: monthlyInterestAmount ?? this.monthlyInterestAmount,
      totalInterestCollected: totalInterestCollected ?? this.totalInterestCollected,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Loan &&
        other.id == id &&
        other.customerId == customerId &&
        other.principal == principal;
  }

  @override
  int get hashCode {
    return Object.hash(id, customerId, principal);
  }

  @override
  String toString() {
    return 'Loan(id: $id, customerId: $customerId, principal: $principal, status: $status, type: $loanType)';
  }
}