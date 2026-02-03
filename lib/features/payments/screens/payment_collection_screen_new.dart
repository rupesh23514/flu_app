import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:decimal/decimal.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/models/payment.dart';
import '../../../shared/models/customer.dart';
import '../../loan_management/providers/loan_provider.dart';
import '../../customer_management/providers/customer_provider.dart';
import '../../../core/utils/currency_formatter.dart';

class PaymentCollectionScreenNew extends StatefulWidget {
  final Loan loan;

  const PaymentCollectionScreenNew({
    super.key,
    required this.loan,
  });

  @override
  State<PaymentCollectionScreenNew> createState() => _PaymentCollectionScreenNewState();
}

class _PaymentCollectionScreenNewState extends State<PaymentCollectionScreenNew> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _interestCollectionController = TextEditingController();
  final _principalRepaymentController = TextEditingController();
  final _notesController = TextEditingController();
  
  String _paymentMethod = 'cash';
  bool _isLoading = false;
  DateTime _selectedPaymentDate = DateTime.now(); // Mandatory payment date
  
  @override
  void initState() {
    super.initState();
    // Set default amounts based on loan type
    if (widget.loan.isMonthlyInterest) {
      // For monthly interest loans, default to monthly interest amount
      _interestCollectionController.text = widget.loan.monthlyInterestAmount?.toDouble().toStringAsFixed(0) ?? '0';
      _principalRepaymentController.text = '0'; // Principal usually paid at end
    } else {
      // Set EMI amount as default for weekly loans
      final emiAmount = _calculateEMI();
      _amountController.text = emiAmount.toStringAsFixed(0);
    }
  }

  double _calculateEMI() {
    // EMI calculation: Principal amount divided by 10 (mandatory as per requirement)
    final principalAmount = widget.loan.principal.toDouble();
    return principalAmount / 10;
  }

  double _getOutstanding() {
    // Outstanding is based on principal only
    final principal = widget.loan.principal.toDouble();
    final paid = widget.loan.totalPaid.toDouble();
    return (principal - paid).clamp(0, principal);
  }

  double _getTotalMonthlyPayment() {
    final interest = double.tryParse(_interestCollectionController.text) ?? 0;
    final principal = double.tryParse(_principalRepaymentController.text) ?? 0;
    return interest + principal;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _interestCollectionController.dispose();
    _principalRepaymentController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collect Payment'),
      ),
      body: Consumer<CustomerProvider>(
        builder: (context, customerProvider, _) {
          if (customerProvider.customers.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final customer = customerProvider.customers.firstWhere(
            (c) => c.id == widget.loan.customerId,
            orElse: () => Customer(
              id: 0,
              name: 'Unknown Customer',
              phoneNumber: '',
              address: '',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
          
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Customer & Loan Info Card
                _buildInfoCard(customer.name),
                
                const SizedBox(height: 24),
                
                // Different UI for monthly interest loans vs weekly loans
                if (widget.loan.isMonthlyInterest) ...[
                  // Monthly Interest Loan Collection UI
                  _buildMonthlyInterestSection(),
                ] else ...[
                  // Weekly Loan Collection UI
                  // Quick Amount Buttons
                  _buildQuickAmountButtons(),
                  
                  const SizedBox(height: 24),
                  
                  // Amount Input
                  _buildAmountInput(),
                ],
                
                const SizedBox(height: 16),
                
                // Payment Date Picker (Mandatory)
                _buildPaymentDatePicker(),
                
                const SizedBox(height: 16),
                
                // Payment Method
                _buildPaymentMethodSection(),
                
                const SizedBox(height: 16),
                
                // Notes
                TextFormField(
                  controller: _notesController,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                    prefixIcon: Icon(Icons.note_outlined),
                    hintText: 'Add payment notes',
                    counterText: '',
                  ),
                  maxLines: 2,
                ),
                
                const SizedBox(height: 24),
                
                // Submit Button
                _buildSubmitButton(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(String customerName) {
    final principal = widget.loan.principal.toDouble();
    final paid = widget.loan.totalPaid.toDouble();
    final remaining = _getOutstanding();
    final progress = principal > 0 
        ? (paid / principal).clamp(0.0, 1.0)
        : 0.0;
    
    final isMonthly = widget.loan.isMonthlyInterest;
    final accentColor = isMonthly ? Colors.orange.shade600 : AppColors.primary;
    final lightColor = isMonthly ? Colors.orange.shade100 : AppColors.primaryLight;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: lightColor,
                  radius: 24,
                  child: Text(
                    customerName.isNotEmpty ? customerName[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (widget.loan.bookNo != null && widget.loan.bookNo!.isNotEmpty)
                            Text(
                              'Book #${widget.loan.bookNo}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          // Loan Start Date
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today, size: 14, color: Colors.purple.shade700),
                                const SizedBox(width: 5),
                                Text(
                                  '${widget.loan.loanDate.day}/${widget.loan.loanDate.month}/${widget.loan.loanDate.year}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isMonthly)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Monthly Interest',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Progress Bar (for principal repayment)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isMonthly ? 'Principal Repayment' : 'Repayment Progress',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.surfaceContainer,
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Amount Info Row - different for monthly vs weekly
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: isMonthly 
                  ? _buildMonthlyInfoRow(remaining)
                  : _buildWeeklyInfoRow(remaining),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyInfoRow(double remaining) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              const Text(
                'Outstanding',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  CurrencyFormatter.format(remaining),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.loanOverdue,
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 30,
          width: 1,
          color: AppColors.textSecondary.withValues(alpha: 0.3),
        ),
        Expanded(
          child: Column(
            children: [
              const Text(
                'EMI Amount',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  CurrencyFormatter.format(_calculateEMI()),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.primary,
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyInfoRow(double remaining) {
    final monthlyInterest = widget.loan.monthlyInterestAmount?.toDouble() ?? 0;
    final totalInterestCollected = widget.loan.totalInterestCollected?.toDouble() ?? 0;
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  const Text(
                    'Outstanding Principal',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      CurrencyFormatter.format(remaining),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.loanOverdue,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 30,
              width: 1,
              color: AppColors.textSecondary.withValues(alpha: 0.3),
            ),
            Expanded(
              child: Column(
                children: [
                  const Text(
                    'Monthly Interest',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      CurrencyFormatter.format(monthlyInterest),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.orange.shade600,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_balance_wallet, size: 16, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Text(
                'Total Interest Collected: ',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange.shade700,
                ),
              ),
              Text(
                CurrencyFormatter.format(totalInterestCollected),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyInterestSection() {
    final monthlyInterest = widget.loan.monthlyInterestAmount?.toDouble() ?? 0;
    final outstanding = _getOutstanding();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info Text
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Enter interest collection and/or principal repayment amount',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Interest Collection Box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.percent, color: Colors.orange.shade700, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Interest Collection',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.orange.shade800,
                        ),
                      ),
                      Text(
                        'Monthly: ${CurrencyFormatter.format(monthlyInterest)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _interestCollectionController,
                decoration: InputDecoration(
                  labelText: 'Interest Amount',
                  prefixIcon: const Icon(Icons.currency_rupee),
                  hintText: 'Enter interest collected',
                  filled: true,
                  fillColor: Colors.orange.shade50,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () {
                      _interestCollectionController.text = monthlyInterest.toStringAsFixed(0);
                      setState(() {});
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      side: BorderSide(color: Colors.orange.shade300),
                    ),
                    child: const Text('Monthly'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      _interestCollectionController.text = '0';
                      setState(() {});
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.textSecondary.withValues(alpha: 0.3)),
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Principal Repayment Box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.account_balance, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Principal Repayment',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'Outstanding: ${CurrencyFormatter.format(outstanding)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _principalRepaymentController,
                decoration: InputDecoration(
                  labelText: 'Principal Amount',
                  prefixIcon: const Icon(Icons.currency_rupee),
                  hintText: 'Enter principal to reduce',
                  filled: true,
                  fillColor: AppColors.primaryLight.withValues(alpha: 0.3),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
                validator: (value) {
                  final amount = double.tryParse(value ?? '0') ?? 0;
                  if (amount > outstanding) {
                    return 'Cannot exceed outstanding (${CurrencyFormatter.format(outstanding)})';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () {
                      _principalRepaymentController.text = outstanding.toStringAsFixed(0);
                      setState(() {});
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                    child: const Text('Full'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      _principalRepaymentController.text = '0';
                      setState(() {});
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.textSecondary.withValues(alpha: 0.3)),
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Total Collection Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, Colors.orange.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Collection',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                CurrencyFormatter.format(_getTotalMonthlyPayment()),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAmountButtons() {
    final outstanding = _getOutstanding();
    final amounts = [
      {'label': '500', 'value': 500.0},
      {'label': '1000', 'value': 1000.0},
      {'label': '2000', 'value': 2000.0},
      {'label': 'Full', 'value': outstanding},
    ];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Amount',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: amounts.map((item) {
            final value = (item['value'] as double).clamp(0, outstanding);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: OutlinedButton(
                  onPressed: () {
                    _amountController.text = value.toStringAsFixed(0);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    item['label'] as String,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAmountInput() {
    return TextFormField(
      controller: _amountController,
      decoration: InputDecoration(
        labelText: 'Payment Amount *',
        prefixIcon: const Icon(Icons.currency_rupee),
        hintText: 'Enter amount',
        suffixIcon: IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => _amountController.clear(),
        ),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter amount';
        }
        final amount = double.tryParse(value) ?? 0;
        if (amount <= 0) {
          return 'Enter valid amount';
        }
        if (amount > _getOutstanding()) {
          return 'Amount exceeds outstanding balance';
        }
        return null;
      },
    );
  }

  Widget _buildPaymentDatePicker() {
    final now = DateTime.now();
    
    // Check if selected date is in the future (info only, not blocking)
    final bool isFutureDate = _selectedPaymentDate.isAfter(now);
    // Check if date is in the past (info only, not blocking)
    final bool isPastDate = _selectedPaymentDate.isBefore(DateTime(now.year, now.month, now.day));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text(
              'Payment Date',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            Text(
              ' *',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _selectPaymentDate(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(
                color: isFutureDate 
                    ? AppColors.warning 
                    : AppColors.textSecondary.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: isFutureDate 
                      ? AppColors.warning 
                      : AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(_selectedPaymentDate),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isFutureDate 
                              ? AppColors.warning 
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (isFutureDate)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Future date - advance payment',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      if (isPastDate)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Backdated payment',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Quick date buttons
        Row(
          children: [
            _buildQuickDateButton('Today', DateTime.now()),
            const SizedBox(width: 8),
            _buildQuickDateButton('Yesterday', DateTime.now().subtract(const Duration(days: 1))),
            const SizedBox(width: 8),
            _buildQuickDateButton('Last Week', DateTime.now().subtract(const Duration(days: 7))),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickDateButton(String label, DateTime date) {
    final isSelected = _isSameDay(_selectedPaymentDate, date);
    return Expanded(
      child: OutlinedButton(
        onPressed: () {
          setState(() {
            _selectedPaymentDate = date;
          });
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: isSelected ? Colors.white : AppColors.primary,
          backgroundColor: isSelected ? AppColors.primary : null,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return '${weekdays[date.weekday % 7]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _selectPaymentDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedPaymentDate,
      firstDate: DateTime(2000), // Allow any past date
      lastDate: DateTime(2100), // Allow any future date
      helpText: 'Select Payment Collection Date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedPaymentDate) {
      setState(() {
        _selectedPaymentDate = picked;
      });
    }
  }

  Widget _buildPaymentMethodSection() {
    final methods = [
      {'key': 'cash', 'label': 'Cash', 'icon': Icons.money},
      {'key': 'upi', 'label': 'UPI', 'icon': Icons.qr_code},
      {'key': 'bank', 'label': 'Bank', 'icon': Icons.account_balance},
      {'key': 'other', 'label': 'Other', 'icon': Icons.more_horiz},
    ];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Method',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: methods.map((method) {
            final isSelected = _paymentMethod == method['key'];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  selected: isSelected,
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        method['icon'] as IconData,
                        size: 20,
                        color: isSelected ? AppColors.primary : AppColors.textSecondary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        method['label'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  onSelected: (selected) {
                    setState(() {
                      _paymentMethod = method['key'] as String;
                    });
                  },
                  selectedColor: AppColors.primaryLight,
                  backgroundColor: AppColors.surfaceContainer,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  showCheckmark: false,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _submitPayment,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.check_circle),
        label: Text(
          _isLoading ? 'Processing...' : 'Confirm Payment',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    // Payment date validation removed - allow any date for flexibility
    
    // For monthly interest loans, validate at least one amount is entered
    if (widget.loan.isMonthlyInterest) {
      final interestAmount = double.tryParse(_interestCollectionController.text) ?? 0;
      final principalAmount = double.tryParse(_principalRepaymentController.text) ?? 0;
      if (interestAmount <= 0 && principalAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter interest or principal amount'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Calculate amount based on loan type
      Decimal amount;
      String? notes;
      
      if (widget.loan.isMonthlyInterest) {
        final interestAmount = double.tryParse(_interestCollectionController.text) ?? 0;
        final principalAmount = double.tryParse(_principalRepaymentController.text) ?? 0;
        
        // Total amount is only the principal repayment (interest is tracked separately)
        amount = Decimal.parse(principalAmount.toStringAsFixed(0));
        
        // Build notes to track interest collection
        final notesParts = <String>[];
        if (interestAmount > 0) {
          notesParts.add('Interest: ₹${interestAmount.toStringAsFixed(0)}');
        }
        if (principalAmount > 0) {
          notesParts.add('Principal: ₹${principalAmount.toStringAsFixed(0)}');
        }
        if (_notesController.text.trim().isNotEmpty) {
          notesParts.add(_notesController.text.trim());
        }
        notes = notesParts.join(' | ');
        
        // We need to handle interest collection separately
        // For now, we'll record the total as one payment but notes will track breakdown
        // Total payment recorded in transaction = interest + principal
        final totalCollection = interestAmount + principalAmount;
        amount = Decimal.parse(totalCollection.toStringAsFixed(0));
      } else {
        // Safe parse with fallback to zero
        final parsedAmount = double.tryParse(_amountController.text) ?? 0.0;
        amount = Decimal.parse(parsedAmount.toStringAsFixed(0));
        notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
      }
      
      // Save payment via loan provider
      final loanProvider = Provider.of<LoanProvider>(context, listen: false);
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      
      // Convert payment method string to enum
      PaymentMethod paymentMethodEnum;
      switch (_paymentMethod) {
        case 'upi':
          paymentMethodEnum = PaymentMethod.upi;
          break;
        case 'bank':
          paymentMethodEnum = PaymentMethod.bank;
          break;
        case 'other':
          paymentMethodEnum = PaymentMethod.other;
          break;
        default:
          paymentMethodEnum = PaymentMethod.cash;
      }
      
      bool success;
      
      if (widget.loan.isMonthlyInterest) {
        // For monthly interest loans, pass the interest amount separately
        // Use tryParse to safely handle invalid input
        final interestParsed = double.tryParse(_interestCollectionController.text) ?? 0.0;
        final principalParsed = double.tryParse(_principalRepaymentController.text) ?? 0.0;
        final interestAmount = Decimal.parse(interestParsed.toStringAsFixed(0));
        final principalAmount = Decimal.parse(principalParsed.toStringAsFixed(0));
        
        success = await loanProvider.addMonthlyInterestPayment(
          widget.loan.id!,
          interestAmount,
          principalAmount,
          _selectedPaymentDate,
          notes: notes,
          paymentMethod: paymentMethodEnum,
        );
      } else {
        // Use the manually selected payment date (mandatory)
        success = await loanProvider.addPayment(
          widget.loan.id!,
          amount,
          _selectedPaymentDate, // Use selected date instead of now
          notes: notes,
          paymentMethod: paymentMethodEnum,
        );
      }
      
      if (success && mounted) {
        // Refresh all providers to update UI across the app
        await loanProvider.loadLoans();
        await loanProvider.loadDashboardStats();
        await customerProvider.loadCustomers();
        
        // Show success dialog
        final displayAmount = widget.loan.isMonthlyInterest ? _getTotalMonthlyPayment() : amount.toDouble();
        _showSuccessDialog(displayAmount);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loanProvider.errorMessage ?? 'Failed to save payment'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
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

  void _showSuccessDialog(double amount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Payment Successful!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              CurrencyFormatter.format(amount),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Payment recorded successfully',
              style: TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Go back to home
              },
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
