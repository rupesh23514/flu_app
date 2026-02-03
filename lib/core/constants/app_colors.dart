import 'package:flutter/material.dart';

/// App color palette - Material 3 Design
class AppColors {
  AppColors._();

  // Primary Colors (Green theme for finance)
  static const Color primary = Color(0xFF2E7D32);
  static const Color primaryLight = Color(0xFF4CAF50);
  static const Color primaryDark = Color(0xFF1B5E20);
  static const Color primaryContainer = Color(0xFFB8E6B9);
  static const Color onPrimaryContainer = Color(0xFF002106);

  // Secondary Colors
  static const Color secondary = Color(0xFF526350);
  static const Color secondaryContainer = Color(0xFFD4E8D1);
  static const Color onSecondaryContainer = Color(0xFF101F10);

  // Surface Colors
  static const Color surface = Color(0xFFFCFDF7);
  static const Color surfaceVariant = Color(0xFFDEE5D9);
  static const Color surfaceContainer = Color(0xFFF0F5EB);

  // Background
  static const Color background = Color(0xFFFCFDF7);
  static const Color scaffoldBackground = Color(0xFFF5F5F5);

  // Text Colors
  static const Color textPrimary = Color(0xFF1A1C19);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFF73796E);
  static const Color textDisabled = Color(0xFF9E9E9E);

  // Status Colors
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorLight = Color(0xFFFFEDEA);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color warning = Color(0xFFFF8F00);
  static const Color warningLight = Color(0xFFFFF3E0);
  static const Color warningContainer = Color(0xFFFFE082);
  static const Color info = Color(0xFF0288D1);
  static const Color infoLight = Color(0xFFE1F5FE);

  // Other Colors
  static const Color divider = Color(0xFFE0E0E0);
  static const Color outline = Color(0xFFC4C8BB);
  static const Color shadow = Color(0x1A000000);
  static const Color white = Colors.white;
  static const Color black = Colors.black;

  // Loan status colors
  static const Color loanActive = Color(0xFF2E7D32);
  static const Color loanOverdue = Color(0xFFBA1A1A);
  static const Color loanCompleted = Color(0xFF757575);
  static const Color loanPending = Color(0xFFFF8F00);
  static const Color loanClosed = Color(0xFF9E9E9E);
  static const Color loanDueToday = Color(0xFFFF8F00);

  // Gradient colors
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [success, Color(0xFF66BB6A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [warning, Color(0xFFFFB74D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient errorGradient = LinearGradient(
    colors: [error, Color(0xFFEF5350)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}