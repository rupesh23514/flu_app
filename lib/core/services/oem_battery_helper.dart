import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OEM Battery Helper - Guides users on device-specific battery optimization settings
/// This is critical for alarm reliability on phones with aggressive battery management
class OemBatteryHelper {
  static final OemBatteryHelper _instance = OemBatteryHelper._internal();
  static OemBatteryHelper get instance => _instance;
  OemBatteryHelper._internal();

  static const _serviceChannel = MethodChannel('flu_app/foreground_service');
  static const _oemChannel = MethodChannel('flu_app/oem_settings');
  static const String _shownOemGuideKey = 'oem_battery_guide_shown';
  static const String _autostartPromptedKey = 'oem_autostart_prompted';

  /// Get the device manufacturer
  Future<String> getDeviceManufacturer() async {
    try {
      final result = await _serviceChannel.invokeMethod<String>('getDeviceManufacturer');
      return result?.toLowerCase() ?? 'unknown';
    } catch (e) {
      debugPrint('Error getting manufacturer: $e');
      return 'unknown';
    }
  }

  /// Start the foreground service for reliable alarms
  Future<bool> startForegroundService() async {
    try {
      final result = await _serviceChannel.invokeMethod<bool>('startForegroundService');
      debugPrint('✅ Foreground service started: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ Error starting foreground service: $e');
      return false;
    }
  }

  /// Stop the foreground service
  Future<bool> stopForegroundService() async {
    try {
      final result = await _serviceChannel.invokeMethod<bool>('stopForegroundService');
      return result ?? false;
    } catch (e) {
      debugPrint('Error stopping foreground service: $e');
      return false;
    }
  }

  /// Check if OEM battery guide has been shown
  Future<bool> hasShownOemGuide() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_shownOemGuideKey) ?? false;
  }

  /// Mark OEM battery guide as shown
  Future<void> markOemGuideShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shownOemGuideKey, true);
  }

  /// Check if autostart prompt has been shown
  Future<bool> hasPromptedAutostart() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autostartPromptedKey) ?? false;
  }

  /// Mark autostart as prompted
  Future<void> markAutostartPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autostartPromptedKey, true);
  }

  /// Open device-specific autostart settings (Vivo, Xiaomi, Oppo, Huawei, etc.)
  /// Returns true if OEM-specific settings were opened, false if fell back to app settings
  Future<bool> openAutoStartSettings() async {
    try {
      final result = await _oemChannel.invokeMethod<bool>('openAutoStartSettings');
      debugPrint('📱 Autostart settings opened: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ Error opening autostart settings: $e');
      return false;
    }
  }

  /// Open battery optimization settings
  Future<bool> openBatterySettings() async {
    try {
      final result = await _oemChannel.invokeMethod<bool>('openBatterySettings');
      debugPrint('🔋 Battery settings opened: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ Error opening battery settings: $e');
      return false;
    }
  }

  /// Open app-specific settings
  Future<bool> openAppSettings() async {
    try {
      final result = await _oemChannel.invokeMethod<bool>('openAppSettings');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ Error opening app settings: $e');
      return false;
    }
  }

  /// Request ignore battery optimization (shows system dialog)
  Future<bool> requestIgnoreBatteryOptimization() async {
    try {
      final result = await _oemChannel.invokeMethod<bool>('requestIgnoreBatteryOptimization');
      debugPrint('🔋 Battery optimization request: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ Error requesting battery optimization: $e');
      return false;
    }
  }

  /// Check if this is an aggressive OEM (Vivo, Xiaomi, Huawei, etc.)
  Future<bool> isAggressiveOem() async {
    final manufacturer = await getDeviceManufacturer();
    final aggressiveOems = [
      'vivo', 'iqoo', 'xiaomi', 'redmi', 'poco', 
      'huawei', 'honor', 'oppo', 'realme', 'oneplus'
    ];
    return aggressiveOems.any((oem) => manufacturer.contains(oem));
  }

  /// Check if device is Vivo/iQOO (most aggressive)
  Future<bool> isVivoDevice() async {
    final manufacturer = await getDeviceManufacturer();
    return manufacturer.contains('vivo') || manufacturer.contains('iqoo');
  }

  /// Auto-configure for aggressive OEMs - call this on app startup
  /// Silently requests permissions without showing dialogs
  Future<void> autoConfigureForOem(BuildContext context) async {
    // Check if already prompted
    final prompted = await hasPromptedAutostart();
    if (prompted) return;

    final manufacturer = await getDeviceManufacturer();
    debugPrint('📱 Device manufacturer: $manufacturer');

    // Mark as prompted first to avoid triggering again
    await markAutostartPrompted();

    // For Vivo/iQOO (most aggressive), silently open autostart settings
    if (manufacturer.contains('vivo') || manufacturer.contains('iqoo')) {
      debugPrint('⚠️ Vivo/iQOO device detected - configuring autostart');
      
      // Silently open autostart settings
      await openAutoStartSettings();
      
      // Brief delay then request battery optimization exemption
      await Future.delayed(const Duration(milliseconds: 500));
      await requestIgnoreBatteryOptimization();
    } 
    // For other aggressive OEMs, just request battery optimization silently
    else if (await isAggressiveOem()) {
      await requestIgnoreBatteryOptimization();
    }
  }

  /// Get OEM-specific battery optimization instructions
  OemBatteryInstructions getInstructions(String manufacturer) {
    switch (manufacturer.toLowerCase()) {
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        return OemBatteryInstructions(
          brand: 'Xiaomi/Redmi',
          steps: [
            'Open Settings → Apps → Manage apps',
            'Find "Money Lender" app',
            'Tap "Battery saver" → Select "No restrictions"',
            'Go back and tap "Autostart" → Enable it',
            'Open Security app → Battery → App Battery Saver',
            'Find "Money Lender" → Select "No restrictions"',
          ],
          criticalNote: 'Xiaomi has aggressive battery management. AutoStart must be enabled for alarms to work when app is closed.',
          iconColor: Colors.orange,
        );

      case 'samsung':
        return OemBatteryInstructions(
          brand: 'Samsung',
          steps: [
            'Open Settings → Battery and device care',
            'Tap "Battery" → "Background usage limits"',
            'Tap "Never sleeping apps" → Add "Money Lender"',
            'Go to Settings → Apps → Money Lender',
            'Tap "Battery" → Select "Unrestricted"',
          ],
          criticalNote: 'Samsung puts apps to sleep. Adding to "Never sleeping apps" is essential.',
          iconColor: Colors.blue,
        );

      case 'huawei':
      case 'honor':
        return OemBatteryInstructions(
          brand: 'Huawei/Honor',
          steps: [
            'Open Settings → Battery → App launch',
            'Find "Money Lender" → Disable automatic management',
            'Enable all three options: Auto-launch, Secondary launch, Run in background',
            'Go to Settings → Apps → Money Lender → Battery',
            'Select "Unrestricted"',
          ],
          criticalNote: 'Huawei has very aggressive power management. All three launch options must be enabled.',
          iconColor: Colors.red,
        );

      case 'oppo':
      case 'realme':
      case 'oneplus':
        return OemBatteryInstructions(
          brand: 'Oppo/Realme/OnePlus',
          steps: [
            'Open Settings → Battery → Battery optimization',
            'Find "Money Lender" → Select "Don\'t optimize"',
            'Go to Settings → Apps → Money Lender → Battery',
            'Select "Allow background activity"',
            'For OnePlus: Go to Settings → Battery → Battery optimization',
            'Tap ⋮ → Advanced optimization → Disable for Money Lender',
          ],
          criticalNote: 'ColorOS/OxygenOS may kill background apps. Disable all optimization for reliable alarms.',
          iconColor: Colors.green,
        );

      case 'vivo':
      case 'iqoo':
        return OemBatteryInstructions(
          brand: 'Vivo/iQOO',
          steps: [
            '1. Settings → Battery → High background power consumption → Enable for Money Lender',
            '2. Open i Manager → App Manager → Autostart Manager → Enable Money Lender',
            '3. i Manager → App Manager → Background App Management → Add Money Lender to Allow list',
            '4. Settings → Apps → Money Lender → Battery → Select "Unrestricted"',
            '5. Settings → Battery → More battery settings → Disable "Sleep standby optimization"',
            '6. In Recent Apps, long-press Money Lender → Lock the app',
          ],
          criticalNote: '⚠️ VIVO Y-SERIES USERS (Y200, Y100, etc.):\n'
              'Your phone has extra aggressive battery optimization!\n'
              '• MUST enable Autostart in i Manager\n'
              '• MUST add to Background App Management allow list\n'
              '• Lock the app in Recent Apps for 100% reliability',
          iconColor: Colors.deepPurple,
        );

      case 'asus':
        return OemBatteryInstructions(
          brand: 'ASUS',
          steps: [
            'Open Settings → Battery → PowerMaster',
            'Tap "Auto-start Manager" → Enable "Money Lender"',
            'Go to Settings → Apps → Money Lender → Battery',
            'Select "No restrictions"',
          ],
          criticalNote: 'ASUS PowerMaster may block alarms. Enable in Auto-start Manager.',
          iconColor: Colors.teal,
        );

      default:
        return OemBatteryInstructions(
          brand: 'Your Device',
          steps: [
            'Open Settings → Apps → Money Lender',
            'Tap "Battery" → Select "Unrestricted"',
            'Go to Settings → Battery → Battery optimization',
            'Find "Money Lender" → Select "Don\'t optimize"',
            'Look for "Auto-start" or "Background apps" in settings',
            'Enable background/autostart permission for Money Lender',
          ],
          criticalNote: 'For reliable alarms, disable all battery optimization for this app.',
          iconColor: Colors.grey,
        );
    }
  }

  /// Show OEM-specific battery optimization dialog
  Future<void> showOemBatteryDialog(BuildContext context) async {
    final manufacturer = await getDeviceManufacturer();
    final instructions = getInstructions(manufacturer);

    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.battery_alert, color: instructions.iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${instructions.brand} Battery Settings',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Important for Alarms!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                instructions.criticalNote,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Follow these steps:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...instructions.steps.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: instructions.iconColor.withValues(alpha: 0.2),
                      child: Text(
                        '${entry.key + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: instructions.iconColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              markOemGuideShown();
              Navigator.pop(context);
            },
            child: const Text('I\'ll do this later'),
          ),
          ElevatedButton(
            onPressed: () {
              markOemGuideShown();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: instructions.iconColor,
            ),
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// Data class for OEM-specific battery instructions
class OemBatteryInstructions {
  final String brand;
  final List<String> steps;
  final String criticalNote;
  final Color iconColor;

  OemBatteryInstructions({
    required this.brand,
    required this.steps,
    required this.criticalNote,
    required this.iconColor,
  });
}
