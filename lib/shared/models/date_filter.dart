import 'package:decimal/decimal.dart';

enum DateFilterType {
  today,
  thisWeek,
  thisMonth,
  thisQuarter,
  thisYear,
  custom,
  all,
}

class DateFilter {
  final DateFilterType type;
  final DateTime? startDate;
  final DateTime? endDate;
  final String displayName;

  const DateFilter({
    required this.type,
    this.startDate,
    this.endDate,
    required this.displayName,
  });

  factory DateFilter.today() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
    
    return DateFilter(
      type: DateFilterType.today,
      startDate: startOfDay,
      endDate: endOfDay,
      displayName: 'Today',
    );
  }

  factory DateFilter.thisWeek() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final endOfWeek = startOfDay.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
    
    return DateFilter(
      type: DateFilterType.thisWeek,
      startDate: startOfDay,
      endDate: endOfWeek,
      displayName: 'This Week',
    );
  }

  factory DateFilter.thisMonth() {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    
    return DateFilter(
      type: DateFilterType.thisMonth,
      startDate: startOfMonth,
      endDate: endOfMonth,
      displayName: 'This Month',
    );
  }

  factory DateFilter.thisQuarter() {
    final now = DateTime.now();
    final currentQuarter = ((now.month - 1) ~/ 3) + 1;
    final startMonth = (currentQuarter - 1) * 3 + 1;
    final endMonth = currentQuarter * 3;
    
    final startOfQuarter = DateTime(now.year, startMonth, 1);
    final endOfQuarter = DateTime(now.year, endMonth + 1, 0, 23, 59, 59);
    
    return DateFilter(
      type: DateFilterType.thisQuarter,
      startDate: startOfQuarter,
      endDate: endOfQuarter,
      displayName: 'This Quarter',
    );
  }

  factory DateFilter.thisYear() {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final endOfYear = DateTime(now.year, 12, 31, 23, 59, 59);
    
    return DateFilter(
      type: DateFilterType.thisYear,
      startDate: startOfYear,
      endDate: endOfYear,
      displayName: 'This Year',
    );
  }

  factory DateFilter.custom(DateTime start, DateTime end) {
    final startOfDay = DateTime(start.year, start.month, start.day);
    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    
    return DateFilter(
      type: DateFilterType.custom,
      startDate: startOfDay,
      endDate: endOfDay,
      displayName: 'Custom Range',
    );
  }

  factory DateFilter.all() {
    return const DateFilter(
      type: DateFilterType.all,
      displayName: 'All Time',
    );
  }

  bool isWithinRange(DateTime date) {
    if (type == DateFilterType.all) return true;
    if (startDate == null || endDate == null) return true;
    
    return date.isAfter(startDate!.subtract(const Duration(seconds: 1))) &&
           date.isBefore(endDate!.add(const Duration(seconds: 1)));
  }

  @override
  String toString() {
    return 'DateFilter(type: $type, startDate: $startDate, endDate: $endDate, displayName: $displayName)';
  }
}

class FinancialMetrics {
  final Decimal totalPrincipalGiven;
  final Decimal totalCollected;
  final Decimal outstandingAmount;
  final Decimal profit;
  final double roi; // Return on Investment percentage
  final double collectionRate; // Percentage of disbursed amount collected
  final int totalLoans;
  final int activeLoans;
  final int overdueLoans;
  final int completedLoans;
  final Map<String, Decimal> monthlyBreakdown;
  final List<TrendData> trends;
  final DateFilter appliedFilter;

  const FinancialMetrics({
    required this.totalPrincipalGiven,
    required this.totalCollected,
    required this.outstandingAmount,
    required this.profit,
    required this.roi,
    required this.collectionRate,
    required this.totalLoans,
    required this.activeLoans,
    required this.overdueLoans,
    required this.completedLoans,
    required this.monthlyBreakdown,
    required this.trends,
    required this.appliedFilter,
  });

  factory FinancialMetrics.empty(DateFilter filter) {
    return FinancialMetrics(
      totalPrincipalGiven: Decimal.zero,
      totalCollected: Decimal.zero,
      outstandingAmount: Decimal.zero,
      profit: Decimal.zero,
      roi: 0.0,
      collectionRate: 0.0,
      totalLoans: 0,
      activeLoans: 0,
      overdueLoans: 0,
      completedLoans: 0,
      monthlyBreakdown: {},
      trends: [],
      appliedFilter: filter,
    );
  }

  @override
  String toString() {
    return 'FinancialMetrics(totalGiven: $totalPrincipalGiven, collected: $totalCollected, outstanding: $outstandingAmount, profit: $profit, roi: ${roi.toStringAsFixed(2)}%)';
  }
}

class TrendData {
  final DateTime date;
  final Decimal disbursed;
  final Decimal collected;
  final Decimal outstanding;
  final String period; // 'day', 'week', 'month', 'quarter'

  const TrendData({
    required this.date,
    required this.disbursed,
    required this.collected,
    required this.outstanding,
    required this.period,
  });

  @override
  String toString() {
    return 'TrendData(date: $date, disbursed: $disbursed, collected: $collected, outstanding: $outstanding)';
  }
}

class LoanStatusBreakdown {
  final int active;
  final int overdue;
  final int completed;
  final int defaulted;
  final int total;

  const LoanStatusBreakdown({
    required this.active,
    required this.overdue,
    required this.completed,
    required this.defaulted,
    required this.total,
  });

  double get activePercentage => total > 0 ? (active / total) * 100 : 0.0;
  double get overduePercentage => total > 0 ? (overdue / total) * 100 : 0.0;
  double get completedPercentage => total > 0 ? (completed / total) * 100 : 0.0;
  double get defaultedPercentage => total > 0 ? (defaulted / total) * 100 : 0.0;

  @override
  String toString() {
    return 'LoanStatusBreakdown(active: $active, overdue: $overdue, completed: $completed, defaulted: $defaulted, total: $total)';
  }
}