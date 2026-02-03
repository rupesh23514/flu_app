// ignore_for_file: unused_element
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

class AddLoanScreenNew extends StatefulWidget {
  final bool isNewCustomer;
  final Customer? existingCustomer;
  final bool showDailyOption;
  final String? paymentType; // 'weekly' or 'monthly' - if provided, hides payment type selection

  const AddLoanScreenNew({
    super.key,
    required this.isNewCustomer,
    this.existingCustomer,
    this.showDailyOption = true, // Set to false from customer page
    this.paymentType, // Pre-selected payment type from home screen
  });

  @override
  State<AddLoanScreenNew> createState() => _AddLoanScreenNewState();
}

class _AddLoanScreenNewState extends State<AddLoanScreenNew> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Customer fields
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _alternatePhoneController = TextEditingController();
  final _addressController = TextEditingController();

  // Loan fields
  final _principalController = TextEditingController();
  final _durationController = TextEditingController(text: '4');
  final _bookNoController = TextEditingController();  // Book number for the loan

  Customer? _selectedCustomer;
  String _paymentFrequency = 'weekly'; // daily, weekly, monthly
  DateTime _selectedLoanDate = DateTime.now();
  bool _isLoading = false;
  bool _showAlternatePhone = false;
  final List<int> _selectedGroupIds = [];  // Multi-group selection
  List<CustomerGroup> _availableGroups = [];
  
  // Location fields
  double? _customerLatitude;
  double? _customerLongitude;
  
  // Customer search
  String _customerSearchQuery = '';

  @override
  void initState() {
    super.initState();
    // Set payment frequency from parameter if provided
    if (widget.paymentType != null) {
      _paymentFrequency = widget.paymentType!;
    }
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
    _addressController.dispose();
    _principalController.dispose();
    _durationController.dispose();
    _bookNoController.dispose();
    super.dispose();
  }

  String _getPaymentCount() {
    final durationWeeks = int.tryParse(_durationController.text) ?? 1;
    int count;
    String unit;

    switch (_paymentFrequency) {
      case 'daily':
        count = durationWeeks * 7;
        unit = 'days';
        break;
      case 'weekly':
        count = durationWeeks;
        unit = 'weeks';
        break;
      default:
        count = (durationWeeks / 4).ceil();
        if (count < 1) count = 1;
        unit = 'months';
    }

    return '$count $unit';
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
        title: Text(widget.isNewCustomer ? 'New Customer Loan' : 'Add Loan'),
        actions: [
          if (!widget.isNewCustomer && _selectedCustomer != null)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedCustomer = null;
                });
              },
              icon: const Icon(Icons.person_off, size: 18),
              label: const Text('Change'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
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

  Widget _buildSelectCustomerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Select Customer', Icons.person_search),
        const SizedBox(height: 16),
        Consumer<CustomerProvider>(
          builder: (context, provider, _) {
            // Filter customers based on search query
            final allCustomers = provider.customers;
            final customers = _customerSearchQuery.isEmpty
                ? allCustomers
                : allCustomers.where((c) {
                    final query = _customerSearchQuery.toLowerCase();
                    return c.name.toLowerCase().contains(query) ||
                        c.phoneNumber.contains(query) ||
                        (c.alternatePhone?.contains(query) ?? false);
                  }).toList();

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
                // Search field
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search customer by name or phone',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _customerSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() => _customerSearchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (query) {
                    setState(() => _customerSearchQuery = query);
                  },
                ),
                const SizedBox(height: 12),

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
                            backgroundColor: AppColors.primaryLight,
                            child: Text(
                              customer.name.isNotEmpty
                                  ? customer.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(customer.name),
                          subtitle: Text(customer.phoneNumber),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
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
              backgroundColor: AppColors.primaryLight,
              radius: 28,
              child: Text(
                _selectedCustomer!.name.isNotEmpty
                    ? _selectedCustomer!.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: AppColors.primary,
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
                      const Icon(Icons.phone,
                          size: 14, color: AppColors.textSecondary),
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
            const Icon(
              Icons.check_circle,
              color: AppColors.success,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoanDetailsSection() {
    // Get duration label based on frequency
    String durationLabel;
    String durationHint;
    switch (_paymentFrequency) {
      case 'daily':
        durationLabel = 'Duration (Days) *';
        durationHint = '1-99';
        break;
      case 'monthly':
        durationLabel = 'Duration (Months) *';
        durationHint = '1-99';
        break;
      default:
        durationLabel = 'Duration (Weeks) *';
        durationHint = '1-99';
    }

    return Column(
      children: [
        // Payment Frequency Selection - Only show if payment type not pre-specified
        if (widget.paymentType == null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Payment Type *',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildFrequencyCard(
                        'Weekly',
                        'weekly',
                        Icons.calendar_view_week,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFrequencyCard(
                        'Monthly',
                        'monthly',
                        Icons.calendar_month,
                      ),
                    ),
                    // Only show Daily option if enabled (hidden for existing customer loans)
                    if (widget.showDailyOption) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFrequencyCard(
                          'Daily',
                          'daily',
                          Icons.today,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        if (widget.paymentType == null) const SizedBox(height: 20),

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
        const SizedBox(height: 16),

        // Duration Field (label changes based on frequency)
        TextFormField(
          controller: _durationController,
          decoration: InputDecoration(
            labelText: durationLabel,
            prefixIcon: const Icon(Icons.calendar_today),
            hintText: durationHint,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Required';
            }
            final duration = int.tryParse(value) ?? 0;
            if (duration < 1 || duration > 99) {
              return '1-99 required';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Loan Date Picker
        InkWell(
          onTap: _selectLoanDate,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Loan Start Date *',
              prefixIcon: Icon(Icons.calendar_month),
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
        const SizedBox(height: 16),

        // Book No field (for tracking loans)
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
        ),
      ],
    );
  }

  Widget _buildFrequencyCard(String label, String value, IconData icon) {
    final isSelected = _paymentFrequency == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _paymentFrequency = value;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppColors.textSecondary,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build Location Picker Section with Map UI
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
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.map_outlined,
                    color: Colors.green,
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
                        'Tap map to mark location (Optional)',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_customerLatitude != null && _customerLongitude != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Saved',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
              latitude: _customerLatitude,
              longitude: _customerLongitude,
              height: 200,
              onLocationSelected: (lat, lng) {
                setState(() {
                  _customerLatitude = lat;
                  _customerLongitude = lng;
                });
              },
            ),
            
            // Location info display
            if (_customerLatitude != null && _customerLongitude != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_pin, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location: ${_customerLatitude!.toStringAsFixed(6)}, ${_customerLongitude!.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        setState(() {
                          _customerLatitude = null;
                          _customerLongitude = null;
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
                        initialLatitude: _customerLatitude,
                        initialLongitude: _customerLongitude,
                        customerName: _nameController.text.trim(),
                      ),
                    ),
                  );
                  if (result != null && mounted) {
                    setState(() {
                      _customerLatitude = result['latitude'];
                      _customerLongitude = result['longitude'];
                    });
                  }
                },
                icon: const Icon(Icons.fullscreen),
                label: const Text('Open Full Screen Map'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  side: const BorderSide(color: Colors.green),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 16 : 14,
          ),
        ),
      ],
    );
  }

  String _formatNumber(double value) {
    if (value >= 100000) {
      return '${(value / 100000).toStringAsFixed(2)} L';
    } else if (value >= 1000) {
      // Use 2 decimal places to show accurate values like 1.05K
      double kValue = value / 1000;
      // Remove trailing zeros: 1.00 -> 1, 1.50 -> 1.5, 1.05 -> 1.05
      if (kValue == kValue.roundToDouble()) {
        return '${kValue.toStringAsFixed(0)} K';
      } else if ((kValue * 10) == (kValue * 10).roundToDouble()) {
        return '${kValue.toStringAsFixed(1)} K';
      }
      return '${kValue.toStringAsFixed(2)} K';
    }
    return value.toStringAsFixed(0);
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
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.group_add,
                    color: AppColors.primary,
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
                'Create Loan',
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
    final customerProvider =
        Provider.of<CustomerProvider>(context, listen: false);
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);

    setState(() {
      _isLoading = true;
    });

    try {
      int customerId;
      final now = DateTime.now();

      if (widget.isNewCustomer) {
        // Create new customer with location
        final newCustomer = Customer(
          name: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          alternatePhone: _alternatePhoneController.text.trim().isEmpty
              ? null
              : _alternatePhoneController.text.trim(),
          address: _addressController.text.trim(),
          latitude: _customerLatitude,
          longitude: _customerLongitude,
          createdAt: now,
          updatedAt: now,
        );

        // Use addCustomerAndGetId to directly get the customer ID
        final createdId = await customerProvider.addCustomerAndGetId(newCustomer);
        if (createdId == null) {
          throw Exception(
              customerProvider.errorMessage ?? 'Failed to create customer');
        }
        customerId = createdId;

        // Assign customer to groups if selected
        if (_selectedGroupIds.isNotEmpty) {
          await DatabaseService.instance
              .addCustomerToMultipleGroups(customerId, _selectedGroupIds);
        }
      } else {
        customerId = _selectedCustomer!.id!;
        
        // Assign existing customer to groups if selected
        if (_selectedGroupIds.isNotEmpty) {
          await DatabaseService.instance
              .addCustomerToMultipleGroups(customerId, _selectedGroupIds);
        }
      }

      // Create loan
      if (mounted) {
        // Parse duration with error handling
        final duration = int.tryParse(_durationController.text) ?? 4;
        if (duration <= 0) {
          throw Exception('Invalid loan duration');
        }

        // Calculate due date - duration is in weeks
        DateTime dueDate;
        switch (_paymentFrequency) {
          case 'daily':
            dueDate = _selectedLoanDate
                .add(Duration(days: duration * 7)); // weeks to days
            break;
          case 'weekly':
            dueDate = _selectedLoanDate.add(Duration(days: duration * 7));
            break;
          default: // monthly - calculate based on months
            dueDate = DateTime(
              _selectedLoanDate.year,
              _selectedLoanDate.month + duration,
              _selectedLoanDate.day,
            );
        }

        // Parse principal with error handling
        Decimal principalDecimal;
        try {
          final principalText = _principalController.text.trim().replaceAll(',', '');
          if (principalText.isEmpty) {
            throw Exception('Principal amount is required');
          }
          principalDecimal = Decimal.parse(principalText);
          if (principalDecimal <= Decimal.zero) {
            throw Exception('Principal amount must be greater than zero');
          }
        } catch (e) {
          throw Exception('Invalid principal amount: Please enter a valid number');
        }

        // Determine initial loan status based on loan date
        // If loan date is in the past and payments should have been made, it starts as overdue
        LoanStatus initialStatus = LoanStatus.active;
        final daysSinceLoan = now.difference(_selectedLoanDate).inDays;
        final weeksElapsed = daysSinceLoan ~/ 7;
        if (weeksElapsed > 0) {
          // Loan date is more than a week ago, so at least one payment should have been made
          initialStatus = LoanStatus.overdue;
        }

        // Get book number from the loan details section (same for new and existing customers)
        final bookNo = _bookNoController.text.trim().isEmpty 
            ? null 
            : _bookNoController.text.trim();

        final loan = Loan(
          customerId: customerId,
          principal: principalDecimal,
          bookNo: bookNo,
          loanDate: _selectedLoanDate,
          dueDate: dueDate,
          totalAmount: principalDecimal, // Only principal
          remainingAmount: principalDecimal,
          status: initialStatus,
          createdAt: now,
          updatedAt: now,
          tenure: duration,
          notes: null,
        );

        final success = await loanProvider.addLoan(loan);

        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Loan created successfully'),
                backgroundColor: AppColors.success,
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
