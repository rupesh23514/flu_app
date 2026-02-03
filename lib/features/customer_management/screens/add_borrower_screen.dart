import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:decimal/decimal.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/repositories/customer_group_repository.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/customer_group.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/utils/validators.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/location_picker_widget.dart';
import '../providers/customer_provider.dart';
import '../../loan_management/providers/loan_provider.dart';

class AddBorrowerScreen extends StatefulWidget {
  final Customer? customer;

  const AddBorrowerScreen({super.key, this.customer});

  @override
  State<AddBorrowerScreen> createState() => _AddBorrowerScreenState();
}

class _AddBorrowerScreenState extends State<AddBorrowerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();

  // Customer form controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _alternatePhoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _aadharController = TextEditingController();

  // Loan form controllers
  final _principalController = TextEditingController();
  final _tenureController = TextEditingController();
  final _bookNoController = TextEditingController();  // Book number for each loan

  int _currentPage = 0;
  bool _isLoading = false;
  DateTime _loanStartDate = DateTime.now();
  bool _isEditMode = false;
  bool _showAlternatePhone = false;

  // Group selection (multi-group support)
  List<CustomerGroup> _availableGroups = [];
  List<int> _selectedGroupIds = []; // Changed from single to multiple
  final _newGroupNameController = TextEditingController();

  // Location selection
  double? _selectedLatitude;
  double? _selectedLongitude;

  @override
  void initState() {
    super.initState();
    _loadGroups();
    if (widget.customer != null) {
      _isEditMode = true;
      _populateCustomerData();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _alternatePhoneController.dispose();
    _addressController.dispose();
    _aadharController.dispose();
    _principalController.dispose();
    _tenureController.dispose();
    _bookNoController.dispose();
    _pageController.dispose();
    _newGroupNameController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await DatabaseService.instance.getAllCustomerGroups();
      if (mounted) {
        setState(() {
          _availableGroups = groups;
          // Set selected groups if editing customer with existing groups
          if (widget.customer != null && widget.customer!.groupIds.isNotEmpty) {
            _selectedGroupIds = List.from(widget.customer!.groupIds);
          } else if (widget.customer?.groupId != null) {
            // Legacy: single group support
            _selectedGroupIds = [widget.customer!.groupId!];
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading groups: $e');
    }
  }

  Future<void> _showGroupSelectionDialog() async {
    // Create a copy for temp selection in dialog
    List<int> tempSelectedIds = List.from(_selectedGroupIds);
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select Groups'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Existing groups with checkboxes
                if (_availableGroups.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Select one or more groups',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.grey),
                      ),
                    ),
                  ),
                  ...List.generate(_availableGroups.length, (index) {
                    final group = _availableGroups[index];
                    final isSelected = tempSelectedIds.contains(group.id);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (checked) {
                        setDialogState(() {
                          if (checked == true) {
                            tempSelectedIds.add(group.id!);
                          } else {
                            tempSelectedIds.remove(group.id);
                          }
                        });
                      },
                      secondary: CircleAvatar(
                        radius: 12,
                        backgroundColor: group.color,
                      ),
                      title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      controlAffinity: ListTileControlAffinity.trailing,
                      dense: true,
                    );
                  }),
                  const Divider(),
                ],
                // Create new group option
                ListTile(
                  leading: const Icon(Icons.add_circle_outline,
                      color: AppColors.primary),
                  title: const Text('Create New Group',
                      style: TextStyle(color: AppColors.primary)),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateGroupDialog();
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _selectedGroupIds = []);
                Navigator.pop(context);
              },
              child: const Text('Clear All'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _selectedGroupIds = tempSelectedIds);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateGroupDialog() async {
    _newGroupNameController.clear();
    int selectedColorIndex = 0;
    final colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
    ];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create New Group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _newGroupNameController,
                decoration: InputDecoration(
                  labelText: 'Group Name',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              const Text('Select Color:',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: List.generate(colors.length, (index) {
                  return GestureDetector(
                    onTap: () =>
                        setDialogState(() => selectedColorIndex = index),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors[index],
                        shape: BoxShape.circle,
                        border: selectedColorIndex == index
                            ? Border.all(color: Colors.black, width: 3)
                            : null,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_newGroupNameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a group name')),
                  );
                  return;
                }
                try {
                  final newGroup = CustomerGroup(
                    name: _newGroupNameController.text.trim(),
                    colorValue: colors[selectedColorIndex].toARGB32(),
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  final groupId = await DatabaseService.instance
                      .insertCustomerGroup(newGroup);
                  await _loadGroups();
                  setState(() {
                    if (!_selectedGroupIds.contains(groupId)) {
                      _selectedGroupIds.add(groupId);
                    }
                  });
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error creating group: $e')),
                    );
                  }
                }
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child:
                  const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _populateCustomerData() {
    final customer = widget.customer!;
    _nameController.text = customer.name;
    _phoneController.text = customer.phoneNumber;
    _addressController.text = customer.address ?? '';
    _aadharController.text = customer.bookNo ?? '';
    if (customer.alternatePhone != null &&
        customer.alternatePhone!.isNotEmpty) {
      _alternatePhoneController.text = customer.alternatePhone!;
      _showAlternatePhone = true;
    }
    // Populate location if available
    if (customer.hasLocation) {
      _selectedLatitude = customer.latitude;
      _selectedLongitude = customer.longitude;
    }
  }

  Future<void> _selectLoanStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _loanStartDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _loanStartDate) {
      setState(() {
        _loanStartDate = picked;
      });
    }
  }

  void _nextPage() {
    if (_currentPage < 1) {
      if (_validateCurrentPage()) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  bool _validateCurrentPage() {
    if (_currentPage == 0) {
      // Validate customer form
      return _nameController.text.isNotEmpty &&
          _phoneController.text.isNotEmpty &&
          Validators.validatePhoneNumber(_phoneController.text) == null;
    }
    return true;
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final customerProvider =
          Provider.of<CustomerProvider>(context, listen: false);
      final loanProvider = Provider.of<LoanProvider>(context, listen: false);

      // Create or update customer
      Customer customer;
      int customerId;

      if (_isEditMode) {
        customer = widget.customer!.copyWith(
          name: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          alternatePhone: _alternatePhoneController.text.trim().isEmpty
              ? null
              : _alternatePhoneController.text.trim(),
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          bookNo: _aadharController.text.trim().isEmpty
              ? null
              : _aadharController.text.trim(),
          groupId: _selectedGroupIds.isNotEmpty ? _selectedGroupIds.first : null,
          groupIds: _selectedGroupIds,
          latitude: _selectedLatitude,
          longitude: _selectedLongitude,
        );
        await customerProvider.updateCustomer(customer);
        customerId = customer.id!;
        
        // Update group memberships in junction table
        await CustomerGroupRepository.instance.setCustomerGroups(customerId, _selectedGroupIds);
      } else {
        customer = Customer(
          id: 0, // Will be set by database
          name: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          alternatePhone: _alternatePhoneController.text.trim().isEmpty
              ? null
              : _alternatePhoneController.text.trim(),
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          bookNo: _aadharController.text.trim().isEmpty
              ? null
              : _aadharController.text.trim(),
          groupId: _selectedGroupIds.isNotEmpty ? _selectedGroupIds.first : null,
          groupIds: _selectedGroupIds,
          latitude: _selectedLatitude,
          longitude: _selectedLongitude,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final success = await customerProvider.addCustomer(customer);
        if (!success) {
          throw Exception(
              customerProvider.errorMessage ?? 'Failed to add customer');
        }
        // Get the customer with the assigned ID from the reloaded list
        final addedCustomer = customerProvider.customers
            .where((c) => c.phoneNumber == _phoneController.text.trim())
            .firstOrNull;

        if (addedCustomer == null) {
          throw Exception('Customer was added but could not be retrieved');
        }
        customerId = addedCustomer.id!;
        
        // Save group memberships to junction table
        if (_selectedGroupIds.isNotEmpty) {
          await CustomerGroupRepository.instance.setCustomerGroups(customerId, _selectedGroupIds);
        }
      }

      // Create loan if not in edit mode
      if (!_isEditMode && _principalController.text.isNotEmpty) {
        // Safe parse with validation
        final parsedPrincipal = double.tryParse(_principalController.text) ?? 0.0;
        final principal = Decimal.parse(parsedPrincipal.toStringAsFixed(0));
        final tenure = int.tryParse(_tenureController.text) ?? 10;

        // Simple principal-only loan
        final totalAmount = principal;

        final loan = Loan(
          customerId: customerId,
          principal: principal,
          bookNo: _bookNoController.text.trim().isEmpty ? null : _bookNoController.text.trim(),
          tenure: tenure,
          totalAmount: totalAmount,
          loanDate: _loanStartDate,
          dueDate: _loanStartDate
              .add(Duration(days: tenure * 7)), // Assuming weekly payments
          remainingAmount: totalAmount,
          status: LoanStatus.active,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await loanProvider.addLoan(loan);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditMode
                ? 'Customer updated successfully'
                : 'Customer and loan created successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
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
        title: Text(_isEditMode ? 'Edit Customer' : 'Add New Borrower'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Progress indicator
            if (!_isEditMode) ...[
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: (_currentPage + 1) / 2,
                        backgroundColor: Colors.grey[300],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${_currentPage + 1} of 2',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],

            // Page view
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _buildCustomerForm(),
                  if (!_isEditMode) _buildLoanForm(),
                ],
              ),
            ),

            // Navigation buttons
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_currentPage > 0 && !_isEditMode)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previousPage,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Previous'),
                      ),
                    ),
                  if (_currentPage > 0 && !_isEditMode)
                    const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : (_currentPage == 1 || _isEditMode)
                              ? _submitForm
                              : _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
                          : Text(
                              (_currentPage == 1 || _isEditMode)
                                  ? 'Save'
                                  : 'Next',
                              style: const TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Customer Information',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Name field
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Full Name *',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            validator: Validators.validateName,
          ),

          const SizedBox(height: 16),

          // Phone field
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: InputDecoration(
              labelText: 'Phone Number *',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            validator: Validators.validatePhoneNumber,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                ),
              ),
            ),

          if (_showAlternatePhone) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _alternatePhoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: InputDecoration(
                labelText: 'Alternate Phone Number',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
              validator: (value) {
                if (value != null && value.isNotEmpty && value.length != 10) {
                  return 'Enter valid 10-digit number';
                }
                return null;
              },
            ),
          ],

          const SizedBox(height: 16),

          // Address field
          TextFormField(
            controller: _addressController,
            maxLines: 3,
            maxLength: 150,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Address',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Location Picker Section
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _selectedLatitude != null
                    ? AppColors.success.withValues(alpha: 0.5)
                    : Colors.grey.withValues(alpha: 0.3),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(12),
              color: _selectedLatitude != null
                  ? AppColors.success.withValues(alpha: 0.05)
                  : Colors.transparent,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  final result = await Navigator.push<Map<String, double>>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LocationPickerScreen(
                        initialLatitude: _selectedLatitude,
                        initialLongitude: _selectedLongitude,
                        customerName: _nameController.text.isNotEmpty
                            ? _nameController.text
                            : 'Customer',
                      ),
                    ),
                  );
                  if (result != null) {
                    setState(() {
                      _selectedLatitude = result['latitude'];
                      _selectedLongitude = result['longitude'];
                    });
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _selectedLatitude != null
                              ? AppColors.success.withValues(alpha: 0.1)
                              : AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _selectedLatitude != null
                              ? Icons.location_on
                              : Icons.add_location_alt_outlined,
                          color: _selectedLatitude != null
                              ? AppColors.success
                              : AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedLatitude != null
                                  ? 'Location Saved'
                                  : 'Add Location (Optional)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _selectedLatitude != null
                                    ? AppColors.success
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedLatitude != null
                                  ? 'Tap to view or update on map'
                                  : 'Tap to set customer location on map',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Clear location button if location is set
          if (_selectedLatitude != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedLatitude = null;
                    _selectedLongitude = null;
                  });
                },
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Clear Location'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Book No field
          TextFormField(
            controller: _aadharController,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            maxLength: 30,
            decoration: InputDecoration(
              labelText: 'Book No (Optional)',
              counterText: '',
              prefixIcon: const Icon(Icons.menu_book_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            // No validation - optional field
          ),

          const SizedBox(height: 16),

          // Group Selection - Prominent Button Style
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.5), width: 1.5),
              borderRadius: BorderRadius.circular(12),
              color: _selectedGroupIds.isNotEmpty
                  ? AppColors.primary.withValues(alpha: 0.05)
                  : Colors.transparent,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showGroupSelectionDialog,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _selectedGroupIds.isNotEmpty
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _selectedGroupIds.isNotEmpty
                              ? Icons.group
                              : Icons.group_add,
                          color: _selectedGroupIds.isNotEmpty
                              ? Colors.white
                              : AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedGroupIds.isNotEmpty
                                  ? '${_selectedGroupIds.length} Groups Selected'
                                  : 'Assign to groups (Optional)',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_selectedGroupIds.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            setState(() => _selectedGroupIds = []);
                          },
                        ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoanForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Loan Details',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 24),

          // Principal amount
          TextFormField(
            controller: _principalController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9), // Max 99,99,99,999
            ],
            decoration: InputDecoration(
              labelText: 'Principal Amount *',
              prefixText: '₹ ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            validator: Validators.validateAmount,
          ),

          const SizedBox(height: 16),

          // Book Number (optional but recommended)
          TextFormField(
            controller: _bookNoController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Book Number',
              hintText: 'e.g., BK001',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.menu_book),
            ),
          ),

          const SizedBox(height: 16),

          // Interest rate
          // Tenure
          TextFormField(
            controller: _tenureController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: InputDecoration(
              labelText: 'Tenure *',
              suffixText: 'weeks',
              hintText: '1-99',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter tenure';
              }
              final weeks = int.tryParse(value) ?? 0;
              if (weeks < 1 || weeks > 99) {
                return 'Enter 1-99 weeks';
              }
              return null;
            },
          ),

          const SizedBox(height: 16),

          // Start date
          InkWell(
            onTap: _selectLoanStartDate,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Loan Start Date',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_loanStartDate.day}/${_loanStartDate.month}/${_loanStartDate.year}',
                  ),
                  const Icon(Icons.calendar_today),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
