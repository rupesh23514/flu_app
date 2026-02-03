import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'app.dart';
import 'core/services/bootstrap_service.dart';
import 'core/providers/language_provider.dart';
import 'features/authentication/providers/auth_provider.dart';
import 'features/loan_management/providers/loan_provider.dart';
import 'features/customer_management/providers/customer_provider.dart';

// Global key for showing dialogs from main
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global reference to AuthProvider for lifecycle management
AuthProvider? globalAuthProvider;

void main() async {
  // Run app in zone to catch async errors
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Global Flutter error handler for UI errors
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        debugPrint('Flutter Error: ${details.exceptionAsString()}');
        debugPrint('Stack trace: ${details.stack}');
      }
      // Don't rethrow - gracefully handle the error
    };
    
    // Initialize all services via BootstrapService
    await BootstrapService.instance.initialize();
    
    // Create AuthProvider instance to share globally
    final authProvider = AuthProvider();
    globalAuthProvider = authProvider;
    
    // Set system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider.value(value: authProvider),
          ChangeNotifierProvider(create: (_) => LoanProvider()),
          ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ],
        child: const FinancialApp(),
      ),
    );
  }, (error, stackTrace) {
    // Global async error handler - only log in debug mode
    if (kDebugMode) {
      debugPrint('Uncaught async error: $error');
      debugPrint('Stack trace: $stackTrace');
    }
    // Log but don't crash the app
  });
}