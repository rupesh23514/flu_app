import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/models/customer.dart';
import '../providers/loan_provider.dart';
import '../../customer_management/providers/customer_provider.dart';

class PaymentCollectionScreen extends StatefulWidget {
  final int? loanId;
  
  const PaymentCollectionScreen({super.key, this.loanId});

  @override
  State<PaymentCollectionScreen> createState() => _PaymentCollectionScreenState();
}

class _PaymentCollectionScreenState extends State<PaymentCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _remarksController = TextEditingController();
  
  Loan? _selectedLoan;
  Customer? _selectedCustomer;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Defer loading to after the first frame to avoid calling notifyListeners during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    
    await loanProvider.loadLoans();
    await customerProvider.loadCustomers();
    
    // Handle route arguments for loan preselection
    final loanId = widget.loanId ?? (mounted ? ModalRoute.of(context)?.settings.arguments as int? : null);
    if (loanId != null && mounted) {
      final loan = await loanProvider.getLoanById(loanId);
      if (loan != null && mounted) {
        final customer = await customerProvider.getCustomerById(loan.customerId);
        if (mounted) {
          setState(() {
            _selectedLoan = loan;
            _selectedCustomer = customer;
          });
        }
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000), // Allow any past date
      lastDate: DateTime(2100), // Allow any future date
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate() || _selectedLoan == null) return;

    // Get provider references BEFORE async operations
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);

    setState(() {
      _isLoading = true;
    });

    try {
      // Safe parse with fallback to zero
      final parsedAmount = double.tryParse(_amountController.text) ?? 0.0;
      final amount = Decimal.parse(parsedAmount.toStringAsFixed(0));
      
      // Safe null check for loan id
      if (_selectedLoan?.id == null) {
        throw Exception('Loan ID is null');
      }
      
      final success = await loanProvider.addPayment(_selectedLoan!.id!, amount, _selectedDate, notes: _remarksController.text.trim());

      if (success) {
        // Refresh all providers to update UI
        await loanProvider.loadLoans();
        await loanProvider.loadDashboardStats();
        await customerProvider.loadCustomers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment recorded successfully'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          
          // Clear form
          _amountController.clear();
          _remarksController.clear();
          setState(() {
            _selectedDate = DateTime.now();
          });
          
          // Navigate back if this was for a specific loan
          if (widget.loanId != null) {
            Navigator.of(context).pop();
          }
        }
      } else {
        // Payment failed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loanProvider.errorMessage ?? 'Failed to save payment'),
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
            content: Text('Error recording payment: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Collection'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Consumer2<LoanProvider, CustomerProvider>(
        builder: (context, loanProvider, customerProvider, child) {
          if (loanProvider.isLoading || customerProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Loan Selection Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Loan Details',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Customer/Loan Selector
                          if (_selectedLoan == null) ...[
                            Builder(
                              builder: (context) {
                                final activeLoans = loanProvider.loans
                                    .where((loan) => loan.status == LoanStatus.active)
                                    .toList();
                                
                                if (activeLoans.isEmpty) {
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.warning.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                                    ),
                                    child: const Column(
                                      children: [
                                        Icon(Icons.info_outline, color: AppColors.warning, size: 32),
                                        SizedBox(height: 8),
                                        Text(
                                          'No active loans found',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Create a loan first from the Loans tab',
                                          style: TextStyle(color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                
                                return DropdownButtonFormField<Loan>(
                                  decoration: InputDecoration(
                                    labelText: 'Select Loan',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  isExpanded: true,
                                  items: activeLoans.map((loan) {
                                    final customer = customerProvider.getLoadedCustomerById(loan.customerId);
                                    return DropdownMenuItem<Loan>(
                                      value: loan,
                                      child: Text(
                                        '${customer?.name ?? 'Unknown'} - ₹${loan.principal}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (loan) {
                                    if (loan != null) {
                                      final customer = customerProvider.getLoadedCustomerById(loan.customerId);
                                      setState(() {
                                        _selectedLoan = loan;
                                        _selectedCustomer = customer;
                                      });
                                    }
                                  },
                                  validator: (value) {
                                    if (value == null) {
                                      return 'Please select a loan';
                                    }
                                    return null;
                                  },
                                );
                              },
                            ),
                          ] else ...[
                            // Display selected loan info
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedCustomer?.name ?? 'Unknown Customer',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text('Principal: ₹${_selectedLoan!.principal}'),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text('Total Amount: ₹${_selectedLoan!.totalAmount}'),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text('Paid: ₹${_selectedLoan!.totalPaid}'),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text('Outstanding: ₹${_selectedLoan!.totalAmount - _selectedLoan!.totalPaid}'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (widget.loanId == null)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedLoan = null;
                                    _selectedCustomer = null;
                                  });
                                },
                                child: const Text('Change Loan'),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Payment Form Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payment Details',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Amount Field
                          TextFormField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Payment Amount',
                              prefixText: '₹ ',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter payment amount';
                              }
                              try {
                                final amount = Decimal.parse(value);
                                if (amount <= Decimal.zero) {
                                  return 'Amount must be greater than zero';
                                }
                                if (_selectedLoan != null) {
                                  final outstanding = _selectedLoan!.totalAmount - _selectedLoan!.totalPaid;
                                  if (amount > outstanding) {
                                    return 'Amount cannot exceed outstanding balance';
                                  }
                                }
                              } catch (e) {
                                return 'Please enter a valid amount';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          // Date Field
                          InkWell(
                            onTap: _selectDate,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Payment Date',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
                                  const Icon(Icons.calendar_today),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Remarks Field
                          TextFormField(
                            controller: _remarksController,
                            maxLines: 3,
                            maxLength: 100,
                            decoration: InputDecoration(
                              labelText: 'Remarks (Optional)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              counterText: '',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Record Payment',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _remarksController.dispose();
    super.dispose();
  }
}