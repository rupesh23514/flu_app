import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // EMI Calculator fields
  final _principalController = TextEditingController();
  final _rateController = TextEditingController();
  final _tenureController = TextEditingController();
  String _interestType = 'monthly';
  String _paymentFrequency = 'daily';

  // Results
  double _emi = 0;
  double _totalInterest = 0;
  double _totalAmount = 0;

  // Simple Calculator
  String _displayValue = '0';
  String _expression = '';
  double _result = 0;

  // Input limits
  static const int _maxPrincipalDigits = 10;
  static const int _maxRateDigits = 5;
  static const int _maxTenureDigits = 2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _principalController.addListener(_calculateEMI);
    _rateController.addListener(_calculateEMI);
    _tenureController.addListener(_calculateEMI);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _principalController.dispose();
    _rateController.dispose();
    _tenureController.dispose();
    super.dispose();
  }

  void _calculateEMI() {
    final principal =
        double.tryParse(_principalController.text.replaceAll(',', '')) ?? 0;
    final rate = double.tryParse(_rateController.text) ?? 0;
    final tenureWeeks = int.tryParse(_tenureController.text) ?? 0;

    if (principal <= 0 || rate <= 0 || tenureWeeks <= 0) {
      setState(() {
        _emi = 0;
        _totalInterest = 0;
        _totalAmount = 0;
      });
      return;
    }

    // Convert weeks to months for interest calculation
    double tenureInMonths = tenureWeeks / 4.33; // approximate weeks to months

    // Calculate monthly interest rate
    double monthlyRate;
    if (_interestType == 'yearly') {
      monthlyRate = rate / 12 / 100;
    } else {
      monthlyRate = rate / 100; // monthly rate
    }

    // Calculate total interest based on tenure in months
    double totalInterest = principal * monthlyRate * tenureInMonths;

    // Total amount = principal + interest
    final totalAmount = principal + totalInterest;

    // Calculate payment amount based on frequency and duration in weeks
    int totalPayments;
    switch (_paymentFrequency) {
      case 'daily':
        totalPayments = tenureWeeks * 7; // 7 days per week
        break;
      case 'weekly':
        totalPayments = tenureWeeks;
        break;
      case 'monthly':
        totalPayments = (tenureWeeks / 4.33).ceil(); // weeks to months
        break;
      default:
        totalPayments = tenureWeeks;
    }

    if (totalPayments <= 0) totalPayments = 1;

    setState(() {
      _totalInterest = totalInterest;
      _totalAmount = totalAmount;
      _emi = totalAmount / totalPayments;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculator'),
        bottom: TabBar(
          controller: _tabController,
          // ENHANCED: High-contrast tab text for visibility on green AppBar
          labelColor: Colors.white,
          unselectedLabelColor: const Color.fromRGBO(255, 255, 255, 0.90),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            letterSpacing: 0.5,
            shadows: [
              Shadow(
                  blurRadius: 3, color: Colors.black38, offset: Offset(0, 1)),
            ],
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.3,
            shadows: [
              Shadow(
                  blurRadius: 2, color: Colors.black26, offset: Offset(0, 1)),
            ],
          ),
          indicatorColor: Colors.white,
          indicatorWeight: 3.5,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'EMI Calculator'),
            Tab(text: 'Simple Calculator'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEMICalculator(),
          _buildSimpleCalculator(),
        ],
      ),
    );
  }

  Widget _buildEMICalculator() {
    String paymentLabel;
    switch (_paymentFrequency) {
      case 'daily':
        paymentLabel = 'Daily Payment';
        break;
      case 'weekly':
        paymentLabel = 'Weekly Payment';
        break;
      default:
        paymentLabel = 'Monthly EMI';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Principal Amount
          TextField(
            controller: _principalController,
            decoration: const InputDecoration(
              labelText: 'Principal Amount',
              prefixIcon: Icon(Icons.currency_rupee),
              hintText: 'Enter loan amount',
            ),
            keyboardType: TextInputType.number,
            maxLength: _maxPrincipalDigits,
            buildCounter: (context,
                    {required currentLength, required isFocused, maxLength}) =>
                null,
            onChanged: (value) {
              // Limit input length
              if (value.length > _maxPrincipalDigits) {
                _principalController.text =
                    value.substring(0, _maxPrincipalDigits);
                _principalController.selection = TextSelection.fromPosition(
                  const TextPosition(offset: _maxPrincipalDigits),
                );
              }
            },
          ),
          const SizedBox(height: 16),

          // Interest Rate Row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _rateController,
                  decoration: const InputDecoration(
                    labelText: 'Interest Rate',
                    prefixIcon: Icon(Icons.percent),
                    hintText: 'e.g. 2.5',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  maxLength: _maxRateDigits,
                  buildCounter: (context,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null,
                  onChanged: (value) {
                    // Allow only valid float format
                    if (value.isNotEmpty) {
                      final parsed = double.tryParse(value);
                      if (parsed == null &&
                          value != '.' &&
                          !value.endsWith('.')) {
                        _rateController.text =
                            value.substring(0, value.length - 1);
                        _rateController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _rateController.text.length),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _interestType,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _interestType = value!;
                    });
                    _calculateEMI();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Tenure Row - Changed to Weeks
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _tenureController,
                  decoration: const InputDecoration(
                    labelText: 'Duration (Weeks)',
                    prefixIcon: Icon(Icons.calendar_today),
                    hintText: 'e.g. 10',
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: _maxTenureDigits,
                  buildCounter: (context,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null,
                  onChanged: (value) {
                    if (value.length > _maxTenureDigits) {
                      _tenureController.text =
                          value.substring(0, _maxTenureDigits);
                      _tenureController.selection = TextSelection.fromPosition(
                        const TextPosition(offset: _maxTenureDigits),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _paymentFrequency,
                  decoration: const InputDecoration(
                    labelText: 'Frequency',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _paymentFrequency = value!;
                    });
                    _calculateEMI();
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Results
          if (_emi > 0) ...[
            Card(
              color: AppColors.primaryLight,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      paymentLabel,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₹${_formatNumber(_emi)}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildResultRow('Principal Amount',
                        '₹${_formatNumber(double.tryParse(_principalController.text) ?? 0)}'),
                    const Divider(),
                    _buildResultRow(
                        'Interest Amount', '₹${_formatNumber(_totalInterest)}'),
                    const Divider(),
                    _buildResultRow('Total Amount (Principal + Interest)',
                        '₹${_formatNumber(_totalAmount)}',
                        isBold: true),
                    const Divider(),
                    _buildResultRow(
                        'Duration', '${_tenureController.text} weeks'),
                    _buildResultRow('Collection Frequency',
                        _paymentFrequency.toUpperCase()),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              fontSize: isBold ? 16 : 14,
              color: isBold ? AppColors.primary : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleCalculator() {
    return Column(
      children: [
        // Display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          color: AppColors.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _expression,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                _displayValue,
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // Keypad
        Expanded(
          child: GridView.count(
            crossAxisCount: 4,
            padding: const EdgeInsets.all(16),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _buildCalcButton('C', isFunction: true, color: AppColors.error),
              _buildCalcButton('⌫', isFunction: true),
              _buildCalcButton('%', isFunction: true),
              _buildCalcButton('÷', isOperator: true),
              _buildCalcButton('7'),
              _buildCalcButton('8'),
              _buildCalcButton('9'),
              _buildCalcButton('×', isOperator: true),
              _buildCalcButton('4'),
              _buildCalcButton('5'),
              _buildCalcButton('6'),
              _buildCalcButton('-', isOperator: true),
              _buildCalcButton('1'),
              _buildCalcButton('2'),
              _buildCalcButton('3'),
              _buildCalcButton('+', isOperator: true),
              _buildCalcButton('00'),
              _buildCalcButton('0'),
              _buildCalcButton('.'),
              _buildCalcButton('=', isOperator: true, color: AppColors.primary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCalcButton(String text,
      {bool isOperator = false, bool isFunction = false, Color? color}) {
    return Material(
      color: color ??
          (isOperator ? AppColors.primaryLight : AppColors.surfaceContainer),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _onCalcButtonPressed(text),
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: color != null
                  ? Colors.white
                  : isOperator
                      ? AppColors.primary
                      : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  void _onCalcButtonPressed(String value) {
    setState(() {
      switch (value) {
        case 'C':
          _displayValue = '0';
          _expression = '';
          _result = 0;
          break;
        case '⌫':
          if (_displayValue.length > 1) {
            _displayValue =
                _displayValue.substring(0, _displayValue.length - 1);
          } else {
            _displayValue = '0';
          }
          break;
        case '=':
          _calculate();
          break;
        case '+':
        case '-':
        case '×':
        case '÷':
        case '%':
          _expression = '$_displayValue $value ';
          _result = double.tryParse(_displayValue) ?? 0;
          _displayValue = '0';
          break;
        default:
          // Limit display value to 15 characters max
          if (_displayValue.length >= 15) {
            return;
          }
          if (_displayValue == '0' && value != '.') {
            _displayValue = value;
          } else {
            // Prevent multiple decimals
            if (value == '.' && _displayValue.contains('.')) {
              return;
            }
            _displayValue += value;
          }
      }
    });
  }

  void _calculate() {
    if (_expression.isEmpty) return;

    final parts = _expression.trim().split(' ');
    if (parts.length < 2) return;

    final operator = parts[1];
    final secondNumber = double.tryParse(_displayValue) ?? 0;

    double result;
    switch (operator) {
      case '+':
        result = _result + secondNumber;
        break;
      case '-':
        result = _result - secondNumber;
        break;
      case '×':
        result = _result * secondNumber;
        break;
      case '÷':
        result = secondNumber != 0 ? _result / secondNumber : 0;
        break;
      case '%':
        result = _result * secondNumber / 100;
        break;
      default:
        result = secondNumber;
    }

    setState(() {
      _expression = '';
      _displayValue = result == result.toInt()
          ? result.toInt().toString()
          : result.toStringAsFixed(2);
      _result = result;
    });
  }

  String _formatNumber(double value) {
    if (value >= 10000000) {
      return '${(value / 10000000).toStringAsFixed(2)} Cr';
    } else if (value >= 100000) {
      return '${(value / 100000).toStringAsFixed(2)} L';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)} K';
    }
    return value.toStringAsFixed(2);
  }
}
