import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'alarm_service.dart';
import 'migration_safety_service.dart';
import '../../features/loan_management/providers/loan_provider.dart';
import '../../features/customer_management/providers/customer_provider.dart';

/// Centralized post-restore refresh helper.
///
/// Call [refreshAfterRestore] immediately after a successful
/// [DatabaseService.restoreFromFile] call so that all in-memory providers
/// reflect the restored data, pending alarms are rescheduled, and data
/// integrity is validated — all without requiring an app restart.
class PostRestoreService {
  static final PostRestoreService instance = PostRestoreService._internal();
  PostRestoreService._internal();

  /// Refresh providers, reschedule alarms, and run migration validation.
  ///
  /// Must be called with a [BuildContext] that has [LoanProvider] and
  /// [CustomerProvider] in its widget tree.
  Future<void> refreshAfterRestore(BuildContext context) async {
    try {
      final loanProvider = Provider.of<LoanProvider>(context, listen: false);
      final customerProvider =
          Provider.of<CustomerProvider>(context, listen: false);

      // Reload core data
      await Future.wait([
        loanProvider.loadLoans(),
        customerProvider.loadCustomers(),
      ]);

      // Reload derived views
      await Future.wait([
        loanProvider.loadLoansWithCustomers(),
        loanProvider.loadDashboardStats(),
      ]);

      // Reschedule alarms from restored reminders
      try {
        final rescheduled =
            await AlarmService.instance.verifyAndRescheduleAlarms();
        debugPrint('PostRestoreService: Rescheduled $rescheduled alarms');
      } catch (e) {
        debugPrint('PostRestoreService: Alarm reschedule error (non-fatal): $e');
      }

      // Validate migration integrity
      try {
        final valid =
            await MigrationSafetyService.validateMigrationIntegrity();
        debugPrint(
            'PostRestoreService: Migration integrity valid=$valid');
      } catch (e) {
        debugPrint(
            'PostRestoreService: Migration validation error (non-fatal): $e');
      }

      debugPrint('PostRestoreService: Refresh complete');
    } catch (e) {
      debugPrint('PostRestoreService: Refresh error: $e');
    }
  }
}
