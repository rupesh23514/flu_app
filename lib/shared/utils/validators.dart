class Validators {
  
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email';
    }
    
    return null;
  }

  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }
    // Allow any characters, no restrictions
    return null;
  }

  static String? validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    
    // Remove any non-digit characters for validation
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    
    // Allow any 10 digit phone number
    if (digits.length != 10) {
      return 'Phone number must be 10 digits';
    }
    
    return null;
  }

  static String? validateAadhar(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Aadhar is optional
    }
    
    // Remove spaces and hyphens
    final cleaned = value.replaceAll(RegExp(r'[\s\-]'), '');
    
    if (cleaned.length != 12) {
      return 'Aadhar must be 12 digits';
    }
    
    if (!RegExp(r'^\d{12}$').hasMatch(cleaned)) {
      return 'Aadhar must contain only digits';
    }
    
    return null;
  }

  static String? validatePAN(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // PAN is optional
    }
    
    // PAN format: 5 letters, 4 digits, 1 letter
    final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
    if (!panRegex.hasMatch(value.toUpperCase())) {
      return 'Please enter a valid PAN (e.g., ABCDE1234F)';
    }
    
    return null;
  }

  static String? validateAmount(String? value, {double? minAmount, double? maxAmount}) {
    if (value == null || value.trim().isEmpty) {
      return 'Amount is required';
    }
    
    final amount = double.tryParse(value);
    if (amount == null) {
      return 'Please enter a valid amount';
    }
    
    if (amount <= 0) {
      return 'Amount must be greater than zero';
    }
    
    // Max limit: 99,99,99,999 (99 crore)
    const defaultMaxAmount = 999999999.0;
    final effectiveMax = maxAmount ?? defaultMaxAmount;
    
    if (amount > effectiveMax) {
      return 'Amount cannot exceed ₹${effectiveMax.toStringAsFixed(0)}';
    }
    
    if (minAmount != null && amount < minAmount) {
      return 'Amount must be at least ₹$minAmount';
    }
    
    return null;
  }

  static String? validateInterestRate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Interest rate is required';
    }
    
    final rate = double.tryParse(value);
    if (rate == null) {
      return 'Please enter a valid interest rate';
    }
    
    if (rate < 0) {
      return 'Interest rate cannot be negative';
    }
    
    if (rate > 100) {
      return 'Interest rate cannot exceed 100%';
    }
    
    return null;
  }

  static String? validateTenure(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Tenure is required';
    }
    
    final tenure = int.tryParse(value);
    if (tenure == null) {
      return 'Please enter a valid tenure';
    }
    
    if (tenure <= 0) {
      return 'Tenure must be greater than zero';
    }
    
    if (tenure > 600) { // Maximum 50 years in months
      return 'Tenure cannot exceed 600 months';
    }
    
    return null;
  }

  static String? validatePIN(String? value) {
    if (value == null || value.isEmpty) {
      return 'PIN is required';
    }
    
    if (value.length != 4) {
      return 'PIN must be exactly 4 digits';
    }
    
    if (!RegExp(r'^\d{4}$').hasMatch(value)) {
      return 'PIN must contain only digits';
    }
    
    // Check for sequential or repeated digits
    if (isSequentialPIN(value) || isRepeatedPIN(value)) {
      return 'Please choose a more secure PIN';
    }
    
    return null;
  }

  static String? validateConfirmPIN(String? value, String? originalPIN) {
    final pinError = validatePIN(value);
    if (pinError != null) return pinError;
    
    if (value != originalPIN) {
      return 'PINs do not match';
    }
    
    return null;
  }

  static String? validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Address is required';
    }
    
    if (value.trim().length < 10) {
      return 'Please enter a complete address';
    }
    
    if (value.length > 200) {
      return 'Address is too long';
    }
    
    return null;
  }

  // Helper methods
  static bool isSequentialPIN(String pin) {
    for (int i = 0; i < pin.length - 1; i++) {
      if (int.parse(pin[i + 1]) != int.parse(pin[i]) + 1 && 
          int.parse(pin[i + 1]) != int.parse(pin[i]) - 1) {
        return false;
      }
    }
    return true;
  }

  static bool isRepeatedPIN(String pin) {
    return pin.split('').toSet().length <= 2;
  }

  static String formatPhoneNumber(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.length == 10) {
      return '${cleaned.substring(0, 5)} ${cleaned.substring(5)}';
    }
    return phone;
  }

  static String formatAadhar(String aadhar) {
    final cleaned = aadhar.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.length == 12) {
      return '${cleaned.substring(0, 4)} ${cleaned.substring(4, 8)} ${cleaned.substring(8)}';
    }
    return aadhar;
  }
}