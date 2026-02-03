import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/models/customer.dart';
import '../providers/loan_provider.dart';
import '../../customer_management/providers/customer_provider.dart';

class AddLoanScreen extends StatefulWidget {
  final int? customerId;
  
  const AddLoanScreen({super.key, this.customerId});

  @override
  State<AddLoanScreen> createState() => _AddLoanScreenState();
}

class _AddLoanScreenState extends State<AddLoanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _principalController = TextEditingController();
  final _interestRateController = TextEditingController(text: '2');
  final _tenureController = TextEditingController(text: '12');
  final _notesController = TextEditingController();
  
  Customer? _selectedCustomer;
  DateTime _loanDate = DateTime.now();
  InterestType _interestType = InterestType.simple;
  InterestPeriod _interestPeriod = InterestPeriod.monthly;
  bool _isLoading = false;
  
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    if (widget.customerId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
        final customer = customerProvider.getLoadedCustomerById(widget.customerId!);
        if (customer != null) {
          setState(() {
            _selectedCustomer = customer;
          });
        }
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _loanDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _loanDate = picked;
      });
    }
  }

  Future<void> _submitLoan() async {
    if (!_formKey.currentState!.validate() || _selectedCustomer == null) {
      if (_selectedCustomer == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a customer'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // Get provider reference BEFORE async operations
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);

    setState(() {
      _isLoading = true;
    });

    try {
      // Safe parse with validation
      final parsedPrincipal = double.tryParse(_principalController.text) ?? 0.0;
      final principal = Decimal.parse(parsedPrincipal.toStringAsFixed(0));
      // Interest rate parsing removed - not used in simple principal-based loans
      final tenure = int.tryParse(_tenureController.text) ?? 10;
      
      // Validate customer is selected
      if (_selectedCustomer?.id == null) {
        throw Exception('Customer not selected');
      }
      
      // Calculate due date based on tenure
      final dueDate = _loanDate.add(Duration(days: tenure * 30));
      
      final loan = Loan(
        customerId: _selectedCustomer!.id!,
        principal: principal,
        loanDate: _loanDate,
        dueDate: dueDate,
        totalAmount: principal, // Simple principal-based loan
        remainingAmount: principal,
        status: LoanStatus.active,
        tenure: tenure,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final success = await loanProvider.addLoan(loan);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Loan created successfully'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loanProvider.errorMessage ?? 'Failed to create loan'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating loan: $e'),
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
        title: const Text('Create New Loan'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Consumer<CustomerProvider>(
        builder: (context, customerProvider, child) {
          final customers = customerProvider.customers;
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer Selection
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customer Details',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          if (customers.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.person_add, color: AppColors.warning, size: 32),
                                  const SizedBox(height: 8),
                                  const Text('No customers found'),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pushNamed(context, '/add-borrower'),
                                    child: const Text('Add Customer First'),
                                  ),
                                ],
                              ),
                            )
                          else
                            DropdownButtonFormField<Customer>(
                              initialValue: _selectedCustomer,
                              decoration: InputDecoration(
                                labelText: 'Select Customer',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: const Icon(Icons.person),
                              ),
                              items: customers.map((customer) {
                                return DropdownMenuItem<Customer>(
                                  value: customer,
                                  child: Text('${customer.name} - ${customer.phoneNumber}'),
                                );
                              }).toList(),
                              onChanged: (customer) {
                                setState(() {
                                  _selectedCustomer = customer;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Loan Details
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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
                          
                          // Principal Amount
                          TextFormField(
                            controller: _principalController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(9),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Principal Amount',
                              prefixText: '₹ ',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              prefixIcon: const Icon(Icons.currency_rupee),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter principal amount';
                              }
                              if (Decimal.tryParse(value) == null) {
                                return 'Please enter a valid amount';
                              }
                              final amount = double.tryParse(value) ?? 0;
                              if (amount > 999999999) {
                                return 'Amount too large';
                              }
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Interest Rate and Tenure Row
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _interestRateController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Interest Rate (%)',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    prefixIcon: const Icon(Icons.percent),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _tenureController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(2),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'Tenure (weeks)',
                                    hintText: '1-99',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    prefixIcon: const Icon(Icons.calendar_month),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Required';
                                    }
                                    final weeks = int.tryParse(value) ?? 0;
                                    if (weeks < 1 || weeks > 99) {
                                      return '1-99';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Loan Date
                          InkWell(
                            onTap: _selectDate,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Loan Date',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: const Icon(Icons.calendar_today),
                                suffixIcon: const Icon(Icons.arrow_drop_down),
                              ),
                              child: Text(_dateFormat.format(_loanDate)),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Interest Type
                          DropdownButtonFormField<InterestType>(
                            initialValue: _interestType,
                            decoration: InputDecoration(
                              labelText: 'Interest Type',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              prefixIcon: const Icon(Icons.calculate),
                            ),
                            items: InterestType.values.map((type) {
                              return DropdownMenuItem<InterestType>(
                                value: type,
                                child: Text(type.name.toUpperCase()),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _interestType = value;
                                });
                              }
                            },
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Interest Period
                          DropdownButtonFormField<InterestPeriod>(
                            initialValue: _interestPeriod,
                            decoration: InputDecoration(
                              labelText: 'Interest Period',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              prefixIcon: const Icon(Icons.schedule),
                            ),
                            items: InterestPeriod.values.map((period) {
                              return DropdownMenuItem<InterestPeriod>(
                                value: period,
                                child: Text(period.name.toUpperCase()),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _interestPeriod = value;
                                });
                              }
                            },
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Notes
                          TextFormField(
                            controller: _notesController,
                            maxLines: 3,
                            maxLength: 200,
                            decoration: InputDecoration(
                              labelText: 'Notes (Optional)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              prefixIcon: const Icon(Icons.note),
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
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading || customers.isEmpty ? null : _submitLoan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Create Loan',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    _principalController.dispose();
    _interestRateController.dispose();
    _tenureController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}
