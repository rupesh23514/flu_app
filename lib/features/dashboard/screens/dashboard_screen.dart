import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:decimal/decimal.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/loan.dart';
import '../../loan_management/providers/loan_provider.dart';
import '../../customer_management/providers/customer_provider.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int)? onNavigateToTab;
  
  const DashboardScreen({super.key, this.onNavigateToTab});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    
    try {
      await loanProvider.loadLoans();
      await customerProvider.loadCustomers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    icon,
                    color: color,
                    size: 24,
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.trending_up,
                      color: color,
                      size: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: Consumer2<LoanProvider, CustomerProvider>(
          builder: (context, loanProvider, customerProvider, child) {
            if (loanProvider.isLoading || customerProvider.isLoading) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                ),
              );
            }

            final loans = loanProvider.loans;
            final customers = customerProvider.customers;

            // Calculate statistics
            final totalGiven = loans.fold(
              Decimal.zero,
              (sum, loan) => sum + loan.principal,
            );

            final totalReceived = loans.fold(
              Decimal.zero,
              (sum, loan) => sum + loan.totalPaid,
            );

            final outstanding = totalGiven - totalReceived;

            final todayCollection = loans.fold(
              Decimal.zero,
              (sum, loan) {
                final today = DateTime.now();
                final todayPayments = loan.payments.where((payment) {
                  return payment.date.year == today.year &&
                         payment.date.month == today.month &&
                         payment.date.day == today.day;
                }).fold(Decimal.zero, (sum, payment) => sum + payment.amount);
                return sum + todayPayments;
              },
            );

            final overdueLoans = loans.where((loan) => loan.status == LoanStatus.overdue).length;
            final dueTodayLoans = loans.where((loan) => loan.status == LoanStatus.active).length;
            final activeLoans = loans.where((loan) => loan.status == LoanStatus.active).length;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Welcome section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome Back!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Here\'s your financial overview',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Statistics grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Adjust aspect ratio based on available width
                    final aspectRatio = constraints.maxWidth > 400 ? 1.1 : 0.95;
                    return GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: aspectRatio,
                      children: [
                    _buildStatCard(
                      title: 'Total Given',
                      value: '₹${totalGiven.toString()}',
                      icon: Icons.account_balance_wallet,
                      color: AppColors.primary,
                      onTap: () => widget.onNavigateToTab?.call(1),
                    ),
                    _buildStatCard(
                      title: 'Outstanding',
                      value: '₹${outstanding.toString()}',
                      icon: Icons.trending_up,
                      color: AppColors.warning,
                      onTap: () => widget.onNavigateToTab?.call(1),
                    ),
                    _buildStatCard(
                      title: 'Total Customers',
                      value: customers.length.toString(),
                      icon: Icons.people,
                      color: AppColors.info,
                      onTap: () => Navigator.pushNamed(context, '/add-borrower'),
                    ),
                    _buildStatCard(
                      title: 'Active Loans',
                      value: activeLoans.toString(),
                      icon: Icons.description,
                      color: AppColors.success,
                      onTap: () => widget.onNavigateToTab?.call(1),
                    ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Today's collection card
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/payment-collection'),
                  child: Card(
                    elevation: 2,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppColors.success.withValues(alpha: 0.05),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.today,
                                color: AppColors.success,
                                size: 28,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Today\'s Collection',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '₹${todayCollection.toString()}',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Quick stats row
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onNavigateToTab?.call(1),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    overdueLoans.toString(),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.error,
                                    ),
                                    maxLines: 1,
                                  ),
                                ),
                                const Text(
                                  'Overdue',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onNavigateToTab?.call(1),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    dueTodayLoans.toString(),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.warning,
                                    ),
                                    maxLines: 1,
                                  ),
                                ),
                                const Text(
                                  'Due Today',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}