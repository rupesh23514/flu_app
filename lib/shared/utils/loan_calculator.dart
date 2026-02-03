import 'package:decimal/decimal.dart';
import 'dart:math' as math;

class LoanCalculator {
  /// Helper to safely convert arithmetic results to Decimal
  static Decimal _toDecimal(dynamic value) {
    return Decimal.parse(value.toString());
  }

  /// Calculate simple interest
  /// Formula: SI = (P * R * T) / 100
  static Decimal calculateSimpleInterest({
    required Decimal principal,
    required Decimal rate,
    required Decimal time,
  }) {
    return _toDecimal(principal.toDouble() * rate.toDouble() * time.toDouble() / 100);
  }

  /// Calculate compound interest
  /// Formula: CI = P(1 + R/100)^T - P
  static Decimal calculateCompoundInterest({
    required Decimal principal,
    required Decimal rate,
    required Decimal time,
  }) {
    final rateDecimal = rate.toDouble() / 100;
    final onePlusRate = 1 + rateDecimal;
    final amount = principal.toDouble() * math.pow(onePlusRate, time.toDouble());
    return _toDecimal(amount - principal.toDouble());
  }

  /// Calculate monthly compound interest
  static Decimal calculateMonthlyCompoundInterest({
    required Decimal principal,
    required Decimal annualRate,
    required Decimal months,
  }) {
    final monthlyRate = annualRate.toDouble() / 1200; // Annual rate / 12 / 100
    final onePlusRate = 1 + monthlyRate;
    final amount = principal.toDouble() * math.pow(onePlusRate, months.toDouble());
    return _toDecimal(amount - principal.toDouble());
  }

  /// Calculate EMI for loan
  /// Formula: EMI = P * r * (1 + r)^n / ((1 + r)^n - 1)
  static Decimal calculateEMI({
    required Decimal principal,
    required Decimal annualInterestRate,
    required int tenureInMonths,
  }) {
    if (tenureInMonths <= 0) return Decimal.zero;
    
    final monthlyRate = annualInterestRate.toDouble() / 1200; // Annual rate / 12 / 100
    
    if (monthlyRate == 0) {
      return _toDecimal(principal.toDouble() / tenureInMonths);
    }
    
    final onePlusRate = 1 + monthlyRate;
    final powerTerm = math.pow(onePlusRate, tenureInMonths);
    final numerator = principal.toDouble() * monthlyRate * powerTerm;
    final denominator = powerTerm - 1;
    
    return _toDecimal(numerator / denominator);
  }

  /// Calculate total amount for simple interest loan
  static Decimal calculateTotalAmount({
    required Decimal principal,
    required Decimal rate,
    required Decimal time,
  }) {
    final interest = calculateSimpleInterest(
      principal: principal,
      rate: rate,
      time: time,
    );
    return _toDecimal(principal.toDouble() + interest.toDouble());
  }

  /// Calculate late fee
  static Decimal calculateLateFee({
    required Decimal amount,
    required Decimal lateFeeRate,
    required int daysLate,
  }) {
    final dailyRate = lateFeeRate.toDouble() / 100 / 365;
    return _toDecimal(amount.toDouble() * dailyRate * daysLate);
  }

  /// Convert interest rate between different periods
  static Decimal convertInterestRate({
    required Decimal rate,
    required String fromPeriod,
    required String toPeriod,
  }) {
    double rateValue = rate.toDouble();
    
    // Simple conversion - can be enhanced for compound rates
    switch (fromPeriod.toLowerCase()) {
      case 'annual':
        if (toPeriod.toLowerCase() == 'monthly') rateValue /= 12;
        break;
      case 'monthly':
        if (toPeriod.toLowerCase() == 'annual') rateValue *= 12;
        break;
      case 'weekly':
        if (toPeriod.toLowerCase() == 'annual') rateValue *= 52;
        break;
      case 'daily':
        if (toPeriod.toLowerCase() == 'annual') rateValue *= 365;
        break;
    }
    
    return _toDecimal(rateValue);
  }

  /// Calculate remaining balance for amortized loan
  static Decimal calculateRemainingBalance({
    required Decimal principal,
    required Decimal monthlyRate,
    required int totalMonths,
    required int monthsPaid,
  }) {
    if (monthsPaid >= totalMonths) return Decimal.zero;
    
    final rate = monthlyRate.toDouble();
    if (rate == 0) {
      final principalPaid = principal.toDouble() * monthsPaid / totalMonths;
      return _toDecimal(principal.toDouble() - principalPaid);
    }
    
    final onePlusRate = 1 + rate;
    final totalPower = math.pow(onePlusRate, totalMonths);
    final paidPower = math.pow(onePlusRate, monthsPaid);
    final numerator = totalPower - paidPower;
    final denominator = totalPower - 1;
    
    return _toDecimal(principal.toDouble() * numerator / denominator);
  }

  /// Generate amortization schedule
  static List<Map<String, dynamic>> generateAmortizationSchedule({
    required Decimal principal,
    required Decimal annualInterestRate,
    required int tenureInMonths,
  }) {
    List<Map<String, dynamic>> schedule = [];
    
    if (tenureInMonths <= 0) return schedule;
    
    final monthlyRate = annualInterestRate.toDouble() / 1200;
    final emi = calculateEMI(
      principal: principal,
      annualInterestRate: annualInterestRate,
      tenureInMonths: tenureInMonths,
    );
    
    double balance = principal.toDouble();
    
    for (int month = 1; month <= tenureInMonths; month++) {
      final interestPayment = _toDecimal(balance * monthlyRate);
      final principalPayment = _toDecimal(emi.toDouble() - interestPayment.toDouble());
      balance = balance - principalPayment.toDouble();
      
      // Ensure balance doesn't go negative due to rounding
      if (balance < 0) balance = 0;
      
      schedule.add({
        'month': month,
        'emi': emi,
        'principalPayment': principalPayment,
        'interestPayment': interestPayment,
        'remainingBalance': _toDecimal(balance),
      });
    }
    
    return schedule;
  }

  /// Calculate break-even point for investment
  static int calculateBreakEvenMonths({
    required Decimal initialInvestment,
    required Decimal monthlyReturn,
  }) {
    if (monthlyReturn.toDouble() <= 0) return 0;
    return (initialInvestment.toDouble() / monthlyReturn.toDouble()).ceil();
  }

  /// Calculate return on investment percentage
  static Decimal calculateROI({
    required Decimal initialInvestment,
    required Decimal finalAmount,
  }) {
    if (initialInvestment.toDouble() == 0) return Decimal.zero;
    final roi = (finalAmount.toDouble() - initialInvestment.toDouble()) / initialInvestment.toDouble() * 100;
    return _toDecimal(roi);
  }

  /// Helper method to round to 2 decimal places
  static Decimal roundToTwoDecimals(Decimal value) {
    return _toDecimal((value.toDouble() * 100).round() / 100);
  }

  /// Format amount to Indian currency format
  static String formatIndianCurrency(Decimal amount) {
    final rounded = roundToTwoDecimals(amount);
    final parts = rounded.toString().split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : '00';
    
    // Add Indian number formatting (lakhs, crores)
    String formatted = integerPart;
    if (integerPart.length > 3) {
      formatted = integerPart.replaceAllMapped(
        RegExp(r'(\d+?)(?=(\d{2})+(\d{3})+$)'), 
        (match) => '${match.group(0)},',
      );
    }
    
    return '₹$formatted.$decimalPart';
  }

  /// Calculate total amount with penalty
  static Decimal calculateTotalAmountWithPenalty({
    required Decimal principal,
    required Decimal rate,
    required Decimal time,
    required Decimal penaltyRate,
    required int daysOverdue,
  }) {
    final totalAmount = calculateTotalAmount(
      principal: principal,
      rate: rate,
      time: time,
    );
    
    final penalty = calculateLateFee(
      amount: totalAmount,
      lateFeeRate: penaltyRate,
      daysLate: daysOverdue,
    );
    
    return _toDecimal(totalAmount.toDouble() + penalty.toDouble());
  }
}