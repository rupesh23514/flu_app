// ignore_for_file: unused_element
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:decimal/decimal.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/services/permission_service.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/models/payment.dart';
import '../../customer_management/providers/customer_provider.dart';
import '../../loan_management/providers/loan_provider.dart';
import '../../payments/screens/payment_collection_screen_new.dart';
import '../../payments/screens/payment_history_screen.dart';

class LoanDetailsScreenNew extends StatefulWidget {
  final Loan loan;

  const LoanDetailsScreenNew({
    super.key,
    required this.loan,
  });

  @override
  State<LoanDetailsScreenNew> createState() => _LoanDetailsScreenNewState();
}

class _LoanDetailsScreenNewState extends State<LoanDetailsScreenNew> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Loan _currentLoan;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentLoan = widget.loan;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<CustomerProvider, LoanProvider>(
      builder: (context, customerProvider, loanProvider, _) {
        // Get updated loan data
        final updatedLoan = loanProvider.loans.firstWhere(
          (l) => l.id == widget.loan.id,
          orElse: () => widget.loan,
        );
        _currentLoan = updatedLoan;
        
        final customer = customerProvider.customers.firstWhere(
          (c) => c.id == _currentLoan.customerId,
          orElse: () => Customer(
            id: 0,
            name: 'Unknown Customer',
            phoneNumber: '',
            address: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(customer.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) => _handleMenuAction(value),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit),
                      title: Text('Edit Loan'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'renew',
                    child: ListTile(
                      leading: Icon(Icons.refresh),
                      title: Text('Renew Loan'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (_currentLoan.status != LoanStatus.closed && _currentLoan.status != LoanStatus.completed)
                    const PopupMenuItem(
                      value: 'close',
                      child: ListTile(
                        leading: Icon(Icons.check_circle),
                        title: Text('Close Loan'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Payments'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(customer.name, customer.phoneNumber, customer),
              _buildPaymentsTab(),
            ],
          ),
          floatingActionButton: _currentLoan.status != LoanStatus.closed && _currentLoan.status != LoanStatus.completed
              ? FloatingActionButton(
                  onPressed: () => _collectPayment(),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.payment, size: 28),
                )
              : null,
        );
      },
    );
  }

  Widget _buildOverviewTab(String customerName, String phone, Customer customer) {
    // Principal-based calculations
    final principal = _currentLoan.principal;
    final paid = _currentLoan.totalPaid;
    final remaining = (principal - paid) > Decimal.zero ? (principal - paid) : Decimal.zero;
    final progress = principal.toDouble() > 0 
        ? (paid.toDouble() / principal.toDouble()).clamp(0.0, 1.0)
        : 0.0;

    Color statusColor;
    String statusText;
    switch (_currentLoan.status) {
      case LoanStatus.overdue:
        statusColor = AppColors.loanOverdue;
        statusText = 'Overdue';
        break;
      case LoanStatus.closed:
      case LoanStatus.completed:
        statusColor = AppColors.loanClosed;
        statusText = 'Closed';
        break;
      case LoanStatus.pending:
        statusColor = AppColors.loanPending;
        statusText = 'Pending';
        break;
      default:
        statusColor = AppColors.loanActive;
        statusText = 'Active';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Outstanding Amount',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              CurrencyFormatter.format(remaining),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Progress
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Paid: ${CurrencyFormatter.format(paid)}',
                            style: const TextStyle(fontSize: 12),
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
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                          minHeight: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Customer Info
          _buildSectionHeader('Customer', Icons.person),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  customerName.isNotEmpty ? customerName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(customerName),
              subtitle: Text(customer.allPhoneNumbers),
              trailing: IconButton(
                icon: const Icon(Icons.phone, color: AppColors.primary),
                onPressed: () => _handleCallCustomer(customer),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Loan Details
          _buildSectionHeader('Loan Details', Icons.description),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_currentLoan.bookNo != null && _currentLoan.bookNo!.isNotEmpty)
                    _buildDetailRow('Book No', _currentLoan.bookNo!),
                  _buildDetailRow('Principal (P)', CurrencyFormatter.format(_currentLoan.principal)),
                  _buildDetailRow('Duration (T)', '${_currentLoan.tenure} ${_getDurationUnit()}'),
                  _buildDetailRow('Loan Start Date', _formatDate(_currentLoan.loanDate)),
                  _buildDetailRow('Due Date', _formatDate(_currentLoan.dueDate)),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildPaymentsTab() {
    // Get payments from current loan
    final payments = _currentLoan.payments;
    final principal = _currentLoan.principal.toDouble();
    final totalPaid = _currentLoan.totalPaid.toDouble();
    final outstanding = (principal - totalPaid).clamp(0.0, principal);
    
    // Sort by date, newest first
    final sortedPayments = List<Payment>.from(payments)
      ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    
    return Column(
      children: [
        // Payment Report Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Payment Report',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildReportCard(
                      'Principal',
                      CurrencyFormatter.format(principal),
                      AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildReportCard(
                      'Total Paid',
                      CurrencyFormatter.format(totalPaid),
                      AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Payment History List
        Expanded(
          child: payments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 64,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No payments yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Payment history will appear here',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // View Full History Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PaymentHistoryScreen(loan: _currentLoan),
                            ),
                          );
                        },
                        icon: const Icon(Icons.history),
                        label: const Text('View Full History (Edit/Delete)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          minimumSize: const Size(double.infinity, 44),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: sortedPayments.length,
                        itemBuilder: (context, index) {
                          final payment = sortedPayments[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.success.withValues(alpha: 0.3),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Payment Info Row
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      // Left: Rupee icon
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: AppColors.success.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(22),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            '₹',
                                            style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.success,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Middle: Amount and Date
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              CurrencyFormatter.format(payment.amount),
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatPaymentDate(payment.paymentDate),
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Right: Payment method badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _getPaymentMethodColor(payment.paymentMethod).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _getPaymentMethodLabel(payment.paymentMethod),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _getPaymentMethodColor(payment.paymentMethod),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Divider
                                Container(
                                  height: 1,
                                  color: Colors.grey.withValues(alpha: 0.2),
                                ),
                                // Action Buttons Row
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      // Edit Button
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => _showEditPaymentDialog(payment),
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.edit, size: 18, color: AppColors.primary),
                                                SizedBox(width: 6),
                                                Text(
                                                  'Edit',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: AppColors.primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Delete Button
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => _showDeletePaymentConfirmation(payment),
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            decoration: BoxDecoration(
                                              color: AppColors.error.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                                                SizedBox(width: 6),
                                                Text(
                                                  'Delete',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: AppColors.error,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),

        // Bottom Outstanding Summary
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: outstanding > 0 
                ? AppColors.loanOverdue.withValues(alpha: 0.1)
                : AppColors.success.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
            border: Border(
              top: BorderSide(
                color: outstanding > 0 
                    ? AppColors.loanOverdue.withValues(alpha: 0.3)
                    : AppColors.success.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
          ),
          child: Column(
            children: [
              const Text(
                'Outstanding Amount',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                CurrencyFormatter.format(outstanding),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: outstanding > 0 ? AppColors.loanOverdue : AppColors.success,
                ),
              ),
              if (outstanding == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Fully Paid!',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReportCard(String title, String amount, Color color) {
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
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPaymentDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.day} ${months[date.month - 1]} ${date.year}, ${hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} $period';
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  DateTime _calculatePaymentDate(int index) {
    final loanDate = _currentLoan.loanDate;
    // Simple weekly payment schedule
    return loanDate.add(Duration(days: (index + 1) * 7));
  }

  void _collectPayment() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentCollectionScreenNew(loan: _currentLoan),
      ),
    );
  }

  void _showPaymentOptions(Payment payment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.4,
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit Payment', maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditPaymentDialog(payment);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.error),
                  title: const Text('Delete Payment', style: TextStyle(color: AppColors.error), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeletePaymentConfirmation(payment);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditPaymentDialog(Payment payment) {
    final amountController = TextEditingController(text: payment.amount.toString());
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
                        Text(_formatPaymentDate(selectedDate)),
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
                    const SnackBar(content: Text('Please enter a valid amount')),
                  );
                  return;
                }

                final updatedPayment = payment.copyWith(
                  amount: amount,
                  paymentDate: selectedDate,
                  paymentMethod: selectedMethod,
                  notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                  updatedAt: DateTime.now(),
                );

                // Capture context-dependent references before async
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final loanProvider = Provider.of<LoanProvider>(context, listen: false);
                
                Navigator.pop(dialogContext);
                
                final success = await loanProvider.updatePayment(updatedPayment);
                
                if (success && mounted) {
                  await loanProvider.loadLoans();
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Payment updated successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Failed to update payment: ${loanProvider.errorMessage}'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeletePaymentConfirmation(Payment payment) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Are you sure you want to delete this payment?'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        CurrencyFormatter.format(payment.amount.toDouble()),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatPaymentDate(payment.paymentDate),
                      style: const TextStyle(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '⚠️ This will recalculate the loan outstanding and may mark the loan as overdue.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.warning,
                ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () async {
              // Capture context-dependent references before async
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final loanProvider = Provider.of<LoanProvider>(context, listen: false);
              
              Navigator.pop(dialogContext);
              
              final success = await loanProvider.deletePayment(payment.id!);
              
              if (success && mounted) {
                await loanProvider.loadLoans();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Payment deleted successfully'),
                    backgroundColor: AppColors.success,
                  ),
                );
              } else if (mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete payment: ${loanProvider.errorMessage}'),
                    backgroundColor: AppColors.error,
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

  void _handleMenuAction(String action) {
    switch (action) {
      case 'edit':
        _showEditLoanDialog();
        break;
      case 'renew':
        _showRenewLoanDialog();
        break;
      case 'close':
        _showCloseLoanDialog();
        break;
    }
  }

  void _showEditLoanDialog() {
    final principalController = TextEditingController(text: _currentLoan.principalAmount.toStringAsFixed(0));
    final interestController = TextEditingController(
      text: _currentLoan.monthlyInterestAmount?.toStringAsFixed(0) ?? '0',
    );
    // Get provider reference BEFORE showing dialog
    final loanProvider = context.read<LoanProvider>();
    final isMonthlyLoan = _currentLoan.isMonthlyInterest;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Loan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: principalController,
                decoration: const InputDecoration(
                  labelText: 'Principal Amount',
                  prefixText: '₹ ',
                ),
                keyboardType: TextInputType.number,
                maxLength: 12,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              // Show interest field only for monthly interest loans
              if (isMonthlyLoan) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: interestController,
                  decoration: const InputDecoration(
                    labelText: 'Monthly Interest Amount',
                    prefixText: '₹ ',
                    helperText: 'Fixed monthly interest to collect',
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                ),
              ],
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
              final newPrincipal = Decimal.tryParse(principalController.text) ?? _currentLoan.principal;
              final newInterest = isMonthlyLoan 
                  ? (Decimal.tryParse(interestController.text) ?? _currentLoan.monthlyInterestAmount)
                  : _currentLoan.monthlyInterestAmount;
              
              Navigator.pop(dialogContext);
              
              // Calculate new remaining amount
              final newRemaining = newPrincipal - _currentLoan.totalPaid;
              final actualRemaining = newRemaining > Decimal.zero ? newRemaining : Decimal.zero;
              
              final updatedLoan = _currentLoan.copyWith(
                principal: newPrincipal,
                totalAmount: newPrincipal, // Update total amount as well
                remainingAmount: actualRemaining,
                monthlyInterestAmount: newInterest,
                updatedAt: DateTime.now(),
              );
              
              final success = await loanProvider.updateLoan(updatedLoan);
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Loan updated successfully' : 'Failed to update loan'),
                    backgroundColor: success ? AppColors.success : AppColors.error,
                  ),
                );
                if (success && mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showCloseLoanDialog() {
    // Get provider reference BEFORE showing dialog
    final loanProvider = context.read<LoanProvider>();
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close Loan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Are you sure you want to close this loan?'),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('Outstanding: ${CurrencyFormatter.format(_currentLoan.remainingAmount)}'),
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
              Navigator.pop(dialogContext);
              
              final success = await loanProvider.updateLoanStatus(
                _currentLoan.id!,
                LoanStatus.closed,
              );
              
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Loan closed successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                  if (mounted) {
                    Navigator.pop(context); // Go back to list
                  }
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to close loan'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Close Loan'),
          ),
        ],
      ),
    );
  }

  void _showRenewLoanDialog() {
    final loanProvider = context.read<LoanProvider>();
    final principalController = TextEditingController(
      text: _currentLoan.principalAmount.toStringAsFixed(0),
    );
    final durationController = TextEditingController(
      text: _currentLoan.tenure.toString(),
    );
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renew Loan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current loan info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Loan Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Outstanding:'),
                        Text(
                          CurrencyFormatter.format(_currentLoan.remainingAmount),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _currentLoan.remainingAmount > Decimal.zero 
                                ? AppColors.error 
                                : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Paid:'),
                        Text(
                          CurrencyFormatter.format(_currentLoan.totalPaid),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'New Loan Details',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: principalController,
                decoration: const InputDecoration(
                  labelText: 'New Principal Amount',
                  prefixText: '₹ ',
                  helperText: 'Outstanding will be added to this',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: durationController,
                decoration: InputDecoration(
                  labelText: 'Duration',
                  suffixText: _currentLoan.isMonthlyInterest ? 'months' : 'weeks',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
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
              final newPrincipal = double.tryParse(principalController.text) ?? 0;
              final newDuration = int.tryParse(durationController.text) ?? _currentLoan.tenure;
              
              if (newPrincipal <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid principal amount'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              
              Navigator.pop(dialogContext);
              
              // Close current loan
              await loanProvider.updateLoanStatus(_currentLoan.id!, LoanStatus.closed);
              
              // Calculate new principal (new amount + outstanding from old loan)
              final totalNewPrincipal = Decimal.parse(newPrincipal.toString()) + 
                  (_currentLoan.remainingAmount > Decimal.zero ? _currentLoan.remainingAmount : Decimal.zero);
              
              // Create renewed loan
              final now = DateTime.now();
              final renewedLoan = Loan(
                customerId: _currentLoan.customerId,
                principal: totalNewPrincipal,
                tenure: newDuration,
                loanDate: now,
                dueDate: _currentLoan.isMonthlyInterest 
                    ? now.add(Duration(days: newDuration * 30))
                    : now.add(Duration(days: newDuration * 7)),
                totalAmount: totalNewPrincipal, // Will be recalculated
                remainingAmount: totalNewPrincipal,
                status: LoanStatus.active,
                loanType: _currentLoan.loanType,
                monthlyInterestAmount: _currentLoan.monthlyInterestAmount,
                bookNo: _currentLoan.bookNo,
                createdAt: now,
                updatedAt: now,
              );
              
              final success = await loanProvider.addLoan(renewedLoan);
              
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Loan renewed with ₹${totalNewPrincipal.toStringAsFixed(0)} principal'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                  Navigator.pop(context); // Go back to list
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to renew loan: ${loanProvider.errorMessage}'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Renew Loan'),
          ),
        ],
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
                    child: Text('1', style: TextStyle(color: AppColors.primary)),
                  ),
                  title: Text(customer.phoneNumber, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Primary'),
                  onTap: () => Navigator.of(context).pop(customer.phoneNumber),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child: Text('2', style: TextStyle(color: AppColors.primary)),
                  ),
                  title: Text(customer.alternatePhone!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Alternate'),
                  onTap: () => Navigator.of(context).pop(customer.alternatePhone),
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

  Future<void> _callCustomer(String phone) async {
    final permissionService = PermissionService.instance;
    final hasPermission = await permissionService.requestPhonePermission();
    
    if (hasPermission) {
      final uri = Uri.parse('tel:$phone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot make phone call'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Phone permission required'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => permissionService.openSettings(),
          ),
        ),
      );
    }
  }

  String _getDurationUnit() {
    // Fixed to weeks since we removed interest periods
    return 'weeks';
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
}
