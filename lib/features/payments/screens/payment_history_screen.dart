import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:decimal/decimal.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/models/payment.dart';
import '../../loan_management/providers/loan_provider.dart';
import '../../../core/utils/currency_formatter.dart';

class PaymentHistoryScreen extends StatefulWidget {
  final Loan loan;

  const PaymentHistoryScreen({
    super.key,
    required this.loan,
  });

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  List<Payment> _payments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _isLoading = true);
    
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    final payments = await loanProvider.getPaymentsForLoan(widget.loan.id!);
    
    setState(() {
      _payments = payments;
      _isLoading = false;
    });
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return '${weekdays[date.weekday % 7]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _getPaymentMethodLabel(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.bank:
        return 'Bank Transfer';
      case PaymentMethod.other:
        return 'Other';
    }
  }

  IconData _getPaymentMethodIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return Icons.money;
      case PaymentMethod.upi:
        return Icons.qr_code;
      case PaymentMethod.bank:
        return Icons.account_balance;
      case PaymentMethod.other:
        return Icons.more_horiz;
    }
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
                        Text(_formatDate(selectedDate)),
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
                
                if (success) {
                  _loadPayments();
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Payment updated successfully'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } else {
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('Failed to update payment: ${loanProvider.errorMessage}'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Payment payment) {
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
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CurrencyFormatter.format(payment.amount.toDouble()),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(payment.paymentDate),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ This will recalculate the loan outstanding amount.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.warning,
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
              backgroundColor: AppColors.error,
            ),
            onPressed: () async {
              // Capture context-dependent references before async
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final loanProvider = Provider.of<LoanProvider>(context, listen: false);
              
              Navigator.pop(dialogContext);
              
              final success = await loanProvider.deletePayment(payment.id!);
              
              if (success) {
                _loadPayments();
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Payment deleted successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } else {
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete payment: ${loanProvider.errorMessage}'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPayments,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _payments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.payments_outlined,
                        size: 64,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No payments yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Summary Card
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Total Collected',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              CurrencyFormatter.format(
                                _payments.fold(0.0, (sum, p) => sum + p.amount.toDouble()),
                              ),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_payments.length} payment${_payments.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    
                    // Payment List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _payments.length,
                        itemBuilder: (context, index) {
                          final payment = _payments[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getPaymentMethodIcon(payment.paymentMethod),
                                  color: AppColors.success,
                                ),
                              ),
                              title: Text(
                                CurrencyFormatter.format(payment.amount.toDouble()),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today,
                                        size: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDate(payment.paymentDate),
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryLight,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          _getPaymentMethodLabel(payment.paymentMethod),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                      if (payment.notes != null && payment.notes!.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            payment.notes!,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                              fontStyle: FontStyle.italic,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showEditPaymentDialog(payment);
                                  } else if (value == 'delete') {
                                    _showDeleteConfirmation(payment);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_outlined, size: 20),
                                        SizedBox(width: 8),
                                        Text('Edit Payment'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                                        SizedBox(width: 8),
                                        Text('Delete Payment', style: TextStyle(color: AppColors.error)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
