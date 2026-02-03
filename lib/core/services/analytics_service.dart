import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../../shared/models/date_filter.dart';
import '../../shared/models/loan.dart';
import '../../shared/models/payment.dart';

/// Service class for calculating financial analytics and metrics
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  static AnalyticsService get instance => _instance;
  AnalyticsService._internal();

  final DatabaseService _databaseService = DatabaseService.instance;

  /// Calculate comprehensive financial metrics for a given date filter
  Future<FinancialMetrics> calculateMetrics(DateFilter filter) async {
    try {
      // Get all loans and payments within the date range
      final loans = await _getLoansByDateRange(filter);
      final payments = await _getPaymentsByDateRange(filter);

      // Calculate basic metrics
      final totalPrincipalGiven = _calculateTotalPrincipal(loans);
      final totalCollected = _calculateTotalCollected(payments);
      final outstandingAmount = _calculateOutstanding(loans, payments);
      final profit = _calculateProfit(loans, payments);
      
      // Calculate percentages
      final roi = _calculateROI(totalPrincipalGiven, profit);
      final collectionRate = _calculateCollectionRate(totalPrincipalGiven, totalCollected);
      
      // Calculate loan status breakdown
      final statusBreakdown = _calculateLoanStatusBreakdown(loans);
      
      // Calculate trends (simplified for now)
      final trends = await _calculateTrends(filter);
      
      return FinancialMetrics(
        totalPrincipalGiven: totalPrincipalGiven,
        totalCollected: totalCollected,
        outstandingAmount: outstandingAmount,
        profit: profit,
        roi: roi,
        collectionRate: collectionRate,
        totalLoans: loans.length,
        activeLoans: statusBreakdown['active'] ?? 0,
        overdueLoans: statusBreakdown['overdue'] ?? 0,
        completedLoans: statusBreakdown['completed'] ?? 0,
        monthlyBreakdown: {},
        trends: trends,
        appliedFilter: filter,
      );
    } catch (e) {
      debugPrint('Error calculating metrics: $e');
      return FinancialMetrics.empty(filter);
    }
  }

  Future<List<Loan>> _getLoansByDateRange(DateFilter filter) async {
    // For now, return all loans - in a real implementation,
    // you would filter by date range
    try {
      return await _databaseService.getAllLoans();
    } catch (e) {
      debugPrint('Error getting loans: $e');
      return [];
    }
  }

  Future<List<Payment>> _getPaymentsByDateRange(DateFilter filter) async {
    // For now, return all payments - in a real implementation,
    // you would filter by date range  
    try {
      return await _databaseService.getAllPayments();
    } catch (e) {
      debugPrint('Error getting payments: $e');
      return [];
    }
  }

  Decimal _calculateTotalPrincipal(List<Loan> loans) {
    return loans.fold(Decimal.zero, (sum, loan) => sum + loan.principal);
  }

  Decimal _calculateTotalCollected(List<Payment> payments) {
    return payments.fold(Decimal.zero, (sum, payment) => sum + payment.amount);
  }

  Decimal _calculateOutstanding(List<Loan> loans, List<Payment> payments) {
    final totalGiven = _calculateTotalPrincipal(loans);
    final totalCollected = _calculateTotalCollected(payments);
    final outstanding = totalGiven - totalCollected;
    return outstanding > Decimal.zero ? outstanding : Decimal.zero;
  }

  Decimal _calculateProfit(List<Loan> loans, List<Payment> payments) {
    // Simplified profit calculation
    final totalCollected = _calculateTotalCollected(payments);
    final totalPrincipal = _calculateTotalPrincipal(loans);
    final profit = totalCollected - totalPrincipal;
    return profit;
  }

  double _calculateROI(Decimal principal, Decimal profit) {
    if (principal == Decimal.zero) return 0.0;
    return ((profit / principal).toDecimal() * Decimal.fromInt(100)).toDouble();
  }

  double _calculateCollectionRate(Decimal principal, Decimal collected) {
    if (principal == Decimal.zero) return 0.0;
    return ((collected / principal).toDecimal() * Decimal.fromInt(100)).toDouble();
  }

  Map<String, int> _calculateLoanStatusBreakdown(List<Loan> loans) {
    final breakdown = <String, int>{
      'active': 0,
      'overdue': 0,
      'completed': 0,
    };

    for (final loan in loans) {
      switch (loan.status) {
        case LoanStatus.active:
          breakdown['active'] = (breakdown['active'] ?? 0) + 1;
          break;
        case LoanStatus.overdue:
          breakdown['overdue'] = (breakdown['overdue'] ?? 0) + 1;
          break;
        case LoanStatus.closed:
        case LoanStatus.completed:
          breakdown['completed'] = (breakdown['completed'] ?? 0) + 1;
          break;
        default:
          break;
      }
    }

    return breakdown;
  }

  Future<List<TrendData>> _calculateTrends(DateFilter filter) async {
    // Simplified trend calculation - return empty list for now
    // In a real implementation, this would calculate daily/weekly/monthly trends
    return [];
  }
}