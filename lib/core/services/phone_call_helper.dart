import 'package:flutter/material.dart';
import '../../shared/models/customer.dart';
import '../constants/app_colors.dart';
import 'permission_service.dart';

/// Centralized helper for customer phone call functionality.
/// Handles phone validation, multi-number selection, and result feedback.
class PhoneCallHelper {
  PhoneCallHelper._();

  /// Handle calling a customer with phone number selection and result feedback.
  /// 
  /// [context] - BuildContext for dialogs and snackbars
  /// [customer] - Customer to call
  /// [accentColor] - Optional accent color for the phone selection dialog
  /// 
  /// Returns true if call was initiated, false otherwise.
  static Future<bool> handleCall(
    BuildContext context,
    Customer customer, {
    Color? accentColor,
  }) async {
    // Validate phone numbers - at least one must exist
    final hasPrimary = customer.phoneNumber.trim().isNotEmpty;
    final hasAlternate = customer.alternatePhone != null && 
        customer.alternatePhone!.trim().isNotEmpty;
    
    if (!hasPrimary && !hasAlternate) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No phone number'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return false;
    }

    // Default to primary, fall back to alternate if primary is empty
    String phoneToCall = hasPrimary ? customer.phoneNumber : customer.alternatePhone!;

    // Show selection dialog if customer has multiple phones
    if (customer.hasMultiplePhones) {
      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Select Phone Number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: accentColor?.withValues(alpha: 0.2) ?? AppColors.primaryLight,
                  child: Text(
                    '1',
                    style: TextStyle(color: accentColor ?? AppColors.primary),
                  ),
                ),
                title: Text(
                  customer.phoneNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('Primary'),
                onTap: () => Navigator.of(dialogContext).pop(customer.phoneNumber),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: accentColor?.withValues(alpha: 0.2) ?? AppColors.primaryLight,
                  child: Text(
                    '2',
                    style: TextStyle(color: accentColor ?? AppColors.primary),
                  ),
                ),
                title: Text(
                  customer.alternatePhone!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('Alternate'),
                onTap: () => Navigator.of(dialogContext).pop(customer.alternatePhone),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (selected == null) return false;
      phoneToCall = selected;
    }

    // Make the call
    final permissionService = PermissionService.instance;
    final result = await permissionService.launchPhoneCall(phoneToCall);

    if (!context.mounted) return result == PhoneCallResult.success;

    // Handle result with appropriate feedback
    switch (result) {
      case PhoneCallResult.success:
        return true;
      case PhoneCallResult.noNumber:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No phone number'),
            backgroundColor: AppColors.error,
          ),
        );
        return false;
      case PhoneCallResult.permissionDenied:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Phone permission required to make calls'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => permissionService.openSettings(),
            ),
          ),
        );
        return false;
      case PhoneCallResult.launchFailed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot make phone call'),
            backgroundColor: AppColors.error,
          ),
        );
        return false;
    }
  }
}
