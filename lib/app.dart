import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'main.dart' show navigatorKey, globalAuthProvider;
import 'core/constants/app_routes.dart';
import 'core/constants/app_strings.dart';
import 'core/localization/app_localizations.dart';
import 'core/providers/language_provider.dart';
import 'core/services/alarm_service.dart';
import 'core/services/reminder_service.dart';
import 'core/services/permission_helper.dart';
import 'core/services/bootstrap_service.dart';
import 'core/services/oem_battery_helper.dart';
import 'shared/themes/app_theme.dart';
import 'shared/models/customer.dart';
import 'features/authentication/providers/auth_provider.dart';
import 'features/authentication/screens/app_lock_screen_new.dart';
import 'features/home/screens/home_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/calendar/screens/calendar_screen.dart';
import 'features/calendar/screens/alarm_full_screen.dart';
import 'features/calendar/widgets/alarm_popup_notification.dart';
import 'features/reports/screens/reports_screen.dart';
import 'features/calculator/screens/calculator_screen.dart';
import 'features/customers/screens/customer_groups_screen.dart';
import 'features/backup/screens/backup_screen.dart';
import 'features/loan_management/screens/payment_collection_screen.dart';
import 'features/customer_management/screens/add_borrower_screen.dart';

class FinancialApp extends StatefulWidget {
  const FinancialApp({super.key});

  @override
  State<FinancialApp> createState() => _FinancialAppState();
}

class _FinancialAppState extends State<FinancialApp> with WidgetsBindingObserver {
  StreamSubscription<AlarmData>? _alarmSubscription;
  AppLifecycleState _currentLifecycleState = AppLifecycleState.resumed;
  bool _permissionsRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForAlarms();
    // Request permissions and perform deferred update check after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissionsIfNeeded();
      // Deferred update check - doesn't block startup
      BootstrapService.instance.performDeferredUpdateCheck();
    });
  }

  /// 🏆 LEGENDARY Permission Request - handles all permissions professionally
  Future<void> _requestPermissionsIfNeeded() async {
    if (_permissionsRequested) return;
    _permissionsRequested = true;
    
    // Wait a moment for the app to fully load
    await Future.delayed(const Duration(seconds: 2));
    
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      // Use the enhanced permission helper
      final permissionStatus = await PermissionHelper.instance.requestAllPermissions(context);
      
      debugPrint('🏆 Permission Status Report:');
      debugPrint('   📱 Notifications: ${permissionStatus.notification ? "✅" : "❌"}');
      debugPrint('   ⏰ Exact Alarms: ${permissionStatus.exactAlarm ? "✅" : "❌"}');
      debugPrint('   🔋 Battery Opt: ${permissionStatus.batteryOptimization ? "✅" : "❌"}');
      debugPrint('   📊 Score: ${permissionStatus.score}/100');
      debugPrint('   ✨ Ready for alarms: ${permissionStatus.hasCriticalPermissions ? "YES" : "NO"}');
      
      // Verify pending alarms and reschedule any missing ones
      final rescheduledCount = await AlarmService.instance.verifyAndRescheduleAlarms();
      if (rescheduledCount > 0) {
        debugPrint('🔄 Rescheduled $rescheduledCount missing alarms');
      }
      
      // Auto-configure for aggressive OEMs (Vivo, Xiaomi, etc.)
      // This shows autostart settings on first run for Vivo devices
      if (context.mounted) {
        await OemBatteryHelper.instance.autoConfigureForOem(context);
      }
      
      // Show pending alarms summary
      final pendingAlarms = await AlarmService.instance.getPendingAlarms();
      debugPrint('📋 Pending alarms: ${pendingAlarms.length}');
      if (pendingAlarms.isNotEmpty) {
        for (final alarm in pendingAlarms.take(5)) {
          debugPrint('   - ${alarm.title} (ID: ${alarm.id})');
        }
        if (pendingAlarms.length > 5) {
          debugPrint('   ... and ${pendingAlarms.length - 5} more');
        }
      }
    }
  }

  /// Listen for alarm events and show appropriate UI based on phone state
  void _listenForAlarms() {
    _alarmSubscription = AlarmService.alarmStream.listen((alarmData) {
      debugPrint('Received alarm event: ${alarmData.title}');
      debugPrint('Current lifecycle state: $_currentLifecycleState');
      
      // Check if app is in foreground (phone is ON and app visible)
      if (_currentLifecycleState == AppLifecycleState.resumed) {
        // Phone is ON - show popup notification
        _showPopupNotification(alarmData);
      } else {
        // Phone is OFF or app in background - show full screen alarm
        _showFullScreenAlarm(alarmData);
      }
    });
  }

  /// Show popup notification when phone is ON
  void _showPopupNotification(AlarmData alarmData) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      AlarmPopupOverlay.show(
        context,
        alarmData,
        onTapToOpenFullScreen: () {
          // When user taps the popup, open full screen
          _showFullScreenAlarm(alarmData);
        },
        onSnooze: () {
          // Snooze the alarm
          _snoozeAlarm(alarmData);
        },
      );
    }
  }

  /// Show full-screen alarm when phone is OFF
  void _showFullScreenAlarm(AlarmData alarmData) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => AlarmFullScreen(
            title: alarmData.title,
            description: alarmData.description,
            scheduledTime: alarmData.scheduledTime,
            alarmId: alarmData.id,
            databaseId: alarmData.databaseId,  // Pass original database ID
          ),
        ),
      );
    }
  }

  /// Snooze the alarm for default duration - persists to database
  Future<void> _snoozeAlarm(AlarmData alarmData) async {
    // Use databaseId for database operations
    final dbId = alarmData.databaseId;
    
    // DATABASE SYNC: Update reminder time in database (this saves snooze time)
    try {
      await ReminderService.instance.snoozeReminder(dbId);
      debugPrint('✅ App: Reminder $dbId snoozed in DB');
    } catch (e) {
      debugPrint('⚠️ App: Could not update reminder in DB: $e');
    }
    
    // Also update in SharedPreferences for calendar sync
    final snoozeTime = DateTime.now().add(
      Duration(minutes: AlarmService.instance.defaultSnoozeMins),
    );
    await CalendarEventSync.updateEventTimeByAlarmId(dbId, snoozeTime);
    
    // Schedule new alarm notification for when snooze ends
    await AlarmService.instance.scheduleAlarm(
      id: dbId + 1000,  // New notification ID
      databaseId: dbId,  // Keep original database ID
      title: alarmData.title,
      description: alarmData.description,
      scheduledDateTime: snoozeTime,
      playSound: true,
      vibrate: true,
      fullScreenIntent: true,
    );
    
    debugPrint('Alarm snoozed for ${AlarmService.instance.defaultSnoozeMins} minutes - saved to DB (dbId=$dbId)');
  }

  @override
  void dispose() {
    _alarmSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Track current lifecycle state for alarm handling
    _currentLifecycleState = state;
    
    // Use global AuthProvider reference for reliable access
    final authProvider = globalAuthProvider;
    if (authProvider == null) {
      return;
    }
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App going to background - record time for auto-lock timer
      authProvider.onAppPaused();
      debugPrint('🔒 SECURITY: App paused - timer started');
    } else if (state == AppLifecycleState.resumed) {
      // App coming back - check if auto-lock timer expired
      // If phone is already unlocked, only app lock is required (based on timer)
      if (authProvider.shouldAutoLock()) {
        authProvider.logout();
        debugPrint('🔐 SECURITY: Auto-lock timer expired - app locked');
      } else {
        debugPrint('🔓 SECURITY: App resumed within timer - no lock needed');
      }
      
      // Verify and reschedule any missing alarms when app resumes
      _verifyAlarmsOnResume();
    }
  }
  
  /// Verify alarms when app resumes from background
  void _verifyAlarmsOnResume() {
    // Execute asynchronously to prevent blocking the main thread during lifecycle changes
    // This prevents ANR when app resumes from background
    Future.microtask(() async {
      try {
        final rescheduled = await AlarmService.instance.verifyAndRescheduleAlarms();
        if (rescheduled > 0) {
          debugPrint('🔄 Rescheduled $rescheduled missing alarms on app resume');
        }
      } catch (e) {
        debugPrint('⚠️ Error verifying alarms on resume: $e');
        // Don't propagate error - graceful degradation
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageProvider>(
      builder: (context, languageProvider, child) {
        return Listener(
          // Detect user interactions to reset inactivity timer
          // Debouncing in AuthProvider prevents excessive timer restarts
          behavior: HitTestBehavior.translucent, // Don't block gestures
          onPointerDown: (_) {
            // Debounced in AuthProvider - won't cause performance issues
            globalAuthProvider?.updateActivity();
          },
          child: MaterialApp(
            title: AppStrings.appName,
            theme: AppTheme.lightTheme,
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            // RouteObserver for CalendarScreen to detect when it becomes visible
            navigatorObservers: [CalendarScreen.routeObserver],
            
            // Localization support
            locale: languageProvider.currentLocale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            
            home: Consumer<AuthProvider>(
              builder: (context, authProvider, child) {
                if (authProvider.isAuthenticated) {
                  return const HomeScreen();
                } else {
                  return const AppLockScreen();
                }
              },
            ),
            routes: {
              AppRoutes.settings: (context) => const SettingsScreen(),
              AppRoutes.paymentCollection: (context) => const PaymentCollectionScreen(),
              '/calendar': (context) => const CalendarScreen(),
              '/reports': (context) => const ReportsScreen(),
              '/calculator': (context) => const CalculatorScreen(),
              '/customer-groups': (context) => const CustomerGroupsScreen(),
              '/backup': (context) => const BackupScreen(),
            },
            onGenerateRoute: (settings) {
              // Handle routes with arguments
              if (settings.name == '/add-borrower' || settings.name == AppRoutes.addBorrower) {
                final customer = settings.arguments as Customer?;
                return MaterialPageRoute(
                  builder: (context) => AddBorrowerScreen(customer: customer),
                  settings: settings,
                );
              }
              return null;
            },
          ),
        );
      },
    );
  }
}