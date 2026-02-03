import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/loan.dart';
import '../providers/loan_provider.dart';
import '../../customer_management/providers/customer_provider.dart';

class LoanSheetScreen extends StatefulWidget {
  const LoanSheetScreen({super.key});

  @override
  State<LoanSheetScreen> createState() => _LoanSheetScreenState();
}

class _LoanSheetScreenState extends State<LoanSheetScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Loan> _filteredLoans = [];
  String _searchQuery = '';
  LoanStatus? _statusFilter;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

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
    
    await loanProvider.loadLoans();
    await customerProvider.loadCustomers();
    if (mounted) {
      _updateFilteredLoans();
    }
  }

  void _updateFilteredLoans() {
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    List<Loan> loans = loanProvider.loans;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      loans = loans.where((loan) {
        final customer = customerProvider.getLoadedCustomerById(loan.customerId);
        return customer?.name.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false;
      }).toList();
    }

    // Apply status filter
    if (_statusFilter != null) {
      loans = loans.where((loan) => loan.status == _statusFilter).toList();
    }

    setState(() {
      _filteredLoans = loans;
    });
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Loans'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Filter by Status:'),
            const SizedBox(height: 16),
            DropdownButton<LoanStatus?>(
              value: _statusFilter,
              hint: const Text('All Statuses'),
              isExpanded: true,
              items: [
                const DropdownMenuItem<LoanStatus?>(
                  value: null,
                  child: Text('All Statuses'),
                ),
                ...LoanStatus.values.map((status) {
                  return DropdownMenuItem<LoanStatus?>(
                    value: status,
                    child: Text(status.name.toUpperCase()),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _statusFilter = value;
                });
                _updateFilteredLoans();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _statusFilter = null;
              });
              _updateFilteredLoans();
              Navigator.of(context).pop();
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loan Sheet'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by customer name...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
                _updateFilteredLoans();
              },
            ),
          ),
          
          // Data table
          Expanded(
            child: Consumer2<LoanProvider, CustomerProvider>(
              builder: (context, loanProvider, customerProvider, child) {
                if (loanProvider.isLoading || customerProvider.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                  );
                }

                if (_filteredLoans.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No loans found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try adjusting your search or filters',
                          style: TextStyle(
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Card(
                  margin: const EdgeInsets.all(16),
                  child: DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 12,
                    minWidth: 800,
                    columns: const [
                      DataColumn2(
                        label: Text('Customer'),
                        size: ColumnSize.L,
                      ),
                      DataColumn2(
                        label: Text('Principal'),
                        size: ColumnSize.M,
                      ),
                      DataColumn2(
                        label: Text('Total'),
                        size: ColumnSize.M,
                      ),
                      DataColumn2(
                        label: Text('Paid'),
                        size: ColumnSize.M,
                      ),
                      DataColumn2(
                        label: Text('Due Date'),
                        size: ColumnSize.M,
                      ),
                      DataColumn2(
                        label: Text('Status'),
                        size: ColumnSize.S,
                      ),
                    ],
                    rows: _filteredLoans.map((loan) {
                      final customer = customerProvider.getLoadedCustomerById(loan.customerId);
                      final customerName = customer?.name ?? 'Unknown';
                      
                      return DataRow2(
                        cells: [
                          DataCell(
                            Text(
                              customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DataCell(
                            Text(_currencyFormat.format(loan.principal.toDouble())),
                          ),
                          DataCell(
                            Text(_currencyFormat.format(loan.totalAmount.toDouble())),
                          ),
                          DataCell(
                            Text(_currencyFormat.format(loan.totalPaid.toDouble())),
                          ),
                          DataCell(
                            Text(_dateFormat.format(loan.dueDate)),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(loan.status).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                loan.status.name.toUpperCase(),
                                style: TextStyle(
                                  color: _getStatusColor(loan.status),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                        onTap: () {
                          // Navigate to loan details or edit
                          Navigator.of(context).pushNamed(
                            '/payment-collection',
                            arguments: loan.id,
                          );
                        },
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _showAddOptions(context);
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.person_add, color: Colors.white),
                ),
                title: const Text('Add Customer', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Create a new borrower', maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/add-borrower');
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: AppColors.success,
                  child: Icon(Icons.add_card, color: Colors.white),
                ),
                title: const Text('Create Loan', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Add a new loan for a customer', maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/add-loan').then((_) => _loadData());
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: AppColors.warning,
                  child: Icon(Icons.payments, color: Colors.white),
                ),
                title: const Text('Collect Payment', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Record a payment for a loan', maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/payment-collection');
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(LoanStatus status) {
    switch (status) {
      case LoanStatus.active:
        return AppColors.success;
      case LoanStatus.closed:
        return AppColors.textSecondary;
      case LoanStatus.overdue:
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}