import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🏆 LEGENDARY Permission Helper - Enterprise-grade permission management
/// Handles all Android permissions required for reliable alarm/reminder functionality
class PermissionHelper {
  static final PermissionHelper _instance = PermissionHelper._internal();
  static PermissionHelper get instance => _instance;
  PermissionHelper._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Track permission request attempts to avoid spamming user
  static const String _permissionRequestCountKey = 'permission_request_count';
  static const String _lastPermissionRequestKey = 'last_permission_request';
  static const int _maxDailyRequests = 2;

  /// 🚀 Master permission request - handles ALL required permissions
  /// Returns detailed status of all permissions
  Future<AppPermissionStatus> requestAllPermissions(BuildContext context) async {
    debugPrint('🔐 Starting comprehensive permission check...');
    
    final status = AppPermissionStatus();
    
    // ===== CRITICAL ALARM PERMISSIONS =====
    
    // 1. Notification permission (CRITICAL)
    status.notification = await _requestNotificationPermission();
    debugPrint('   📱 Notifications: ${status.notification ? "✅" : "❌"}');
    
    // 2. Exact Alarm permission (CRITICAL for Android 12+)
    status.exactAlarm = await _requestExactAlarmPermission();
    debugPrint('   ⏰ Exact Alarms: ${status.exactAlarm ? "✅" : "❌"}');
    
    // 3. Battery Optimization (IMPORTANT for background alarms)
    status.batteryOptimization = await _requestBatteryOptimization();
    debugPrint('   🔋 Battery Optimization: ${status.batteryOptimization ? "✅" : "❌"}');
    
    // 4. Schedule Exact Alarm (Android 13+)
    status.scheduleExactAlarm = await _checkScheduleExactAlarm();
    debugPrint('   📅 Schedule Exact: ${status.scheduleExactAlarm ? "✅" : "❌"}');
    
    // 5. Full Screen Intent (for lock screen alarms)
    status.fullScreenIntent = await _checkFullScreenIntent();
    debugPrint('   📺 Full Screen Intent: ${status.fullScreenIntent ? "✅" : "❌"}');
    
    // 6. Wake Lock (keep CPU awake for alarms)
    status.wakeLock = true; // Handled by wakelock_plus package
    debugPrint('   💡 Wake Lock: ✅ (via package)');
    
    // ===== APP FEATURE PERMISSIONS =====
    
    // 7. Phone Call Permission (for calling customers)
    status.phone = await _requestPhonePermission();
    debugPrint('   📞 Phone Calls: ${status.phone ? "✅" : "❌"}');
    
    // 8. Location Permission (for customer maps)
    status.location = await _requestLocationPermission();
    debugPrint('   📍 Location: ${status.location ? "✅" : "❌"}');
    
    // 10. Storage Permission (for backup/export)
    status.storage = await _requestStoragePermission();
    debugPrint('   💾 Storage: ${status.storage ? "✅" : "❌"}');
    
    // Show professional dialog if critical permissions are missing
    if (!status.hasCriticalPermissions && context.mounted) {
      await _showProfessionalPermissionDialog(context, status);
    }
    
    debugPrint('🔐 Permission check complete:');
    debugPrint('   Score: ${status.score}/100');
    debugPrint('   Critical: ${status.hasCriticalPermissions ? "✅" : "❌"}');
    debugPrint('   Missing: ${status.missingPermissions.join(", ")}');
    
    return status;
  }

  /// Request notification permission
  Future<bool> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
      return false;
    }
  }

  /// Request exact alarm permission (Android 12+)
  Future<bool> _requestExactAlarmPermission() async {
    try {
      // First try using permission_handler for Android 12+
      final alarmStatus = await Permission.scheduleExactAlarm.status;
      if (!alarmStatus.isGranted) {
        final result = await Permission.scheduleExactAlarm.request();
        if (result.isGranted) return true;
      } else {
        return true;
      }
      
      // Fallback: try flutter_local_notifications approach
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // Request the permission
        await androidPlugin.requestExactAlarmsPermission();
        
        // Verify it's granted
        final canSchedule = await androidPlugin.canScheduleExactNotifications();
        return canSchedule ?? false;
      }
    } catch (e) {
      debugPrint('Error requesting exact alarm permission: $e');
    }
    return false;
  }

  /// Request battery optimization exemption
  Future<bool> _requestBatteryOptimization() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        final result = await Permission.ignoreBatteryOptimizations.request();
        return result.isGranted;
      }
      return status.isGranted;
    } catch (e) {
      debugPrint('Error requesting battery optimization: $e');
      return false;
    }
  }

  /// Check schedule exact alarm capability
  Future<bool> _checkScheduleExactAlarm() async {
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        return await androidPlugin.canScheduleExactNotifications() ?? false;
      }
    } catch (e) {
      debugPrint('Error checking schedule exact alarm: $e');
    }
    return false;
  }

  /// Check full screen intent capability
  Future<bool> _checkFullScreenIntent() async {
    // Full screen intent is declared in manifest, just verify notifications work
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }

  /// Request phone call permission
  Future<bool> _requestPhonePermission() async {
    try {
      final status = await Permission.phone.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('Error requesting phone permission: $e');
      return false;
    }
  }

  /// Request location permission (for customer maps)
  Future<bool> _requestLocationPermission() async {
    try {
      final status = await Permission.locationWhenInUse.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      return false;
    }
  }

  /// Request storage permission (for backup/export)
  Future<bool> _requestStoragePermission() async {
    try {
      // Check if already granted
      if (await Permission.storage.isGranted || 
          await Permission.manageExternalStorage.isGranted) {
        return true;
      }
      
      // Request storage permission
      final status = await Permission.storage.request();
      if (status.isGranted) return true;
      
      // For Android 11+, try manage external storage
      final manageStatus = await Permission.manageExternalStorage.request();
      return manageStatus.isGranted;
    } catch (e) {
      debugPrint('Error requesting storage permission: $e');
      return false;
    }
  }

  /// 🎨 Professional permission dialog with detailed status
  Future<void> _showProfessionalPermissionDialog(
    BuildContext context,
    AppPermissionStatus status,
  ) async {
    // Check if we should show dialog (rate limiting)
    if (!await _shouldShowPermissionDialog()) {
      debugPrint('Permission dialog rate limited, skipping...');
      return;
    }

    if (!context.mounted) return;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.security, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Permissions Required',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Permission Score Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: status.score >= 80 
                      ? Colors.green.shade100 
                      : status.score >= 50 
                          ? Colors.orange.shade100 
                          : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Permission Score: ${status.score}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: status.score >= 80 
                        ? Colors.green.shade800 
                        : status.score >= 50 
                            ? Colors.orange.shade800 
                            : Colors.red.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'For the app to work properly, please enable these permissions:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              
              // Critical - Alarm Permissions
              const Text('🔔 Critical (Alarms)', 
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 4),
              _buildPermissionRow(
                'Notifications',
                status.notification,
                Icons.notifications_active,
                'Show reminder alerts',
              ),
              _buildPermissionRow(
                'Exact Alarms',
                status.exactAlarm,
                Icons.alarm,
                'Precise reminder timing',
              ),
              _buildPermissionRow(
                'Battery Optimization',
                status.batteryOptimization,
                Icons.battery_charging_full,
                'Prevent blocking reminders',
              ),
              
              const SizedBox(height: 8),
              
              // App Features
              const Text('📱 App Features', 
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(height: 4),
              _buildPermissionRow(
                'Phone Calls',
                status.phone,
                Icons.phone,
                'Call customers directly',
              ),
              _buildPermissionRow(
                'Location',
                status.location,
                Icons.location_on,
                'Customer location maps',
              ),
              _buildPermissionRow(
                'Storage',
                status.storage,
                Icons.folder,
                'Backup and export data',
              ),
              
              const SizedBox(height: 12),
              if (status.missingPermissions.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade700, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Tap Settings to enable missing permissions',
                          style: TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    // Record this request
    await _recordPermissionRequest();
  }

  Widget _buildPermissionRow(String name, bool granted, IconData icon, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: granted ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: granted ? Colors.green : Colors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      granted ? Icons.check_circle : Icons.cancel,
                      size: 16,
                      color: granted ? Colors.green : Colors.red,
                    ),
                  ],
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Rate limiting for permission dialogs
  Future<bool> _shouldShowPermissionDialog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRequest = prefs.getString(_lastPermissionRequestKey);
      final requestCount = prefs.getInt(_permissionRequestCountKey) ?? 0;
      
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day).toIso8601String();
      
      // Reset count if it's a new day
      if (lastRequest != today) {
        return true;
      }
      
      // Check if under daily limit
      return requestCount < _maxDailyRequests;
    } catch (e) {
      return true;
    }
  }

  Future<void> _recordPermissionRequest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day).toIso8601String();
      
      final lastRequest = prefs.getString(_lastPermissionRequestKey);
      int count = prefs.getInt(_permissionRequestCountKey) ?? 0;
      
      if (lastRequest != today) {
        count = 0;
      }
      
      await prefs.setString(_lastPermissionRequestKey, today);
      await prefs.setInt(_permissionRequestCountKey, count + 1);
    } catch (e) {
      debugPrint('Error recording permission request: $e');
    }
  }

  /// Quick check all permissions without requesting
  Future<AppPermissionStatus> checkAllPermissions() async {
    final status = AppPermissionStatus();
    
    // Alarm permissions
    status.notification = (await Permission.notification.status).isGranted;
    
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        status.exactAlarm = await androidPlugin.canScheduleExactNotifications() ?? false;
        status.scheduleExactAlarm = status.exactAlarm;
      }
    } catch (e) {
      status.exactAlarm = false;
    }
    
    status.batteryOptimization = (await Permission.ignoreBatteryOptimizations.status).isGranted;
    status.fullScreenIntent = status.notification;
    status.wakeLock = true;
    
    // App feature permissions
    status.phone = (await Permission.phone.status).isGranted;
    status.location = (await Permission.locationWhenInUse.status).isGranted;
    status.storage = (await Permission.storage.status).isGranted || 
                     (await Permission.manageExternalStorage.status).isGranted;
    
    return status;
  }

  /// Open app settings
  Future<void> openSettings() async {
    await openAppSettings();
  }

  /// Legacy compatibility method
  Future<Map<String, bool>> requestAllAlarmPermissions(BuildContext context) async {
    final status = await requestAllPermissions(context);
    return status.toMap();
  }

  String getPermissionStatusString(Map<String, bool> permissions) {
    final sb = StringBuffer();
    sb.writeln('Permission Status:');
    sb.writeln('  Notifications: ${permissions['notification'] == true ? '✅' : '❌'}');
    sb.writeln('  Exact Alarms: ${permissions['exactAlarm'] == true ? '✅' : '❌'}');
    sb.writeln('  Battery Opt: ${permissions['batteryOptimization'] == true ? '✅' : '❌'}');
    return sb.toString();
  }
}

/// 📊 App Permission Status Container
/// Named AppPermissionStatus to avoid collision with permission_handler's PermissionStatus enum
class AppPermissionStatus {
  bool notification = false;
  bool exactAlarm = false;
  bool batteryOptimization = false;
  bool scheduleExactAlarm = false;
  bool fullScreenIntent = false;
  bool wakeLock = false;
  bool phone = false;          // Phone call permission
  bool location = false;       // Maps/location permission
  bool storage = false;        // Storage for backup/export

  /// Check if all critical permissions for alarms are granted
  bool get hasCriticalPermissions => notification && exactAlarm;

  /// Check if alarm-related permissions are granted
  bool get hasAlarmPermissions => 
      notification && exactAlarm && batteryOptimization;

  /// Check if all permissions are granted
  bool get hasAllPermissions =>
      notification &&
      exactAlarm &&
      batteryOptimization &&
      scheduleExactAlarm &&
      fullScreenIntent &&
      wakeLock &&
      phone &&
      location &&
      storage;

  /// Get overall status score (0-100)
  /// Weights adjusted to sum to exactly 100
  int get score {
    int total = 0;
    if (notification) total += 25; // Most critical for alarms
    if (exactAlarm) total += 25; // Most critical for alarms
    if (batteryOptimization) total += 15;
    if (scheduleExactAlarm) total += 5;
    if (fullScreenIntent) total += 5;
    if (wakeLock) total += 5;
    if (phone) total += 5;
    if (location) total += 10; // Increased from 5 to make total 100
    if (storage) total += 5;
    return total;
  }

  /// Get list of missing permissions (includes all tracked permissions for consistency)
  List<String> get missingPermissions {
    final missing = <String>[];
    if (!notification) missing.add('Notifications');
    if (!exactAlarm) missing.add('Exact Alarms');
    if (!batteryOptimization) missing.add('Battery Optimization');
    if (!scheduleExactAlarm) missing.add('Schedule Exact Alarm');
    if (!fullScreenIntent) missing.add('Full Screen Intent');
    if (!wakeLock) missing.add('Wake Lock');
    if (!phone) missing.add('Phone Calls');
    if (!location) missing.add('Location');
    if (!storage) missing.add('Storage');
    return missing;
  }

  Map<String, bool> toMap() => {
        'notification': notification,
        'exactAlarm': exactAlarm,
        'batteryOptimization': batteryOptimization,
        'scheduleExactAlarm': scheduleExactAlarm,
        'fullScreenIntent': fullScreenIntent,
        'wakeLock': wakeLock,
        'phone': phone,
        'location': location,
        'storage': storage,
      };
}
