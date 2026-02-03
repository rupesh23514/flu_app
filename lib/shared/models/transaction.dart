import 'package:decimal/decimal.dart';

/// Transaction type for bank-style tracking
enum TransactionType {
  credit, // Money received (payment from borrower)
  debit, // Money given (loan disbursement)
}

/// Extended payment class with transaction tracking
class Transaction {
  final int? id;
  final int? loanId;
  final int customerId;
  final TransactionType type;
  final Decimal amount;
  final DateTime transactionDate;
  final String? description;
  final String? referenceNumber;
  final Decimal runningBalance;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  // For display
  final String? customerName;
  final String? loanInfo;

  const Transaction({
    this.id,
    this.loanId,
    required this.customerId,
    required this.type,
    required this.amount,
    required this.transactionDate,
    this.description,
    this.referenceNumber,
    required this.runningBalance,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
    this.customerName,
    this.loanInfo,
  });

  /// Check if this is a credit (money received)
  bool get isCredit => type == TransactionType.credit;

  /// Check if this is a debit (money given)
  bool get isDebit => type == TransactionType.debit;

  /// Get display amount with sign
  String get displayAmount {
    final sign = isCredit ? '+' : '-';
    return '$sign${amount.toString()}';
  }

  /// Get the transaction type label
  String get typeLabel => isCredit ? 'Credit' : 'Debit';

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as int?,
      loanId: map['loan_id'] as int?,
      customerId: map['customer_id'] as int,
      type: TransactionType.values[map['transaction_type'] as int? ?? 0],
      amount: Decimal.parse(map['amount'].toString()),
      transactionDate: DateTime.parse(map['transaction_date'] as String),
      description: map['description'] as String?,
      referenceNumber: map['reference_number'] as String?,
      runningBalance: Decimal.parse((map['running_balance'] ?? '0').toString()),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isActive: (map['is_active'] as int?) == 1,
      customerName: map['customer_name'] as String?,
      loanInfo: map['loan_info'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'loan_id': loanId,
      'customer_id': customerId,
      'customer_name': customerName,
      'transaction_type': type.index,
      'amount': amount.toString(),
      'transaction_date': transactionDate.toIso8601String(),
      'description': description,
      'reference_number': referenceNumber,
      'running_balance': runningBalance.toString(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_active': isActive ? 1 : 0,
    };
  }

  Transaction copyWith({
    int? id,
    int? loanId,
    int? customerId,
    TransactionType? type,
    Decimal? amount,
    DateTime? transactionDate,
    String? description,
    String? referenceNumber,
    Decimal? runningBalance,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    String? customerName,
    String? loanInfo,
  }) {
    return Transaction(
      id: id ?? this.id,
      loanId: loanId ?? this.loanId,
      customerId: customerId ?? this.customerId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      transactionDate: transactionDate ?? this.transactionDate,
      description: description ?? this.description,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      runningBalance: runningBalance ?? this.runningBalance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      customerName: customerName ?? this.customerName,
      loanInfo: loanInfo ?? this.loanInfo,
    );
  }

  @override
  String toString() {
    return 'Transaction(id: $id, type: $type, amount: $amount, date: $transactionDate)';
  }
}

/// Transaction summary for a period
class TransactionSummary {
  final Decimal totalCredits;
  final Decimal totalDebits;
  final Decimal netBalance;
  final int creditCount;
  final int debitCount;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  const TransactionSummary({
    required this.totalCredits,
    required this.totalDebits,
    required this.netBalance,
    required this.creditCount,
    required this.debitCount,
    this.periodStart,
    this.periodEnd,
  });

  factory TransactionSummary.empty() {
    return TransactionSummary(
      totalCredits: Decimal.zero,
      totalDebits: Decimal.zero,
      netBalance: Decimal.zero,
      creditCount: 0,
      debitCount: 0,
    );
  }

  factory TransactionSummary.fromTransactions(
    List<Transaction> transactions, {
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    Decimal credits = Decimal.zero;
    Decimal debits = Decimal.zero;
    int creditCount = 0;
    int debitCount = 0;

    for (final t in transactions) {
      if (t.isCredit) {
        credits += t.amount;
        creditCount++;
      } else {
        debits += t.amount;
        debitCount++;
      }
    }

    return TransactionSummary(
      totalCredits: credits,
      totalDebits: debits,
      netBalance: credits - debits,
      creditCount: creditCount,
      debitCount: debitCount,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }
}
