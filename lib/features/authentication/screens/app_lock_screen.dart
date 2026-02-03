import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../providers/auth_provider.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  bool _hasError = false;
  bool _isPinSetup = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isPinSetup = await authProvider.isPinSetup();
    
    setState(() {
      _isPinSetup = isPinSetup;
    });
  }

  Future<void> _authenticateWithPin() async {
    if (_pinController.text.length != 4) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      if (_isPinSetup) {
        // Verify PIN
        final isValid = await authProvider.verifyPin(_pinController.text);
        if (isValid) {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          }
        } else {
          setState(() {
            _hasError = true;
            _pinController.clear();
          });
        }
      } else {
        // Set up PIN
        await authProvider.setPin(_pinController.text);
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/dashboard');
        }
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _pinController.clear();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Authentication failed: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  size: 64,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // App Title
              Text(
                AppStrings.appName,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 48),
              
              // PIN Setup/Login Title
              Text(
                _isPinSetup ? 'Enter your PIN' : 'Set up your PIN',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 8),
              
              // Subtitle
              Text(
                _isPinSetup 
                  ? 'Please enter your 4-digit PIN to access the app'
                  : 'Create a 4-digit PIN to secure your financial data',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 48),
              
              // PIN Input
              PinCodeTextField(
                appContext: context,
                length: 4,
                controller: _pinController,
                obscureText: true,
                obscuringCharacter: '●',
                animationType: AnimationType.fade,
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(12),
                  fieldHeight: 60,
                  fieldWidth: 60,
                  activeFillColor: Colors.white,
                  inactiveFillColor: Colors.white,
                  selectedFillColor: AppColors.primary.withValues(alpha: 0.1),
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.outline,
                  selectedColor: AppColors.primary,
                  borderWidth: 2,
                ),
                enableActiveFill: true,
                keyboardType: TextInputType.number,
                errorAnimationController: null,
                onCompleted: (pin) {
                  _authenticateWithPin();
                },
                onChanged: (value) {
                  if (_hasError) {
                    setState(() {
                      _hasError = false;
                    });
                  }
                },
              ),
              
              if (_hasError) ...[
                const SizedBox(height: 16),
                const Text(
                  'Invalid PIN. Please try again.',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 14,
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              
              // Loading indicator
              if (_isLoading)
                const CircularProgressIndicator(
                  color: AppColors.primary,
                ),
              
              const Spacer(),
              
              // App version and security note
              const Column(
                children: [
                  Text(
                    'Secured with PIN Protection',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Version 1.1.0',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }
}