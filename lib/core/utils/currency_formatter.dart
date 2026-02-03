import 'package:decimal/decimal.dart';

/// Utility class for formatting currency values in Indian Rupee format
class CurrencyFormatter {
  CurrencyFormatter._();
  
  /// Format amount as Indian currency
  /// Examples:
  /// - 1000 -> ₹1,000
  /// - 100000 -> ₹1,00,000
  /// - 1234567.89 -> ₹12,34,567.89
  /// Accepts double or Decimal
  static String format(dynamic amount, {bool showSymbol = true}) {
    double doubleAmount;
    if (amount is Decimal) {
      doubleAmount = amount.toDouble();
    } else if (amount is double) {
      doubleAmount = amount;
    } else if (amount is int) {
      doubleAmount = amount.toDouble();
    } else {
      doubleAmount = double.tryParse(amount.toString()) ?? 0.0;
    }
    
    final isNegative = doubleAmount < 0;
    doubleAmount = doubleAmount.abs();
    
    // Handle decimal part
    String formatted;
    if (doubleAmount == doubleAmount.truncateToDouble()) {
      formatted = doubleAmount.toInt().toString();
    } else {
      formatted = doubleAmount.toStringAsFixed(2);
    }
    
    final parts = formatted.split('.');
    final wholePart = parts[0];
    final decimalPart = parts.length > 1 ? '.${parts[1]}' : '';
    
    // Apply Indian number formatting (lakhs and crores)
    String formattedWhole;
    if (wholePart.length <= 3) {
      formattedWhole = wholePart;
    } else {
      final lastThree = wholePart.substring(wholePart.length - 3);
      final rest = wholePart.substring(0, wholePart.length - 3);
      
      // Add commas for every 2 digits from right to left for Indian format
      final buffer = StringBuffer();
      for (int i = 0; i < rest.length; i++) {
        if (i != 0 && (rest.length - i) % 2 == 0) {
          buffer.write(',');
        }
        buffer.write(rest[i]);
      }
      
      formattedWhole = '${buffer.toString()},$lastThree';
    }
    
    final sign = isNegative ? '-' : '';
    final symbol = showSymbol ? '₹' : '';
    
    return '$sign$symbol$formattedWhole$decimalPart';
  }
  
  /// Format amount in short form (K, L, Cr)
  /// Examples:
  /// - 1000 -> ₹1K
  /// - 100000 -> ₹1L
  /// - 10000000 -> ₹1Cr
  /// Accepts double or Decimal
  static String formatShort(dynamic amount, {bool showSymbol = true}) {
    double doubleAmount;
    if (amount is Decimal) {
      doubleAmount = amount.toDouble();
    } else if (amount is double) {
      doubleAmount = amount;
    } else if (amount is int) {
      doubleAmount = amount.toDouble();
    } else {
      doubleAmount = double.tryParse(amount.toString()) ?? 0.0;
    }
    
    final symbol = showSymbol ? '₹' : '';
    final isNegative = doubleAmount < 0;
    doubleAmount = doubleAmount.abs();
    final sign = isNegative ? '-' : '';
    
    if (doubleAmount >= 10000000) {
      return '$sign$symbol${(doubleAmount / 10000000).toStringAsFixed(2)}Cr';
    } else if (doubleAmount >= 100000) {
      return '$sign$symbol${(doubleAmount / 100000).toStringAsFixed(2)}L';
    } else if (doubleAmount >= 1000) {
      return '$sign$symbol${(doubleAmount / 1000).toStringAsFixed(1)}K';
    } else {
      return '$sign$symbol${doubleAmount.toStringAsFixed(0)}';
    }
  }
  
  /// Parse a formatted currency string back to double
  static double? parse(String value) {
    // Remove currency symbol and commas
    String cleanValue = value.replaceAll('₹', '').replaceAll(',', '').trim();
    
    // Handle K, L, Cr suffixes
    double multiplier = 1;
    if (cleanValue.endsWith('Cr')) {
      multiplier = 10000000;
      cleanValue = cleanValue.substring(0, cleanValue.length - 2);
    } else if (cleanValue.endsWith('L')) {
      multiplier = 100000;
      cleanValue = cleanValue.substring(0, cleanValue.length - 1);
    } else if (cleanValue.endsWith('K')) {
      multiplier = 1000;
      cleanValue = cleanValue.substring(0, cleanValue.length - 1);
    }
    
    final parsed = double.tryParse(cleanValue);
    if (parsed != null) {
      return parsed * multiplier;
    }
    return null;
  }
}
