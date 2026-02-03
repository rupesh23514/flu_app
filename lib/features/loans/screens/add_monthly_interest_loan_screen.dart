import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:decimal/decimal.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/customer_group.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/widgets/location_picker_widget.dart';
import '../../customer_management/providers/customer_provider.dart';
import '../../loan_management/providers/loan_provider.dart';

class AddMonthlyInterestLoanScreen extends StatefulWidget {
  final bool isNewCustomer;
  final Customer? existingCustomer;

  const AddMonthlyInterestLoanScreen({
    super.key,
    required this.isNewCustomer,
    this.existingCustomer,
  });

  @override
  State<AddMonthlyInterestLoanScreen> createState() => _AddMonthlyInterestLoanScreenState();
}

class _AddMonthlyInterestLoanScreenState extends State<AddMonthlyInterestLoanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  
  // Customer fields
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _alternatePhoneController = TextEditingController();
  final _bookNoController = TextEditingController();
  final _addressController = TextEditingController();
  
  // Loan fields
  final _principalController = TextEditingController();
  final _monthlyInterestController = TextEditingController();
  final _loanBookNoController = TextEditingController();  // Book number for the loan
  
  Customer? _selectedCustomer;
  DateTime _selectedLoanDate = DateTime.now();
  bool _isLoading = false;
  bool _showAlternatePhone = false;
  final List<int> _selectedGroupIds = [];  // Multi-group selection
  List<CustomerGroup> _availableGroups = [];
  
  // Location fields
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    if (widget.existingCustomer != null) {
      _selectedCustomer = widget.existingCustomer;
    }
    _loadCustomerGroups();
  }

  Future<void> _loadCustomerGroups() async {
    try {
      final groups = await DatabaseService.instance.getAllCustomerGroups();
      if (mounted) {
        setState(() {
          _availableGroups = groups;
        });
      }
    } catch (e) {
      debugPrint('Error loading groups: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _alternatePhoneController.dispose();
    _bookNoController.dispose();
    _addressController.dispose();
    _principalController.dispose();
    _monthlyInterestController.dispose();
    _loanBookNoController.dispose();
    super.dispose();
  }

  Future<void> _selectLoanDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedLoanDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select Loan Start Date',
    );
    if (picked != null && picked != _selectedLoanDate) {
      setState(() {
        _selectedLoanDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNewCustomer ? 'New Monthly Interest Loan' : 'Monthly Interest Loan'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (!widget.isNewCustomer && _selectedCustomer != null)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedCustomer = null;
                });
              },
              icon: const Icon(Icons.person_off, size: 18, color: Colors.white),
              label: const Text('Change', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            // Info Card
            _buildInfoCard(),
            const SizedBox(height: 20),
            
            // Customer Section
            if (widget.isNewCustomer)
              _buildNewCustomerSection()
            else if (_selectedCustomer == null)
              _buildSelectCustomerSection()
            else
              _buildSelectedCustomerCard(),
            
            const SizedBox(height: 24),
            
            // Loan Details Section
            _buildSectionHeader('Loan Details', Icons.account_balance),
            const SizedBox(height: 16),
            _buildLoanDetailsSection(),
            
            const SizedBox(height: 24),
            
            // Add to Group Section (for both new and existing customers)
            _buildAddToGroupSection(),
            const SizedBox(height: 24),
            
            // Submit Button
            _buildSubmitButton(),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.orange.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.percent,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly Interest Loan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Enter principal & monthly interest manually. Interest collected monthly, principal repaid at end.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildNewCustomerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Customer Details', Icons.person),
        const SizedBox(height: 16),
        
        // Name
        TextFormField(
          controller: _nameController,
          maxLength: 50,
          decoration: const InputDecoration(
            labelText: 'Full Name *',
            prefixIcon: Icon(Icons.person_outline),
            hintText: 'Enter customer name',
            counterText: '',
          ),
          textCapitalization: TextCapitalization.words,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter customer name';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        
        // Phone
        TextFormField(
          controller: _phoneController,
          decoration: const InputDecoration(
            labelText: 'Phone Number *',
            prefixIcon: Icon(Icons.phone_outlined),
            hintText: '10-digit mobile number',
          ),
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter phone number';
            }
            if (value.length != 10) {
              return 'Enter valid 10-digit number';
            }
            return null;
          },
        ),
        
        // Add Another Number Button / Alternate Phone
        if (!_showAlternatePhone)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _showAlternatePhone = true;
                });
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Another Number'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              ),
            ),
          ),
        
        if (_showAlternatePhone) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _alternatePhoneController,
            decoration: InputDecoration(
              labelText: 'Alternate Phone Number',
              prefixIcon: const Icon(Icons.phone_outlined),
              hintText: '10-digit mobile number',
              suffixIcon: IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _showAlternatePhone = false;
                    _alternatePhoneController.clear();
                  });
                },
              ),
            ),
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            validator: (value) {
              if (value != null && value.isNotEmpty && value.length != 10) {
                return 'Enter valid 10-digit number';
              }
              return null;
            },
          ),
        ],
        const SizedBox(height: 16),
        
        // Book No (Optional)
        TextFormField(
          controller: _bookNoController,
          maxLength: 30,
          decoration: const InputDecoration(
            labelText: 'Book No (Optional)',
            prefixIcon: Icon(Icons.menu_book_outlined),
            hintText: 'Enter book number',
            counterText: '',
          ),
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 16),
        
        // Address
        TextFormField(
          controller: _addressController,
          maxLength: 150,
          decoration: const InputDecoration(
            labelText: 'Address',
            prefixIcon: Icon(Icons.location_on_outlined),
            hintText: 'Enter address',
            counterText: '',
          ),
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 20),
        
        // Location Picker Section
        _buildLocationPickerSection(),
      ],
    );
  }

  /// Build Location Picker Section with Map UI and Full Screen Button
  Widget _buildLocationPickerSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.map_outlined,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Customer Location',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Tap map or use GPS to set location',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Map Widget
            LocationPickerWidget(
              latitude: _latitude,
              longitude: _longitude,
              height: 200,
              onLocationSelected: (lat, lng) {
                setState(() {
                  _latitude = lat;
                  _longitude = lng;
                });
              },
            ),
            
            // Location info display
            if (_latitude != null && _longitude != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.green.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        setState(() {
                          _latitude = null;
                          _longitude = null;
                        });
                      },
                      tooltip: 'Clear location',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
            
            // Full screen picker button
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push<Map<String, double>>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LocationPickerScreen(
                        initialLatitude: _latitude,
                        initialLongitude: _longitude,
                        customerName: _nameController.text.trim(),
                      ),
                    ),
                  );
                  if (result != null && mounted) {
                    setState(() {
                      _latitude = result['latitude'];
                      _longitude = result['longitude'];
                    });
                  }
                },
                icon: const Icon(Icons.fullscreen),
                label: const Text('Open Full Screen Map'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectCustomerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Select Customer', Icons.person_search),
        const SizedBox(height: 16),
        
        Consumer<CustomerProvider>(
          builder: (context, provider, _) {
            final customers = provider.customers;
            
            if (customers.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_off_outlined,
                        size: 48,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No customers found',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add a new customer first',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            
            return Column(
              children: [
                // Customer list
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: customers.length,
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.shade100,
                            child: Text(
                              customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(customer.name),
                          subtitle: Text(customer.phoneNumber),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            setState(() {
                              _selectedCustomer = customer;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSelectedCustomerCard() {
    if (_selectedCustomer == null) return const SizedBox.shrink();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.orange.shade100,
              radius: 28,
              child: Text(
                _selectedCustomer!.name.isNotEmpty 
                    ? _selectedCustomer!.name[0].toUpperCase() 
                    : '?',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedCustomer!.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        _selectedCustomer!.phoneNumber,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.check_circle,
              color: Colors.orange.shade600,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoanDetailsSection() {
    return Column(
      children: [
        // Principal Amount
        TextFormField(
          controller: _principalController,
          decoration: const InputDecoration(
            labelText: 'Principal Amount *',
            prefixIcon: Icon(Icons.currency_rupee),
            hintText: 'Enter loan amount',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter principal amount';
            }
            final amount = double.tryParse(value) ?? 0;
            if (amount <= 0) {
              return 'Enter valid amount';
            }
            if (amount > 999999999) {
              return 'Amount too large';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        
        // Monthly Interest Amount
        TextFormField(
          controller: _monthlyInterestController,
          decoration: InputDecoration(
            labelText: 'Monthly Interest Amount *',
            prefixIcon: const Icon(Icons.percent),
            hintText: 'Enter monthly interest',
            filled: true,
            fillColor: Colors.orange.shade50,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter monthly interest amount';
            }
            final amount = double.tryParse(value) ?? 0;
            if (amount <= 0) {
              return 'Enter valid interest amount';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        
        // Loan Date Picker
        InkWell(
          onTap: _selectLoanDate,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Loan Start Date *',
              prefixIcon: Icon(Icons.calendar_today),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedLoanDate.day}/${_selectedLoanDate.month}/${_selectedLoanDate.year}',
                  style: const TextStyle(fontSize: 16),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        
        // Book No field (for tracking loans)
        TextFormField(
          controller: _loanBookNoController,
          maxLength: 30,
          decoration: const InputDecoration(
            labelText: 'Book No (Optional)',
            prefixIcon: Icon(Icons.menu_book_outlined),
            hintText: 'Enter book number for this loan',
            counterText: '',
          ),
          keyboardType: TextInputType.text,
        ),
      ],
    );
  }

  Widget _buildAddToGroupSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.group_add,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add to Group',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Assign customer to a group (Optional)',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_availableGroups.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.info, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No groups available. Create a group from Customer Groups screen.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: _availableGroups.map((group) {
                  final isSelected = _selectedGroupIds.contains(group.id);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedGroupIds.add(group.id!);
                        } else {
                          _selectedGroupIds.remove(group.id);
                        }
                      });
                    },
                    title: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: group.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(group.name),
                      ],
                    ),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    final canSubmit = widget.isNewCustomer || _selectedCustomer != null;
    
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.shade600,
          foregroundColor: Colors.white,
        ),
        onPressed: canSubmit && !_isLoading ? _submitLoan : null,
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Create Monthly Interest Loan',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Future<void> _submitLoan() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    if (!widget.isNewCustomer && _selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a customer'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    // Get provider references BEFORE any async operations
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      int customerId;
      final now = DateTime.now();
      
      if (widget.isNewCustomer) {
        // Create new customer
        final newCustomer = Customer(
          name: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          alternatePhone: _alternatePhoneController.text.trim().isEmpty ? null : _alternatePhoneController.text.trim(),
          bookNo: _bookNoController.text.trim().isEmpty ? null : _bookNoController.text.trim(),
          address: _addressController.text.trim(),
          latitude: _latitude,
          longitude: _longitude,
          createdAt: now,
          updatedAt: now,
        );
        
        // Use addCustomerAndGetId to directly get the customer ID
        final createdId = await customerProvider.addCustomerAndGetId(newCustomer);
        if (createdId == null) {
          throw Exception(customerProvider.errorMessage ?? 'Failed to create customer');
        }
        customerId = createdId;
        
        // Assign customer to groups if selected
        if (_selectedGroupIds.isNotEmpty) {
          await DatabaseService.instance.addCustomerToMultipleGroups(customerId, _selectedGroupIds);
        }
      } else {
        customerId = _selectedCustomer!.id!;
        
        // Assign existing customer to groups if selected
        if (_selectedGroupIds.isNotEmpty) {
          await DatabaseService.instance.addCustomerToMultipleGroups(customerId, _selectedGroupIds);
        }
      }
      
      // Create monthly interest loan
      if (mounted) {
        // Default tenure of 12 months for monthly interest loans
        const tenure = 12;
        
        // Calculate due date - tenure is in months
        final dueDate = DateTime(
          _selectedLoanDate.year,
          _selectedLoanDate.month + tenure,
          _selectedLoanDate.day,
        );
        
        // Safe parse with validation
        final parsedPrincipal = double.tryParse(_principalController.text) ?? 0.0;
        final parsedMonthlyInterest = double.tryParse(_monthlyInterestController.text) ?? 0.0;
        final principalDecimal = Decimal.parse(parsedPrincipal.toStringAsFixed(0));
        final monthlyInterestDecimal = Decimal.parse(parsedMonthlyInterest.toStringAsFixed(0));
        
        // Determine initial loan status based on loan date
        LoanStatus initialStatus = LoanStatus.active;
        final daysSinceLoan = now.difference(_selectedLoanDate).inDays;
        final monthsElapsed = daysSinceLoan ~/ 30;
        if (monthsElapsed > 0) {
          // Loan date is more than a month ago, may need interest collection
          initialStatus = LoanStatus.overdue;
        }
        
        // Get book number for loan
        final loanBookNo = _loanBookNoController.text.trim().isEmpty 
            ? null 
            : _loanBookNoController.text.trim();
        
        final loan = Loan(
          customerId: customerId,
          principal: principalDecimal,
          bookNo: loanBookNo,
          loanDate: _selectedLoanDate,
          dueDate: dueDate,
          totalAmount: principalDecimal, // Only principal for monthly interest loans
          remainingAmount: principalDecimal,
          status: initialStatus,
          createdAt: now,
          updatedAt: now,
          tenure: tenure,
          notes: null,
          loanType: LoanType.monthlyInterest,
          monthlyInterestAmount: monthlyInterestDecimal,
          totalInterestCollected: Decimal.zero,
        );
        
        final success = await loanProvider.addLoan(loan);
        
        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Monthly interest loan created successfully'),
                backgroundColor: Colors.orange.shade600,
                behavior: SnackBarBehavior.floating,
              ),
            );
            Navigator.pop(context, true); // Return true to indicate success
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${loanProvider.errorMessage ?? "Failed to create loan"}'),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
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
}
