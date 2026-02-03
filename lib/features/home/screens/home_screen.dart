import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:decimal/decimal.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/excel_export_service.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/global_search_service.dart';
import '../../loan_management/providers/loan_provider.dart';
import '../../customer_management/providers/customer_provider.dart';
import '../../customer_management/screens/customer_detail_screen.dart';
import '../../loans/screens/add_loan_screen_new.dart';
import '../../loans/screens/add_monthly_interest_loan_screen.dart';
import '../../payments/screens/payment_collection_screen_new.dart';
import '../widgets/sidebar_menu.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/widgets/secure_balance_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'all'; // all, active, overdue, closed
  String _selectedLoanType = 'all'; // all, weekly, monthly
  bool _isSearching = false;
  String _searchQuery = '';
  bool _isGlobalSearchLoading = false;
  GlobalSearchResults? _globalSearchResults;
  Timer? _searchDebounceTimer; // Debounce search to prevent UI lag

  @override
  void initState() {
    super.initState();
    // Load data after the frame is built to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounceTimer?.cancel(); // Cancel timer to prevent memory leak
    super.dispose();
  }

  Future<void> _loadData() async {
    debugPrint('🏠 HomeScreen: Loading data...');
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    final customerProvider =
        Provider.of<CustomerProvider>(context, listen: false);
    await loanProvider.loadLoans();
    await customerProvider.loadCustomers();
    debugPrint(
        '🏠 HomeScreen: Data loaded - Loans: ${loanProvider.loans.length}, Customers: ${customerProvider.customers.length}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const SidebarMenu(),
      appBar: _buildAppBar(),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          child: Column(
            children: [
              // Quick Stats - Flexible to shrink when keyboard appears
              Flexible(
                flex: 0,
                child: _buildQuickStats(),
              ),

              // Filter Chips
              _buildFilterChips(),

              // Loan List
              Expanded(
                child: _buildLoanList(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddLoanOptions,
        backgroundColor: AppColors.success,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  void _showExportOptions() {
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    final loans = loanProvider.loans;
    final activeCount =
        loans.where((l) => l.status == LoanStatus.active).length;
    final overdueCount =
        loans.where((l) => l.status == LoanStatus.overdue).length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Export to Excel',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select which loans to export',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.folder, color: AppColors.primary),
                ),
                title: Text('All Loans (${loans.length})',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Export all loan records',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(context);
                  _exportLoans(null);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      const Icon(Icons.check_circle, color: AppColors.success),
                ),
                title: Text('Active Loans ($activeCount)',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Currently running loans',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(context);
                  _exportLoans(LoanStatus.active);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.warning, color: AppColors.error),
                ),
                title: Text('Overdue Loans ($overdueCount)',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Loans past due date',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(context);
                  _exportLoans(LoanStatus.overdue);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportLoans(LoanStatus? status) async {
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Generating Excel file...'),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );

    final success =
        await ExcelExportService.instance.exportAndShare(status: status);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content:
            Text(success ? 'Excel file ready to share' : 'Failed to export'),
        backgroundColor: success ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleCallCustomer(Customer customer) async {
    if (customer.hasMultiplePhones) {
      // Show dialog to select which number to call
      final selectedPhone = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Phone Number'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child:
                        Text('1', style: TextStyle(color: AppColors.primary)),
                  ),
                  title: Text(customer.phoneNumber,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Primary'),
                  onTap: () => Navigator.of(context).pop(customer.phoneNumber),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child:
                        Text('2', style: TextStyle(color: AppColors.primary)),
                  ),
                  title: Text(customer.alternatePhone!,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Alternate'),
                  onTap: () =>
                      Navigator.of(context).pop(customer.alternatePhone),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selectedPhone != null) {
        await _callCustomer(selectedPhone);
      }
    } else {
      await _callCustomer(customer.phoneNumber);
    }
  }

  Future<void> _callCustomer(String phoneNumber) async {
    final permissionService = PermissionService.instance;

    // Request phone permission
    final hasPermission = await permissionService.requestPhonePermission();

    if (hasPermission) {
      final uri = Uri.parse('tel:$phoneNumber');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Phone permission required to make calls'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => permissionService.openSettings(),
            ),
          ),
        );
      }
    }
  }

  PreferredSizeWidget _buildAppBar() {
    if (_isSearching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _isSearching = false;
              _searchQuery = '';
              _searchController.clear();
              _globalSearchResults = null;
            });
          },
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search by name, phone, or book #...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: AppColors.textSecondary),
          ),
          style: const TextStyle(fontSize: 18),
          onChanged: (value) {
            setState(() {
              _searchQuery = value.toLowerCase();
            });
            _performGlobalSearch(value);
          },
          onSubmitted: (value) {
            // Quick book number lookup for numeric input
            final trimmed = value.trim();
            if (RegExp(r'^\d+$').hasMatch(trimmed)) {
              _quickBookLookup(trimmed);
            }
          },
        ),
        actions: [
          if (_isGlobalSearchLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (_searchController.text.isNotEmpty && !_isGlobalSearchLoading)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                  _globalSearchResults = null;
                });
              },
            ),
        ],
      );
    }

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.menu),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      title: const Text('Loan Book'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            setState(() {
              _isSearching = true;
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.download),
          tooltip: 'Export to Excel',
          onPressed: _showExportOptions,
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _showAddLoanOptions,
        ),
      ],
    );
  }

  Future<void> _performGlobalSearch(String query) async {
    // Cancel any pending search to prevent rapid database queries
    _searchDebounceTimer?.cancel();

    if (query.trim().isEmpty) {
      setState(() => _globalSearchResults = null);
      return;
    }

    // Debounce search by 300ms to prevent lag on rapid typing
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      setState(() => _isGlobalSearchLoading = true);

      try {
        final results = await GlobalSearchService.instance.search(query);
        if (mounted && _searchQuery.isNotEmpty) {
          setState(() {
            _globalSearchResults = results;
            _isGlobalSearchLoading = false;
          });
        }
      } catch (e) {
        debugPrint('Global search error: $e');
        if (mounted) {
          setState(() => _isGlobalSearchLoading = false);
        }
      }
    });
  }

  Future<void> _quickBookLookup(String bookNumber) async {
    final loan =
        await GlobalSearchService.instance.findLoanByBookNumber(bookNumber);
    if (loan != null && mounted) {
      _openLoanDetails(loan);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Book #$bookNumber not found'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Widget _buildQuickStats() {
    // Get keyboard visibility to adjust size
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Consumer<LoanProvider>(
      builder: (context, loanProvider, _) {
        final loans = loanProvider.loans;
        // Outstanding = Principal - Paid (for active loans)
        final totalOutstanding = loans
            .where((l) =>
                l.status != LoanStatus.closed &&
                l.status != LoanStatus.completed)
            .fold(Decimal.zero,
                (sum, loan) => sum + (loan.principal - loan.totalPaid));
        final todayCollections =
            loanProvider.dashboardStats['todayCollection']?.toDouble() ?? 0.0;
        final overdueCount =
            loans.where((l) => l.status == LoanStatus.overdue).length;
        final activeCount =
            loans.where((l) => l.status == LoanStatus.active).length;

        // Separate counts for weekly and monthly
        final weeklyCount =
            loans.where((l) => l.loanType == LoanType.weekly).length;
        final monthlyCount =
            loans.where((l) => l.loanType == LoanType.monthlyInterest).length;

        // Show compact stats when keyboard is visible (instead of hiding completely)
        if (keyboardVisible) {
          // Import the shared visibility from SecureBalanceWidget would create circular dep
          // Instead, show compact version with SecureBalanceWidget functionality
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SecureBalanceWidget(
                    value:
                        CurrencyFormatter.format(totalOutstanding.toDouble()),
                    label: 'Outstanding',
                    icon: Icons.account_balance_wallet,
                    valueStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white.withValues(alpha: 0.3),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                ),
                Expanded(
                  child: SecureBalanceWidget(
                    value: CurrencyFormatter.format(todayCollections),
                    label: 'Today',
                    icon: Icons.today,
                    valueStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SecureBalanceWidget(
                      value:
                          CurrencyFormatter.format(totalOutstanding.toDouble()),
                      label: 'Total Outstanding',
                      icon: Icons.account_balance_wallet,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 50,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  Expanded(
                    child: SecureBalanceWidget(
                      value: CurrencyFormatter.format(todayCollections),
                      label: "Today's Collection",
                      icon: Icons.today,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Loan type counts row
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStat(
                        'Weekly', weeklyCount.toString(), AppColors.primary),
                  ),
                  Expanded(
                    child: _buildMiniStat(
                        'Monthly', monthlyCount.toString(), Colors.orange),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Status counts row
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStat(
                        'Active', activeCount.toString(), AppColors.loanActive),
                  ),
                  Expanded(
                    child: _buildMiniStat('Overdue', overdueCount.toString(),
                        AppColors.loanOverdue),
                  ),
                  Expanded(
                    child: _buildMiniStat(
                        'Total', loans.length.toString(), Colors.white),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$label: $value',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    // Hide filter chips when keyboard is visible
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    if (keyboardVisible) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Loan Type Filter (Weekly / Monthly)
        _buildLoanTypeFilter(),
        const SizedBox(height: 8),
        // Status Filter
        _buildStatusFilter(),
      ],
    );
  }

  Widget _buildLoanTypeFilter() {
    final loanTypes = [
      {
        'key': 'all',
        'label': 'All Loans',
        'icon': Icons.list_alt,
        'color': AppColors.primary
      },
      {
        'key': 'weekly',
        'label': 'Weekly',
        'icon': Icons.calendar_view_week,
        'color': AppColors.primary
      },
      {
        'key': 'monthly',
        'label': 'Monthly Interest',
        'icon': Icons.percent,
        'color': Colors.orange
      },
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: loanTypes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = loanTypes[index];
          final isSelected = _selectedLoanType == type['key'];
          final color = type['color'] as Color;

          return ChoiceChip(
            selected: isSelected,
            avatar: Icon(
              type['icon'] as IconData,
              size: 16,
              color: isSelected ? Colors.white : color,
            ),
            label: Text(type['label'] as String),
            onSelected: (selected) {
              setState(() {
                _selectedLoanType = type['key'] as String;
              });
            },
            selectedColor: color,
            backgroundColor: color.withValues(alpha: 0.1),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        },
      ),
    );
  }

  Widget _buildStatusFilter() {
    final filters = [
      {'key': 'all', 'label': 'All'},
      {'key': 'active', 'label': 'Active'},
      {'key': 'overdue', 'label': 'Overdue'},
      {'key': 'closed', 'label': 'Closed'},
    ];

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter['key'];

          return FilterChip(
            selected: isSelected,
            label: Text(filter['label']!),
            onSelected: (selected) {
              setState(() {
                _selectedFilter = filter['key']!;
              });
            },
            selectedColor: AppColors.primaryLight,
            checkmarkColor: AppColors.primary,
            backgroundColor: AppColors.surfaceContainer,
            labelStyle: TextStyle(
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 12,
            ),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  Widget _buildLoanList() {
    // Show global search results if available
    if (_globalSearchResults != null && _globalSearchResults!.isNotEmpty) {
      return _buildGlobalSearchResults();
    }

    return Consumer2<LoanProvider, CustomerProvider>(
      builder: (context, loanProvider, customerProvider, _) {
        var loans = loanProvider.loans;

        // Apply loan type filter (Weekly / Monthly)
        if (_selectedLoanType != 'all') {
          loans = loans.where((l) {
            switch (_selectedLoanType) {
              case 'weekly':
                return l.loanType == LoanType.weekly;
              case 'monthly':
                return l.loanType == LoanType.monthlyInterest;
              default:
                return true;
            }
          }).toList();
        }

        // Apply status filter
        if (_selectedFilter != 'all') {
          loans = loans.where((l) {
            switch (_selectedFilter) {
              case 'active':
                return l.status == LoanStatus.active;
              case 'overdue':
                return l.status == LoanStatus.overdue;
              case 'closed':
                return l.status == LoanStatus.closed ||
                    l.status == LoanStatus.completed;
              default:
                return true;
            }
          }).toList();
        }

        // Apply search
        if (_searchQuery.isNotEmpty && _globalSearchResults == null) {
          loans = loans.where((loan) {
            final customer = customerProvider.customers.firstWhere(
              (c) => c.id == loan.customerId,
              orElse: () => Customer(
                id: 0,
                name: 'Unknown',
                phoneNumber: '',
                address: '',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
            return customer.name.toLowerCase().contains(_searchQuery) ||
                customer.phoneNumber.contains(_searchQuery) ||
                loan.id.toString().contains(_searchQuery);
          }).toList();
        }

        if (loans.isEmpty) {
          return _buildEmptyState();
        }

        // Sort by due date
        loans.sort((a, b) => a.dueDate.compareTo(b.dueDate));

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: loans.length,
          itemBuilder: (context, index) {
            return _buildLoanCard(loans[index], customerProvider);
          },
        );
      },
    );
  }

  Widget _buildGlobalSearchResults() {
    final results = _globalSearchResults!;

    // Combine all loans for card display
    final allLoans = results.loans;
    final allCustomers = results.customers;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Loans section - display as home page cards
        if (allLoans.isNotEmpty) ...[
          _buildSearchSectionHeader('Loans', Icons.receipt_long, allLoans.length),
          ...allLoans.map((result) => _buildLoanSearchCard(result)),
          const SizedBox(height: 16),
        ],

        // Customers section - simplified display
        if (allCustomers.isNotEmpty) ...[
          _buildSearchSectionHeader('Customers', Icons.person, allCustomers.length),
          ...allCustomers.map((result) => _buildCustomerSearchCard(result)),
        ],

        // Empty state
        if (results.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off,
                      size: 64,
                      color: AppColors.textSecondary.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  const Text(
                    'No results found',
                    style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try book number, name, or phone',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Build loan search result as home page style card
  Widget _buildLoanSearchCard(SearchResult result) {
    final loan = result.data as Loan;
    final customerName = result.title;
    final isMonthlyLoan = loan.loanType == LoanType.monthlyInterest;
    
    // Status colors
    Color statusColor;
    IconData statusIcon;
    switch (loan.status) {
      case LoanStatus.overdue:
        statusColor = AppColors.loanOverdue;
        statusIcon = Icons.warning_rounded;
        break;
      case LoanStatus.active:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        break;
      case LoanStatus.closed:
      case LoanStatus.completed:
        statusColor = AppColors.textSecondary;
        statusIcon = Icons.check_circle_outline;
        break;
      default:
        statusColor = AppColors.warning;
        statusIcon = Icons.schedule;
    }

    final loanTypeColor = isMonthlyLoan ? Colors.purple : Colors.blue;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _handleSearchResultTap(result),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: loanTypeColor, width: 4),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Customer Avatar
              CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.2),
                radius: 22,
                child: Text(
                  customerName.isNotEmpty ? customerName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Name and status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          loan.status.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Right side: Book #, Type Badge, Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Book Number (only if available)
                  if (loan.bookNo != null && loan.bookNo!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Book #${loan.bookNo}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  // Loan type + Amount
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: loanTypeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isMonthlyLoan ? 'M' : 'W',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: loanTypeColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        CurrencyFormatter.format(loan.principal.toDouble()),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build customer search result card
  Widget _buildCustomerSearchCard(SearchResult result) {
    final customer = result.data as Customer;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          radius: 20,
          child: Text(
            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          customer.name,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(
          customer.phoneNumber,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => _handleSearchResultTap(result),
      ),
    );
  }

  Widget _buildSearchSectionHeader(String title, IconData icon, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 12, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _handleSearchResultTap(SearchResult result) {
    // Close search mode
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
      _globalSearchResults = null;
    });

    switch (result.type) {
      case SearchResultType.customer:
        final customer = result.data as Customer;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                CustomerDetailScreen(customerId: customer.id!),
          ),
        );
        break;
      case SearchResultType.loan:
        final loan = result.data as Loan;
        _openLoanDetails(loan);
        break;
      case SearchResultType.payment:
        // For payments, open the associated loan
        final loanProvider = Provider.of<LoanProvider>(context, listen: false);
        final payment = result.data;
        if (loanProvider.loans.isEmpty) return;
        final loan = loanProvider.loans.firstWhere(
          (l) => l.id == payment.loanId,
          orElse: () => loanProvider.loans.first,
        );
        _openLoanDetails(loan);
        break;
    }
  }

  Widget _buildLoanCard(Loan loan, CustomerProvider customerProvider) {
    String customerName = 'Unknown';
    Customer? customer;

    final matches = customerProvider.customers.where((c) => c.id == loan.customerId);
    if (matches.isNotEmpty) {
      customer = matches.first;
      customerName = customer.name;
    }

    Color statusColor;
    IconData statusIcon;
    switch (loan.status) {
      case LoanStatus.overdue:
        statusColor = AppColors.loanOverdue;
        statusIcon = Icons.warning_amber_rounded;
        break;
      case LoanStatus.closed:
      case LoanStatus.completed:
        statusColor = AppColors.loanClosed;
        statusIcon = Icons.check_circle;
        break;
      default:
        statusColor = AppColors.loanActive;
        statusIcon = Icons.schedule;
    }

    // Loan type badge colors
    final isMonthlyLoan = loan.isMonthlyInterest;
    final loanTypeColor = isMonthlyLoan ? Colors.orange : AppColors.primary;

    final daysUntilDue = loan.dueDate.difference(DateTime.now()).inDays;
    String dueText;
    if (loan.status == LoanStatus.closed ||
        loan.status == LoanStatus.completed) {
      dueText = 'Completed';
    } else if (daysUntilDue < 0) {
      dueText = '${-daysUntilDue} days overdue';
    } else if (daysUntilDue == 0) {
      dueText = 'Due today';
    } else {
      dueText = 'Due in $daysUntilDue days';
    }

    // Calculate EMI or monthly interest
    final Decimal emiOrInterest = isMonthlyLoan
        ? (loan.monthlyInterestAmount ?? Decimal.zero)
        : Decimal.parse(
            (loan.tenure > 0 ? loan.totalAmount.toDouble() / loan.tenure : 0.0).toStringAsFixed(2));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openLoanDetails(loan),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: loanTypeColor,
                width: 4,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    // Customer Avatar
                    CircleAvatar(
                      backgroundColor: statusColor.withValues(alpha: 0.2),
                      radius: 22,
                      child: Text(
                        customerName.isNotEmpty
                            ? customerName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Name and Status only - more space for name
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customerName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(statusIcon, size: 14, color: statusColor),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  dueText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: statusColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    
                    // Right side: Loan Type Badge + Principal Amount
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Loan Type Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: loanTypeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isMonthlyLoan
                                    ? Icons.percent
                                    : Icons.calendar_view_week,
                                size: 10,
                                color: loanTypeColor,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                isMonthlyLoan ? 'Monthly' : 'Weekly',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: loanTypeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Principal Amount
                        Text(
                          CurrencyFormatter.format(loan.principal.toDouble()),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Details Row - Different for weekly vs monthly
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: isMonthlyLoan
                        ? [
                            _buildLoanDetail(
                                'Monthly Interest',
                                CurrencyFormatter.format(
                                    emiOrInterest.toDouble()),
                                color: Colors.orange),
                            _buildLoanDetail(
                                'Outstanding',
                                CurrencyFormatter.format(
                                    loan.remainingAmount.toDouble()),
                                color: AppColors.loanOverdue),
                          ]
                        : [
                            _buildLoanDetail(
                                'Principal',
                                CurrencyFormatter.format(
                                    loan.principal.toDouble())),
                            _buildLoanDetail(
                                'EMI',
                                CurrencyFormatter.format(
                                    emiOrInterest.toDouble())),
                          ],
                  ),
                ),

                const SizedBox(height: 12),

                // Action Buttons
                Row(
                  children: [
                    if (loan.status != LoanStatus.closed &&
                        loan.status != LoanStatus.completed) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _collectPayment(loan),
                          icon: const Icon(Icons.payment, size: 16),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Collect', maxLines: 1),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: customer != null
                            ? () => _handleCallCustomer(customer!)
                            : null,
                        icon: const Icon(Icons.phone, size: 16),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Call', maxLines: 1),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoanDetail(String label, String value, {Color? color}) {
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color ?? AppColors.textPrimary,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 80,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No loans found'
                : _selectedFilter != 'all'
                    ? 'No $_selectedFilter loans'
                    : 'No loans yet',
            style: const TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Tap the + button to add your first loan'
                : 'Try a different search term',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 24),
          if (_searchQuery.isEmpty)
            ElevatedButton.icon(
              onPressed: _showAddLoanOptions,
              icon: const Icon(Icons.add),
              label: const Text('Add Loan'),
            ),
        ],
      ),
    );
  }

  void _showAddLoanOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Add New Loan',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Weekly Loan Section Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                width: double.infinity,
                child: const Text(
                  'Weekly Loan (10 Week Tenure)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),

              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_add,
                      color: AppColors.primary, size: 22),
                ),
                title: const Text('New Customer',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Create a new customer and loan',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToAddLoan(isNewCustomer: true);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_search,
                      color: AppColors.primary, size: 22),
                ),
                title: const Text('Existing Customer',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Add loan for an existing customer',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToAddLoan(isNewCustomer: false);
                },
              ),

              const Divider(height: 24),

              // Monthly Interest Loan Section Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                width: double.infinity,
                child: Text(
                  'Monthly Interest Loan',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),

              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person_add,
                      color: Colors.orange.shade700, size: 22),
                ),
                title: const Text('New Customer (Monthly)',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text(
                    'Manual interest entry, monthly collection',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToAddMonthlyLoan(isNewCustomer: true);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person_search,
                      color: Colors.orange.shade700, size: 22),
                ),
                title: const Text('Existing Customer (Monthly)',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text(
                    'Monthly interest loan for existing customer',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToAddMonthlyLoan(isNewCustomer: false);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToAddLoan({required bool isNewCustomer}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddLoanScreenNew(
          isNewCustomer: isNewCustomer,
          paymentType:
              'weekly', // Pre-select weekly since this is from Weekly Loan section
        ),
      ),
    );
    // Always reload data when returning, especially if loan was created
    if (mounted) {
      debugPrint('🏠 HomeScreen: Returned from AddLoan, result: $result');
      await _loadData();
    }
  }

  void _navigateToAddMonthlyLoan({required bool isNewCustomer}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AddMonthlyInterestLoanScreen(isNewCustomer: isNewCustomer),
      ),
    );
    // Always reload data when returning
    if (mounted) {
      debugPrint(
          '🏠 HomeScreen: Returned from AddMonthlyLoan, result: $result');
      await _loadData();
    }
  }

  void _openLoanDetails(Loan loan) async {
    // Navigate to CustomerDetailScreen with Payments tab (index 1) selected
    // This ensures consistent UI whether opened from Home or Customer Groups
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerDetailScreen(
          customerId: loan.customerId,
          initialTabIndex: 1, // Open Payments tab
        ),
      ),
    );
    if (mounted) {
      await _loadData();
    }
  }

  void _collectPayment(Loan loan) async {
    // Navigate to new payment collection screen with loan data
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentCollectionScreenNew(loan: loan),
      ),
    );
    if (mounted) {
      await _loadData();
    }
  }
}
