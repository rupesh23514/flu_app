// ignore_for_file: unused_element
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:decimal/decimal.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/models/payment.dart';
import '../../../shared/widgets/location_picker_widget.dart';
import '../providers/customer_provider.dart';
import '../../loan_management/providers/loan_provider.dart';
import '../../payments/screens/payment_collection_screen_new.dart';
import '../../loans/screens/add_loan_screen_new.dart';

class CustomerDetailScreen extends StatefulWidget {
  final int customerId;
  final int initialTabIndex;

  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    this.initialTabIndex = 0,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Customer? _customer;
  List<Loan> _customerLoans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    // Defer loading to after the first frame to avoid calling notifyListeners during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final customerProvider =
        Provider.of<CustomerProvider>(context, listen: false);
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);

    await customerProvider.loadCustomers();
    await loanProvider.loadLoans();

    final customer = await customerProvider.getCustomerById(widget.customerId);
    final loans = loanProvider.loans
        .where((loan) => loan.customerId == widget.customerId)
        .toList();

    setState(() {
      _customer = customer;
      _customerLoans = loans;
      _isLoading = false;
    });
  }

  Future<void> _updateCustomerLocation() async {
    final result = await Navigator.push<Map<String, double>>(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLatitude: _customer?.latitude,
          initialLongitude: _customer?.longitude,
          customerName: _customer?.name,
        ),
      ),
    );

    if (result != null && _customer != null && mounted) {
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      
      // Update customer with new location
      final updatedCustomer = Customer(
        id: _customer!.id,
        name: _customer!.name,
        phoneNumber: _customer!.phoneNumber,
        alternatePhone: _customer!.alternatePhone,
        bookNo: _customer!.bookNo,
        address: _customer!.address,
        latitude: result['latitude'],
        longitude: result['longitude'],
        createdAt: _customer!.createdAt,
        updatedAt: DateTime.now(),
      );

      final success = await customerProvider.updateCustomer(updatedCustomer);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadData();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update location'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showLoanTypeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Loan Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.calendar_view_week, color: Colors.blue.shade700),
              ),
              title: const Text('Weekly Loan'),
              subtitle: const Text('Weekly payment schedule'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddLoanScreenNew(
                      isNewCustomer: false,
                      existingCustomer: _customer,
                      paymentType: 'weekly',
                      showDailyOption: false,
                    ),
                  ),
                ).then((_) => _loadData());
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.calendar_month, color: Colors.green.shade700),
              ),
              title: const Text('Monthly Loan'),
              subtitle: const Text('Monthly payment schedule'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddLoanScreenNew(
                      isNewCustomer: false,
                      existingCustomer: _customer,
                      paymentType: 'monthly',
                      showDailyOption: false,
                    ),
                  ),
                ).then((_) => _loadData());
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showEditSelectionDialog() {
    // If no loans, just edit customer directly
    if (_customerLoans.isEmpty) {
      Navigator.of(context)
          .pushNamed('/add-borrower', arguments: _customer)
          .then((_) => _loadData());
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('What do you want to edit?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Edit Customer Details option
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.person_outline, color: AppColors.primary),
                ),
                title: const Text('Customer Details'),
                subtitle: const Text('Edit name, phone, address, etc.'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  Navigator.of(context)
                      .pushNamed('/add-borrower', arguments: _customer)
                      .then((_) => _loadData());
                },
              ),
              const Divider(),
              // Edit individual loans
              ..._customerLoans.asMap().entries.map((entry) {
                final index = entry.key;
                final loan = entry.value;
                final isMonthly = loan.isMonthlyInterest;
                final loanColor = isMonthly ? Colors.orange : AppColors.primary;
                final loanLabel = isMonthly ? 'Monthly' : 'Weekly';
                final bookLabel = loan.bookNo != null && loan.bookNo!.isNotEmpty 
                    ? ' - Book: ${loan.bookNo}' 
                    : '';
                
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: loanColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isMonthly ? Icons.calendar_month : Icons.calendar_view_week,
                      color: loanColor,
                    ),
                  ),
                  title: Text('Loan ${index + 1} ($loanLabel)$bookLabel'),
                  subtitle: Text(
                    'Principal: ₹${loan.principal.toStringAsFixed(0)} • ${loan.loanDate.day}/${loan.loanDate.month}/${loan.loanDate.year}',
                  ),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _showLoanEditOptions(loan, index + 1);
                  },
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showLoanEditOptions(Loan loan, int loanNumber) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit Loan $loanNumber'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.currency_rupee),
              title: const Text('Edit Principal Amount'),
              onTap: () {
                Navigator.pop(dialogContext);
                _showEditPrincipalDialog(loan);
              },
            ),
            // Show interest editing option only for monthly interest loans
            if (loan.isMonthlyInterest)
              ListTile(
                leading: const Icon(Icons.percent),
                title: const Text('Edit Monthly Interest'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _showEditInterestDialog(loan);
                },
              ),
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('Edit Book Number'),
              onTap: () {
                Navigator.pop(dialogContext);
                _showEditBookNoDialog(loan);
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Edit Loan Date'),
              onTap: () {
                Navigator.pop(dialogContext);
                _showEditLoanDateDialog(loan);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditPrincipalDialog(Loan loan) async {
    final controller = TextEditingController(text: loan.principal.toStringAsFixed(0));
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Principal Amount'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Principal Amount',
            prefixText: '₹ ',
            hintText: 'Enter principal amount',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty && mounted) {
      final newPrincipal = Decimal.tryParse(result);
      if (newPrincipal != null && newPrincipal > Decimal.zero) {
        final loanProvider = Provider.of<LoanProvider>(context, listen: false);
        
        // Calculate new remaining amount
        final newRemaining = newPrincipal - loan.totalPaid;
        final actualRemaining = newRemaining > Decimal.zero ? newRemaining : Decimal.zero;
        
        final updatedLoan = loan.copyWith(
          principal: newPrincipal,
          totalAmount: newPrincipal, // For weekly loans, total = principal
          remainingAmount: actualRemaining,
          updatedAt: DateTime.now(),
        );
        
        final success = await loanProvider.updateLoan(updatedLoan);
        await _loadData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success ? 'Principal amount updated to ₹$result' : 'Failed to update'),
              backgroundColor: success ? Colors.green : Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _showEditInterestDialog(Loan loan) async {
    final controller = TextEditingController(
      text: loan.monthlyInterestAmount?.toStringAsFixed(0) ?? '0',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Monthly Interest'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Principal: ₹${loan.principal.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Monthly Interest Amount',
                prefixText: '₹ ',
                hintText: 'Enter monthly interest',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty && mounted) {
      final newInterest = Decimal.tryParse(result);
      if (newInterest != null && newInterest >= Decimal.zero) {
        final loanProvider = Provider.of<LoanProvider>(context, listen: false);
        
        final updatedLoan = loan.copyWith(
          monthlyInterestAmount: newInterest,
          updatedAt: DateTime.now(),
        );
        
        final success = await loanProvider.updateLoan(updatedLoan);
        await _loadData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success ? 'Monthly interest updated to ₹$result' : 'Failed to update'),
              backgroundColor: success ? Colors.green : Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _showEditBookNoDialog(Loan loan) async {
    final controller = TextEditingController(text: loan.bookNo ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Book Number'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Book No',
            hintText: 'Enter book number',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (result != null && mounted) {
      final loanProvider = Provider.of<LoanProvider>(context, listen: false);
      final updatedLoan = loan.copyWith(
        bookNo: result.isEmpty ? null : result,
        updatedAt: DateTime.now(),
      );
      await loanProvider.updateLoan(updatedLoan);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Book number updated'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _showEditLoanDateDialog(Loan loan) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: loan.loanDate,
      firstDate: DateTime(2000), // Allow any past date
      lastDate: DateTime(2100), // Allow any future date
    );
    
    if (picked != null && mounted) {
      final loanProvider = Provider.of<LoanProvider>(context, listen: false);
      final updatedLoan = loan.copyWith(
        loanDate: picked,
        updatedAt: DateTime.now(),
      );
      await loanProvider.updateLoan(updatedLoan);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loan date updated'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _deleteCustomer() async {
    final customerProvider =
        Provider.of<CustomerProvider>(context, listen: false);
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);

    // Check if customer has multiple loans
    if (_customerLoans.length > 1) {
      // Show loan selection dialog
      await _showLoanSelectionForDeletion(customerProvider, loanProvider);
    } else {
      // Single loan or no loans - use simple confirmation
      await _showSimpleDeleteConfirmation(customerProvider, loanProvider);
    }
  }

  Future<void> _showSimpleDeleteConfirmation(
      CustomerProvider customerProvider, LoanProvider loanProvider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text(
          _customerLoans.isEmpty
              ? 'Are you sure you want to delete this customer?\n\nThis action cannot be undone.'
              : 'Are you sure you want to delete this customer?\n\n'
                  'This will also delete their loan and payment records.\n\n'
                  'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _performCustomerDeletion(customerProvider, loanProvider);
    }
  }

  Future<void> _showLoanSelectionForDeletion(
      CustomerProvider customerProvider, LoanProvider loanProvider) async {
    final selectedLoanIds = <int>{};
    bool deleteCustomerToo = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Delete Loans'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This customer has ${_customerLoans.length} loans. Select which loan(s) to delete:',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  // Loan list with checkboxes
                  ...(_customerLoans.map((loan) {
                    final isMonthly = loan.isMonthlyInterest;
                    final isSelected = selectedLoanIds.contains(loan.id);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selectedLoanIds.add(loan.id!);
                          } else {
                            selectedLoanIds.remove(loan.id);
                          }
                          // Auto-check delete customer if all loans selected
                          if (selectedLoanIds.length == _customerLoans.length) {
                            deleteCustomerToo = true;
                          }
                        });
                      },
                      title: Text(
                        '${isMonthly ? "Monthly" : "Weekly"} ${loan.bookNo != null && loan.bookNo!.isNotEmpty ? "Book: ${loan.bookNo}" : "Loan"}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Principal: ₹${loan.principal.toStringAsFixed(0)} • Outstanding: ₹${loan.remainingAmount.toStringAsFixed(0)}',
                      ),
                      secondary: Container(
                        width: 8,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isMonthly ? Colors.orange : AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                    );
                  })),
                  const Divider(height: 24),
                  // Delete customer option
                  CheckboxListTile(
                    value: deleteCustomerToo,
                    onChanged: (value) {
                      setDialogState(() {
                        deleteCustomerToo = value ?? false;
                        if (deleteCustomerToo) {
                          // Select all loans when deleting customer
                          selectedLoanIds.clear();
                          for (var loan in _customerLoans) {
                            selectedLoanIds.add(loan.id!);
                          }
                        }
                      });
                    },
                    title: const Text(
                      'Delete customer too',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Remove customer and all their data'),
                    secondary: const Icon(Icons.person_remove, color: AppColors.error),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (selectedLoanIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, color: AppColors.error, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This will permanently delete ${selectedLoanIds.length} loan(s) and their payment records.',
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedLoanIds.isEmpty
                    ? null
                    : () => Navigator.of(dialogContext).pop({
                          'loanIds': selectedLoanIds.toList(),
                          'deleteCustomer': deleteCustomerToo,
                        }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                child: const Text('Delete Selected'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final loanIds = result['loanIds'] as List<int>;
      final shouldDeleteCustomer = result['deleteCustomer'] as bool;

      try {
        if (shouldDeleteCustomer) {
          // Delete customer (which cascades to delete all loans)
          await customerProvider.deleteCustomer(widget.customerId);
        } else {
          // Delete only selected loans
          for (final loanId in loanIds) {
            await loanProvider.deleteLoan(loanId, permanentDelete: true);
          }
        }

        await loanProvider.loadLoans();
        await loanProvider.loadLoansWithCustomers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                shouldDeleteCustomer
                    ? 'Customer deleted successfully'
                    : '${loanIds.length} loan(s) deleted successfully',
              ),
              backgroundColor: AppColors.success,
            ),
          );
          if (shouldDeleteCustomer) {
            Navigator.of(context).pop();
          } else {
            await _loadData(); // Refresh the screen
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _performCustomerDeletion(
      CustomerProvider customerProvider, LoanProvider loanProvider) async {
    try {
      await customerProvider.deleteCustomer(widget.customerId);

      // Refresh loan data to remove deleted customer's loans from all screens
      await loanProvider.loadLoans();
      await loanProvider.loadLoansWithCustomers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer deleted successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting customer: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_customer == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Customer Not Found'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('Customer not found'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_customer!.name),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _showEditSelectionDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteCustomer,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Payments'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildPaymentsTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Customer Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          _customer!.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _customer!.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _customer!.allPhoneNumbers,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Contact Information
                  _buildInfoSection(
                    'Contact Information',
                    [
                      _buildInfoRow(
                          Icons.phone, 'Phone', _customer!.allPhoneNumbers),
                      if (_customer!.address != null)
                        _buildInfoRow(
                            Icons.location_on, 'Address', _customer!.address!),
                      if (_customer!.bookNo != null)
                        _buildInfoRow(
                            Icons.menu_book, 'Book No', _customer!.bookNo!),
                    ],
                  ),

                  // Location Map Section - Always show with update option
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            children: [
                              const Icon(Icons.map,
                                  color: AppColors.primary, size: 20),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Customer Location',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => _updateCustomerLocation(),
                                icon: Icon(
                                  _customer!.hasLocation ? Icons.edit_location_alt : Icons.add_location_alt,
                                  size: 18,
                                ),
                                label: Text(_customer!.hasLocation ? 'Update' : 'Add'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_customer!.hasLocation)
                          SizedBox(
                            height: 180,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(12),
                                bottomRight: Radius.circular(12),
                              ),
                              child: LocationPickerWidget(
                                latitude: _customer!.latitude,
                                longitude: _customer!.longitude,
                                customerName: _customer!.name,
                                isReadOnly: true,
                                showDirectionsButton: true,
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Container(
                              height: 100,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.location_off, color: Colors.grey.shade400, size: 32),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No location saved',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Account Information
                  _buildInfoSection(
                    'Account Information',
                    [
                      _buildInfoRow(
                        Icons.account_balance,
                        'Total Loans',
                        _customerLoans.length.toString(),
                      ),
                      _buildInfoRow(
                        Icons.attach_money,
                        'Active Loans',
                        _customerLoans
                            .where((l) => l.status == LoanStatus.active)
                            .length
                            .toString(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Individual Loans Section - Each loan shown separately
          if (_customerLoans.isNotEmpty) ...[
            ..._customerLoans.map((loan) => _buildIndividualLoanCard(loan)),
            const SizedBox(height: 16),
          ],


        ],
      ),
    );
  }

  Widget _buildPaymentsTab() {
    if (_customerLoans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.payment_outlined,
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
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _customerLoans.length,
      itemBuilder: (context, index) {
        final loan = _customerLoans[index];
        return _buildLoanPaymentSection(loan);
      },
    );
  }

  Widget _buildLoanPaymentSection(Loan loan) {
    final isMonthly = loan.isMonthlyInterest;
    final outstanding = loan.remainingAmount;
    final isCompleted =
        loan.status == LoanStatus.closed || loan.status == LoanStatus.completed;
    final loanColor = isMonthly ? Colors.orange : AppColors.primary;

    // Sort payments by date (newest first)
    final sortedPayments = List<Payment>.from(loan.payments)
      ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: loanColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Loan Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: loanColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: loanColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isMonthly ? 'Monthly Interest' : 'Weekly EMI',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: loanColor,
                            ),
                          ),
                        ),
                        if (loan.bookNo != null && loan.bookNo!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.menu_book, size: 12, color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  loan.bookNo!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Loan Start Date - placed between book/status
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today, size: 10, color: Colors.purple.shade700),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('dd/MM/yy').format(loan.loanDate),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.purple.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.blue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isCompleted ? 'Completed' : 'Active',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isCompleted ? Colors.green : Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Amount summary for THIS loan only
                Row(
                  children: [
                    Expanded(
                      child: _buildLoanAmountBox(
                        'Principal',
                        '₹${loan.principal.toStringAsFixed(0)}',
                        AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildLoanAmountBox(
                        'Paid',
                        '₹${loan.totalPaid.toStringAsFixed(0)}',
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildLoanAmountBox(
                        'Outstanding',
                        '₹${outstanding.toStringAsFixed(0)}',
                        outstanding > Decimal.zero ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
                // Collect payment button for this specific loan
                if (!isCompleted && outstanding > Decimal.zero) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _navigateToPaymentCollection(loan),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Collect Payment for this Loan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: loanColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Payments for THIS loan only
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long,
                        size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Payment History (${sortedPayments.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                if (sortedPayments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No payments yet for this loan',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                else
                  ...sortedPayments
                      .map((payment) => _buildPaymentItem(payment, loan.id!)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentItem(Payment payment, int loanId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Rupee Icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Center(
              child: Text(
                '₹',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Amount and Date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '₹${payment.amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getPaymentMethodColor(payment.paymentMethod)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _getPaymentMethodLabel(payment.paymentMethod),
                        style: TextStyle(
                          fontSize: 10,
                          color: _getPaymentMethodColor(payment.paymentMethod),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a')
                      .format(payment.paymentDate),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
                ),
                // Display payment notes if available
                if (payment.notes != null && payment.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.note, size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          payment.notes!,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Edit & Delete
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => _showEditPaymentDialog(payment, loanId),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.primary),
                ),
              ),
              InkWell(
                onTap: () => _showDeletePaymentDialog(payment, loanId),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child:
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIndividualLoanCard(Loan loan) {
    final isMonthly = loan.isMonthlyInterest;
    final outstanding = loan.remainingAmount;
    final isCompleted =
        loan.status == LoanStatus.closed || loan.status == LoanStatus.completed;
    final statusColor = isCompleted
        ? AppColors.success
        : loan.status == LoanStatus.overdue
            ? AppColors.error
            : AppColors.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: isMonthly ? Colors.orange : AppColors.primary,
              width: 4,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Loan Header
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Left badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isMonthly ? Colors.orange : AppColors.primary)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isMonthly ? 'Monthly Interest' : 'Weekly EMI',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color:
                                isMonthly ? Colors.orange : AppColors.primary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isCompleted
                              ? 'Completed'
                              : loan.status == LoanStatus.overdue
                                  ? 'Overdue'
                                  : 'Active',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Book No and Loan Date display
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (loan.bookNo != null && loan.bookNo!.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.menu_book, size: 12, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              'Book: ${loan.bookNo}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 2),
                      Text(
                        'Started: ${loan.loanDate.day}/${loan.loanDate.month}/${loan.loanDate.year}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Amount Details - Separate boxes for each loan
              Row(
                children: [
                  Expanded(
                    child: _buildLoanAmountBox(
                      'Principal',
                      '₹${loan.principal.toStringAsFixed(0)}',
                      AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildLoanAmountBox(
                      'Paid',
                      '₹${loan.totalPaid.toStringAsFixed(0)}',
                      AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildLoanAmountBox(
                      'Outstanding',
                      '₹${outstanding.toStringAsFixed(0)}',
                      outstanding > Decimal.zero
                          ? AppColors.error
                          : AppColors.success,
                    ),
                  ),
                ],
              ),

              if (isMonthly && loan.monthlyInterestAmount != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.percent, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        'Monthly Interest: ₹${loan.monthlyInterestAmount!.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Collect Payment Button for this specific loan
              if (!isCompleted)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _navigateToPaymentCollection(loan),
                    icon: const Icon(Icons.payment, size: 16),
                    label: const Text('Collect Payment'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: statusColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoanAmountBox(String label, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
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

  IconData _getStatusIcon(LoanStatus status) {
    switch (status) {
      case LoanStatus.active:
        return Icons.check_circle;
      case LoanStatus.closed:
        return Icons.check_circle_outline;
      case LoanStatus.overdue:
        return Icons.warning;
      default:
        return Icons.schedule;
    }
  }

  void _navigateToPaymentCollection(Loan loan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentCollectionScreenNew(loan: loan),
      ),
    );

    // Refresh data after payment collection
    await _loadData();
  }

  Future<void> _showAddPaymentDialog(Loan loan) async {
    final TextEditingController amountController = TextEditingController();
    final TextEditingController notesController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Outstanding Amount: ₹${loan.remainingAmount.toStringAsFixed(0)}',
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Payment Amount',
                border: OutlineInputBorder(),
                prefixText: '₹ ',
              ),
              keyboardType: TextInputType.number,
              maxLength: 12,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount != null && amount > 0) {
                Navigator.of(context).pop();
                await _addPayment(loan, amount, notesController.text);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid amount')),
                );
              }
            },
            child: const Text('Add Payment'),
          ),
        ],
      ),
    );
  }

  Future<void> _addPayment(Loan loan, double amount, String? notes) async {
    // Get provider reference BEFORE any async operations
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);

    try {
      final success = await loanProvider.addPayment(
        loan.id!,
        Decimal.parse(amount.toString()),
        DateTime.now(),
        notes: notes?.isNotEmpty == true ? notes : null,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment added successfully'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Refresh the customer data to show updated payment
          _loadData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(loanProvider.errorMessage ?? 'Failed to save payment'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding payment: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showPaymentNotes(String notes) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Notes'),
        content: Text(notes),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showEditPaymentDialog(Payment payment, int loanId) {
    final amountController =
        TextEditingController(text: payment.amount.toString());
    final notesController = TextEditingController(text: payment.notes ?? '');
    DateTime selectedDate = payment.paymentDate;
    PaymentMethod selectedMethod = payment.paymentMethod;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Amount
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Payment Amount *',
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 16),

                // Date Picker
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000), // Allow any past date
                      lastDate: DateTime(2100), // Allow any future date
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today),
                        const SizedBox(width: 12),
                        Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Payment Method
                DropdownButtonFormField<PaymentMethod>(
                  initialValue: selectedMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    prefixIcon: Icon(Icons.payment),
                  ),
                  items: PaymentMethod.values.map((method) {
                    return DropdownMenuItem(
                      value: method,
                      child: Text(_getPaymentMethodLabel(method)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedMethod = value);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Notes
                TextFormField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                    prefixIcon: Icon(Icons.note_outlined),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = Decimal.tryParse(amountController.text);
                if (amount == null || amount <= Decimal.zero) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Please enter a valid amount')),
                  );
                  return;
                }

                final updatedPayment = payment.copyWith(
                  amount: amount,
                  paymentDate: selectedDate,
                  paymentMethod: selectedMethod,
                  notes: notesController.text.trim().isEmpty
                      ? null
                      : notesController.text.trim(),
                  updatedAt: DateTime.now(),
                );

                // Capture context-dependent references before async
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final loanProvider =
                    Provider.of<LoanProvider>(context, listen: false);
                
                Navigator.pop(dialogContext);

                final success =
                    await loanProvider.updatePayment(updatedPayment);

                if (success && mounted) {
                  await _loadData(); // Refresh the screen
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Payment updated successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(
                          'Failed to update payment: ${loanProvider.errorMessage}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeletePaymentDialog(Payment payment, int loanId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this payment?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${payment.amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('dd MMM yyyy').format(payment.paymentDate),
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ This will recalculate the loan outstanding amount.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              // Capture context-dependent references before async
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final loanProvider =
                  Provider.of<LoanProvider>(context, listen: false);
                  
              Navigator.pop(dialogContext);

              final success = await loanProvider.deletePayment(payment.id!);

              if (success && mounted) {
                await _loadData(); // Refresh the screen
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Payment deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else if (mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(
                        'Failed to delete payment: ${loanProvider.errorMessage}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _getPaymentMethodLabel(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.bank:
        return 'Bank';
      case PaymentMethod.other:
        return 'Other';
    }
  }

  Color _getPaymentMethodColor(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return Colors.green;
      case PaymentMethod.upi:
        return Colors.purple;
      case PaymentMethod.bank:
        return Colors.blue;
      case PaymentMethod.other:
        return Colors.orange;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
