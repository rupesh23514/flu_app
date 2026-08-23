import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of attempting to open the phone dialer / place a call.
enum PhoneCallResult {
  success,
  noNumber,
  permissionDenied,
  launchFailed,
}

/// Service to handle app permissions
class PermissionService {
  static final PermissionService instance = PermissionService._internal();
  PermissionService._internal();

  /// Request microphone permission for voice input
  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Check if microphone permission is granted
  Future<bool> hasMicrophonePermission() async {
    return await Permission.microphone.isGranted;
  }

  /// Request phone call permission
  Future<bool> requestPhonePermission() async {
    final status = await Permission.phone.request();
    return status.isGranted;
  }

  /// Check if phone permission is permanently denied
  Future<bool> isPhonePermissionPermanentlyDenied() async {
    final status = await Permission.phone.status;
    return status.isPermanentlyDenied;
  }

  /// Open dialer for [phone]. Requests CALL_PHONE when needed; still tries the
  /// dialer if permission is denied (ACTION_DIAL does not require CALL_PHONE).
  Future<PhoneCallResult> launchPhoneCall(String phone) async {
    final cleanedPhone = phone.replaceAll(RegExp(r'[\s+\-]'), '');
    if (cleanedPhone.isEmpty) {
      return PhoneCallResult.noNumber;
    }

    final uri = Uri.parse('tel:$cleanedPhone');

    var status = await Permission.phone.status;
    if (!status.isGranted) {
      status = await Permission.phone.request();
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return PhoneCallResult.success;
    }

    if (status.isDenied || status.isPermanentlyDenied) {
      return PhoneCallResult.permissionDenied;
    }

    return PhoneCallResult.launchFailed;
  }

  /// Check if phone permission is granted
  Future<bool> hasPhonePermission() async {
    return await Permission.phone.isGranted;
  }

  /// Request storage permission for Excel export
  Future<bool> requestStoragePermission() async {
    // For Android 13+, we need to request specific media permissions
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }
    
    final status = await Permission.storage.request();
    if (status.isGranted) return true;
    
    // Try manage external storage for Android 11+
    final manageStatus = await Permission.manageExternalStorage.request();
    return manageStatus.isGranted;
  }

  /// Check if storage permission is granted
  Future<bool> hasStoragePermission() async {
    return await Permission.storage.isGranted || 
           await Permission.manageExternalStorage.isGranted;
  }

  /// Request all required permissions at once
  Future<Map<Permission, PermissionStatus>> requestAllPermissions() async {
    return await [
      Permission.microphone,
      Permission.phone,
      Permission.storage,
    ].request();
  }

  /// Open app settings if permission is permanently denied
  Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
