import 'package:flutter/foundation.dart';

/// Utility functions for isolate-based computation to prevent main thread blocking
class ComputeUtils {
  /// Check which loan IDs are overdue based on weekly payment schedule
  /// This runs in an isolate to prevent ANR
  static Future<List<int>> checkWeeklyOverdueLoans(List<Map<String, dynamic>> loansData) async {
    return compute(_checkOverdueLoansIsolate, loansData);
  }
  
  /// Isolate-safe function to check overdue loans
  static List<int> _checkOverdueLoansIsolate(List<Map<String, dynamic>> loansData) {
    final now = DateTime.now();
    final overdueIds = <int>[];
    
    for (final loanData in loansData) {
      try {
        final loanId = loanData['id'] as int;
        final status = loanData['status'] as int;
        final isMonthlyInterest = (loanData['is_monthly_interest'] as int?) == 1;
        final principal = double.parse(loanData['principal'].toString());
        final totalPaid = double.parse(loanData['total_paid'].toString());
        final loanDateStr = loanData['loan_date'] as String;
        final loanDate = DateTime.parse(loanDateStr);
        final tenure = loanData['tenure'] as int;
        
        // Skip non-active loans (completed, closed, cancelled)
        if (status == 2 || status == 3 || status == 4) {
          continue;
        }
        
        if (isMonthlyInterest) {
          // Monthly interest loan: check 30-day overdue
          final daysSinceLoan = now.difference(loanDate).inDays;
          final monthsElapsed = daysSinceLoan ~/ 30;
          final remaining = principal - totalPaid;
          
          if (monthsElapsed > tenure && remaining > 0) {
            overdueIds.add(loanId);
          }
        } else {
          // Weekly loan: check EMI-based overdue
          final emiAmount = principal / 10.0;
          if (emiAmount <= 0) continue;
          
          final actualPayments = (totalPaid / emiAmount).floor();
          final daysSinceLoan = now.difference(loanDate).inDays;
          final expectedPayments = (daysSinceLoan ~/ 7).clamp(0, tenure);
          
          if (actualPayments < expectedPayments) {
            overdueIds.add(loanId);
          }
        }
      } catch (e) {
        debugPrint('Error checking loan: $e');
        continue;
      }
    }
    
    return overdueIds;
  }
}
