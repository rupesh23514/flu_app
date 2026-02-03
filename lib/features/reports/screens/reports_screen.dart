import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/services/database_service.dart';
import '../../../core/repositories/payment_repository.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/models/payment.dart';
import '../../loan_management/providers/loan_provider.dart';

/// Date filter types for reports
enum ReportPeriod {
  today,
  thisWeek,
  thisMonth,
  thisQuarter,
  thisYear,
  custom,
  all,
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod _selectedPeriod = ReportPeriod.thisMonth;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _isLoading = false;

  // Calculated metrics
  double _totalDisbursed = 0;
  double _totalCollected = 0;
  double _totalOutstanding = 0;
  double _todayCollection = 0;
  int _activeLoans = 0;
  int _overdueLoans = 0;
  int _closedLoans = 0;

  // Enhanced metrics
  double _weeklyCollection = 0;
  double _lastWeekCollection = 0;
  List<double> _weeklyTrends = [];
  Map<String, int> _overdueAging = {};
  Map<PaymentMethod, double> _paymentMethodBreakdown = {};
  double _expectedCollection = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReportData();
    });
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);

    try {
      final dateRange = _getDateRange(_selectedPeriod);
      final loanProvider = Provider.of<LoanProvider>(context, listen: false);

      // Filter loans by date range
      final allLoans = loanProvider.loans;
      final filteredLoans =
          _filterLoansByDate(allLoans, dateRange.$1, dateRange.$2);

      // Calculate basic metrics
      _totalDisbursed = filteredLoans.fold(
          0.0, (sum, loan) => sum + loan.principal.toDouble());
      _totalCollected = filteredLoans.fold(
          0.0, (sum, loan) => sum + loan.totalPaid.toDouble());
      _totalOutstanding = filteredLoans
          .where((l) =>
              l.status != LoanStatus.closed && l.status != LoanStatus.completed)
          .fold(
              0.0,
              (sum, loan) =>
                  sum +
                  (loan.principal.toDouble() - loan.totalPaid.toDouble())
                      .clamp(0, double.infinity));

      _activeLoans =
          filteredLoans.where((l) => l.status == LoanStatus.active).length;
      _overdueLoans =
          filteredLoans.where((l) => l.status == LoanStatus.overdue).length;
      _closedLoans = filteredLoans
          .where((l) =>
              l.status == LoanStatus.closed || l.status == LoanStatus.completed)
          .length;

      // Get today's collection from database
      final stats = await DatabaseService.instance.getDashboardStats();
      _todayCollection = stats['todayCollection']?.toDouble() ?? 0.0;

      // Calculate enhanced metrics
      await _calculateEnhancedMetrics(allLoans);
    } catch (e) {
      debugPrint('Error loading report data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateEnhancedMetrics(List<Loan> allLoans) async {
    final now = DateTime.now();

    // Weekly collection trends (last 4 weeks)
    _weeklyTrends = [];
    for (int i = 3; i >= 0; i--) {
      final weekStart = now.subtract(Duration(days: (i + 1) * 7));
      final weekEnd = now.subtract(Duration(days: i * 7));
      final result = await PaymentRepository.instance
          .getTotalByDateRange(weekStart, weekEnd);
      _weeklyTrends.add(result.dataOrNull ?? 0.0);
    }

    // This week vs last week
    final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = thisWeekStart.subtract(const Duration(days: 1));

    final thisWeekResult = await PaymentRepository.instance
        .getTotalByDateRange(thisWeekStart, now);
    _weeklyCollection = thisWeekResult.dataOrNull ?? 0.0;

    final lastWeekResult = await PaymentRepository.instance
        .getTotalByDateRange(lastWeekStart, lastWeekEnd);
    _lastWeekCollection = lastWeekResult.dataOrNull ?? 0.0;

    // Overdue aging analysis
    _overdueAging = {'0-7': 0, '8-14': 0, '15-30': 0, '30+': 0};
    for (final loan in allLoans.where((l) => l.status == LoanStatus.overdue)) {
      final daysOverdue = now.difference(loan.dueDate).inDays;
      if (daysOverdue <= 7) {
        _overdueAging['0-7'] = (_overdueAging['0-7'] ?? 0) + 1;
      } else if (daysOverdue <= 14) {
        _overdueAging['8-14'] = (_overdueAging['8-14'] ?? 0) + 1;
      } else if (daysOverdue <= 30) {
        _overdueAging['15-30'] = (_overdueAging['15-30'] ?? 0) + 1;
      } else {
        _overdueAging['30+'] = (_overdueAging['30+'] ?? 0) + 1;
      }
    }

    // Payment method breakdown
    _paymentMethodBreakdown = {};
    final allPaymentsResult = await PaymentRepository.instance.getAll();
    final allPayments = allPaymentsResult.dataOrNull ?? [];
    for (final payment in allPayments) {
      _paymentMethodBreakdown[payment.paymentMethod] =
          (_paymentMethodBreakdown[payment.paymentMethod] ?? 0) +
              payment.amount.toDouble();
    }

    // Expected collection (for active weekly loans: EMI * weeks since loan start)
    _expectedCollection = 0;
    for (final loan in allLoans
        .where((l) => l.status == LoanStatus.active && !l.isMonthlyInterest)) {
      final weeksSinceLoan = now.difference(loan.loanDate).inDays ~/ 7;
      final emiAmount = loan.principal.toDouble() / 10;
      _expectedCollection +=
          (weeksSinceLoan * emiAmount).clamp(0, loan.principal.toDouble());
    }
  }

  (DateTime?, DateTime?) _getDateRange(ReportPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case ReportPeriod.today:
        return (
          DateTime(now.year, now.month, now.day),
          DateTime(now.year, now.month, now.day, 23, 59, 59)
        );
      case ReportPeriod.thisWeek:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        return (
          DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day),
          now
        );
      case ReportPeriod.thisMonth:
        return (DateTime(now.year, now.month, 1), now);
      case ReportPeriod.thisQuarter:
        final quarterMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return (DateTime(now.year, quarterMonth, 1), now);
      case ReportPeriod.thisYear:
        return (DateTime(now.year, 1, 1), now);
      case ReportPeriod.custom:
        return (_customStartDate, _customEndDate);
      case ReportPeriod.all:
        return (null, null);
    }
  }

  List<Loan> _filterLoansByDate(
      List<Loan> loans, DateTime? start, DateTime? end) {
    if (start == null && end == null) return loans;

    return loans.where((loan) {
      final loanDate = loan.loanDate;
      if (start != null && loanDate.isBefore(start)) return false;
      if (end != null && loanDate.isAfter(end)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReportData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReportData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Period Selector
                    _buildPeriodSelector(),

                    const SizedBox(height: 20),

                    // Summary Cards
                    _buildSummaryCards(),

                    const SizedBox(height: 20),

                    // Collection Efficiency Section
                    _buildCollectionEfficiency(),

                    const SizedBox(height: 20),

                    // Weekly Trend Analysis
                    _buildWeeklyTrendAnalysis(),

                    const SizedBox(height: 20),

                    // Overdue Aging Analysis
                    if (_overdueLoans > 0) ...[
                      _buildOverdueAgingAnalysis(),
                      const SizedBox(height: 20),
                    ],

                    // Payment Method Breakdown
                    _buildPaymentMethodBreakdown(),

                    const SizedBox(height: 20),

                    // Loan Status Breakdown
                    _buildLoanStatusBreakdown(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPeriodSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.date_range, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Report Period',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPeriodChip('Today', ReportPeriod.today, Icons.today),
                _buildPeriodChip(
                    'Week', ReportPeriod.thisWeek, Icons.view_week),
                _buildPeriodChip(
                    'Month', ReportPeriod.thisMonth, Icons.calendar_month),
                _buildPeriodChip(
                    'Quarter', ReportPeriod.thisQuarter, Icons.date_range),
                _buildPeriodChip(
                    'Year', ReportPeriod.thisYear, Icons.calendar_today),
                _buildPeriodChip('All', ReportPeriod.all, Icons.all_inclusive),
              ],
            ),
            if (_selectedPeriod == ReportPeriod.custom) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_customStartDate != null
                          ? '${_customStartDate!.day}/${_customStartDate!.month}/${_customStartDate!.year}'
                          : 'Start Date'),
                      onPressed: () => _selectDate(true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_customEndDate != null
                          ? '${_customEndDate!.day}/${_customEndDate!.month}/${_customEndDate!.year}'
                          : 'End Date'),
                      onPressed: () => _selectDate(false),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodChip(String label, ReportPeriod period, IconData icon) {
    final isSelected = _selectedPeriod == period;
    return FilterChip(
      avatar: Icon(icon,
          size: 16, color: isSelected ? Colors.white : AppColors.primary),
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.primary,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      onSelected: (selected) {
        setState(() => _selectedPeriod = period);
        _loadReportData();
      },
    );
  }

  Future<void> _selectDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_customStartDate ?? DateTime.now())
          : (_customEndDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _customStartDate = picked;
        } else {
          _customEndDate = picked;
        }
      });
      if (_customStartDate != null && _customEndDate != null) {
        _loadReportData();
      }
    }
  }

  Widget _buildSummaryCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.count(
          crossAxisCount: constraints.maxWidth > 600 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: constraints.maxWidth > 600 ? 1.3 : 1.1,
          children: [
            _buildSummaryCard(
              'Total Given',
              CurrencyFormatter.format(_totalDisbursed),
              Icons.account_balance_wallet,
              AppColors.primary,
              subtitle: 'Principal Amount',
            ),
            _buildSummaryCard(
              'Collected',
              CurrencyFormatter.format(_totalCollected),
              Icons.check_circle,
              AppColors.success,
              subtitle: _calculateCollectionRate(),
            ),
            _buildSummaryCard(
              'Outstanding',
              CurrencyFormatter.format(_totalOutstanding),
              Icons.pending_actions,
              AppColors.warning,
              subtitle: '$_activeLoans active loans',
            ),
            _buildSummaryCard(
              'Today',
              CurrencyFormatter.format(_todayCollection),
              Icons.today,
              Colors.purple,
              subtitle: "Today's collection",
            ),
          ],
        );
      },
    );
  }

  String _calculateCollectionRate() {
    if (_totalDisbursed == 0) return '0% collected';
    final rate = (_totalCollected / _totalDisbursed * 100).toStringAsFixed(1);
    return '$rate% collected';
  }

  Widget _buildSummaryCard(
      String title, String value, IconData icon, Color color,
      {String? subtitle}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionEfficiency() {
    final collectionRate =
        _totalDisbursed > 0 ? (_totalCollected / _totalDisbursed * 100) : 0.0;
    final expectedRate = _expectedCollection > 0
        ? (_totalCollected / _expectedCollection * 100).clamp(0, 100)
        : 0.0;

    // Determine efficiency status
    Color efficiencyColor;
    String efficiencyText;
    IconData efficiencyIcon;

    if (expectedRate >= 90) {
      efficiencyColor = AppColors.success;
      efficiencyText = 'Excellent';
      efficiencyIcon = Icons.trending_up;
    } else if (expectedRate >= 70) {
      efficiencyColor = Colors.green.shade400;
      efficiencyText = 'Good';
      efficiencyIcon = Icons.thumb_up;
    } else if (expectedRate >= 50) {
      efficiencyColor = AppColors.warning;
      efficiencyText = 'Needs Attention';
      efficiencyIcon = Icons.warning_amber;
    } else {
      efficiencyColor = AppColors.error;
      efficiencyText = 'Critical';
      efficiencyIcon = Icons.error_outline;
    }

    // Weekly comparison
    double weeklyChange = 0;
    if (_lastWeekCollection > 0) {
      weeklyChange =
          ((_weeklyCollection - _lastWeekCollection) / _lastWeekCollection) *
              100;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: efficiencyColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.speed, color: efficiencyColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Collection Efficiency',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      Row(
                        children: [
                          Icon(efficiencyIcon,
                              size: 16, color: efficiencyColor),
                          const SizedBox(width: 4),
                          Text(
                            efficiencyText,
                            style: TextStyle(
                              color: efficiencyColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Efficiency Progress Bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Overall Collection Rate',
                        style: TextStyle(fontSize: 13)),
                    Text(
                      '${collectionRate.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (collectionRate / 100).clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.shade200,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(collectionRate >= 80
                            ? AppColors.success
                            : collectionRate >= 50
                                ? AppColors.warning
                                : AppColors.error),
                    minHeight: 10,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Expected vs Actual
            if (_expectedCollection > 0) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Expected vs Actual',
                          style: TextStyle(fontSize: 13)),
                      Text(
                        '${expectedRate.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: expectedRate >= 80
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (expectedRate / 100).clamp(0.0, 1.0),
                      backgroundColor: Colors.grey.shade200,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(expectedRate >= 80
                              ? AppColors.success
                              : expectedRate >= 50
                                  ? AppColors.warning
                                  : AppColors.error),
                      minHeight: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Expected: ${CurrencyFormatter.format(_expectedCollection)} | Actual: ${CurrencyFormatter.format(_totalCollected)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Weekly Comparison
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('This Week',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.format(_weeklyCollection),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  Container(
                      height: 30,
                      width: 1,
                      color: AppColors.textSecondary.withValues(alpha: 0.3)),
                  Column(
                    children: [
                      const Text('Last Week',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.format(_lastWeekCollection),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  Container(
                      height: 30,
                      width: 1,
                      color: AppColors.textSecondary.withValues(alpha: 0.3)),
                  Column(
                    children: [
                      const Text('Change',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            weeklyChange >= 0
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 14,
                            color: weeklyChange >= 0
                                ? AppColors.success
                                : AppColors.error,
                          ),
                          Text(
                            '${weeklyChange.abs().toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: weeklyChange >= 0
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyTrendAnalysis() {
    if (_weeklyTrends.isEmpty || _weeklyTrends.every((v) => v == 0)) {
      return const SizedBox.shrink();
    }

    final maxValue = _weeklyTrends.reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Weekly Collection Trend',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxValue * 1.2,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppColors.primary,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          CurrencyFormatter.format(rod.toY),
                          const TextStyle(color: Colors.white, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final labels = [
                            '3 Wks Ago',
                            '2 Wks Ago',
                            'Last Week',
                            'This Week'
                          ];
                          if (value.toInt() < labels.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                labels[value.toInt()],
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _weeklyTrends.asMap().entries.map((entry) {
                    final isLatest = entry.key == _weeklyTrends.length - 1;
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value,
                          color: isLatest
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.5),
                          width: 24,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverdueAgingAnalysis() {
    final total = _overdueAging.values.fold(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.warning_amber,
                      color: AppColors.error, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overdue Analysis',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '$total overdue loans',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Aging breakdown bars
            ...['0-7', '8-14', '15-30', '30+'].map((range) {
              final count = _overdueAging[range] ?? 0;
              final percentage = total > 0 ? (count / total) : 0.0;
              final color = range == '0-7'
                  ? Colors.orange
                  : range == '8-14'
                      ? Colors.deepOrange
                      : range == '15-30'
                          ? Colors.red.shade400
                          : AppColors.error;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$range days',
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          '$count loans (${(percentage * 100).toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodBreakdown() {
    final total = _paymentMethodBreakdown.values.fold(0.0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    final methodColors = {
      PaymentMethod.cash: Colors.green,
      PaymentMethod.upi: Colors.purple,
      PaymentMethod.bank: Colors.blue,
      PaymentMethod.other: Colors.orange,
    };

    final methodLabels = {
      PaymentMethod.cash: 'Cash',
      PaymentMethod.upi: 'UPI',
      PaymentMethod.bank: 'Bank',
      PaymentMethod.other: 'Other',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payment, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Payment Methods',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Pie Chart
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 140,
                    child: PieChart(
                      PieChartData(
                        sections: _paymentMethodBreakdown.entries.map((entry) {
                          final percentage = (entry.value / total) * 100;
                          return PieChartSectionData(
                            color: methodColors[entry.key] ?? Colors.grey,
                            value: entry.value,
                            title: '${percentage.toStringAsFixed(0)}%',
                            radius: 45,
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          );
                        }).toList(),
                        sectionsSpace: 2,
                        centerSpaceRadius: 20,
                      ),
                    ),
                  ),
                ),
                // Legend
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _paymentMethodBreakdown.entries.map((entry) {
                      final color = methodColors[entry.key] ?? Colors.grey;
                      final label = methodLabels[entry.key] ?? 'Unknown';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoanStatusBreakdown() {
    final total = _activeLoans + _overdueLoans + _closedLoans;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Loan Status Distribution',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (total == 0)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No loans in selected period'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 150,
                      child: _buildPieChart(),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatusIndicator(
                            'Active', _activeLoans, AppColors.primary),
                        const SizedBox(height: 8),
                        _buildStatusIndicator(
                            'Overdue', _overdueLoans, AppColors.warning),
                        const SizedBox(height: 8),
                        _buildStatusIndicator(
                            'Closed', _closedLoans, AppColors.success),
                        const Divider(height: 16),
                        _buildStatusIndicator(
                            'Total', total, AppColors.textSecondary),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    final total = _activeLoans + _overdueLoans + _closedLoans;
    if (total == 0) return const SizedBox.shrink();

    return PieChart(
      PieChartData(
        sections: [
          if (_activeLoans > 0)
            PieChartSectionData(
              color: AppColors.primary,
              value: _activeLoans.toDouble(),
              title: '${((_activeLoans / total) * 100).toStringAsFixed(0)}%',
              radius: 50,
              titleStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          if (_overdueLoans > 0)
            PieChartSectionData(
              color: AppColors.warning,
              value: _overdueLoans.toDouble(),
              title: '${((_overdueLoans / total) * 100).toStringAsFixed(0)}%',
              radius: 50,
              titleStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          if (_closedLoans > 0)
            PieChartSectionData(
              color: AppColors.success,
              value: _closedLoans.toDouble(),
              title: '${((_closedLoans / total) * 100).toStringAsFixed(0)}%',
              radius: 50,
              titleStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
        ],
        sectionsSpace: 2,
        centerSpaceRadius: 25,
      ),
    );
  }

  Widget _buildStatusIndicator(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        Text('$count',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}
