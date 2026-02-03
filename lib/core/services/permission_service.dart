import 'package:permission_handler/permission_handler.dart';

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
