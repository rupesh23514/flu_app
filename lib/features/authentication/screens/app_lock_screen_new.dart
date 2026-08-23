import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../../../core/services/auth_service.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final List<String> _pin = [];
  final List<String> _confirmPin = [];

  bool _isCreatingPin = false;
  bool _isConfirmingPin = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isLoading = true;

  // Lockout state
  bool _isLockedOut = false;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _checkPinStatus();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _checkPinStatus() async {
    final hasPin = await _authService.hasPin();
    final needsAccountSetup = await _authService.needsAccountSetup();

    if (!mounted) return;

    // If PIN exists but account setup not complete, go to account choice
    if (hasPin && needsAccountSetup) {
      Navigator.of(context).pushReplacementNamed('/account-choice');
      return;
    }

    // Check lockout status for existing PIN
    if (hasPin) {
      await _checkLockoutStatus();
      if (!mounted) return; // Guard after async call
    }

    setState(() {
      _isCreatingPin = !hasPin;
      _isLoading = false;
    });
  }

  Future<void> _checkLockoutStatus() async {
    final lockoutStatus = await _authService.getLockoutStatus();
    if (lockoutStatus.isLockedOut && mounted) {
      setState(() {
        _isLockedOut = true;
        _lockoutSeconds = lockoutStatus.remainingSeconds;
      });
      _startLockoutTimer();
    }
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        // Check before decrementing to prevent negative values
        if (_lockoutSeconds <= 1) {
          _isLockedOut = false;
          _lockoutSeconds = 0;
          timer.cancel();
        } else {
          _lockoutSeconds--;
        }
      });
    });
  }

  void _onNumberPressed(String number) {
    // Block input if locked out
    if (_isLockedOut) return;

    HapticFeedback.lightImpact();

    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    if (_isConfirmingPin) {
      if (_confirmPin.length < 4) {
        setState(() {
          _confirmPin.add(number);
        });
        if (_confirmPin.length == 4) {
          _verifyConfirmPin();
        }
      }
    } else {
      if (_pin.length < 4) {
        setState(() {
          _pin.add(number);
        });
        if (_pin.length == 4) {
          if (_isCreatingPin) {
            _proceedToConfirm();
          } else {
            _verifyPin();
          }
        }
      }
    }
  }

  void _onBackspace() {
    HapticFeedback.lightImpact();

    setState(() {
      if (_isConfirmingPin && _confirmPin.isNotEmpty) {
        _confirmPin.removeLast();
      } else if (_pin.isNotEmpty) {
        _pin.removeLast();
      }
    });
  }

  void _proceedToConfirm() {
    setState(() {
      _isConfirmingPin = true;
    });
  }

  Future<void> _verifyConfirmPin() async {
    if (_pin.join() == _confirmPin.join()) {
      // PINs match, save it using AuthProvider
      if (mounted) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final success = await authProvider.setupPin(_pin.join());
        if (success && mounted) {
          // Navigate to account choice screen instead of dashboard
          Navigator.of(context).pushReplacementNamed('/account-choice');
        } else if (!success && mounted) {
          _showError('Error creating PIN');
        }
      }
    } else {
      _showError('PIN does not match');
      _shakeController.forward().then((_) => _shakeController.reset());
      setState(() {
        _confirmPin.clear();
      });
    }
  }

  Future<void> _verifyPin() async {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.authenticateWithPin(_pin.join());
    if (!success && mounted) {
      // Check if we're now locked out
      if (authProvider.isLockedOut) {
        setState(() {
          _isLockedOut = true;
          _lockoutSeconds = authProvider.lockoutSeconds;
        });
        _startLockoutTimer();
      }
      _showError(authProvider.errorMessage ?? 'Wrong PIN');
      _shakeController.forward().then((_) => _shakeController.reset());
      setState(() {
        _pin.clear();
      });
    }
    // Note: Navigation on success is handled by Consumer<AuthProvider> in app.dart
  }

  void _showError(String message) {
    HapticFeedback.heavyImpact();
    setState(() {
      _hasError = true;
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Logo and Title
            _buildHeader(),

            const SizedBox(height: 48),

            // Lockout indicator
            if (_isLockedOut) ...[
              _buildLockoutIndicator(),
              const SizedBox(height: 24),
            ],

            // PIN Dots (dimmed when locked out)
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset:
                      Offset(_shakeAnimation.value * (_hasError ? 1 : 0), 0),
                  child: Opacity(
                    opacity: _isLockedOut ? 0.5 : 1.0,
                    child: _buildPinDots(),
                  ),
                );
              },
            ),

            // Error Message
            if (_hasError && !_isLockedOut) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            const Spacer(),

            // Number Pad (disabled when locked out)
            Opacity(
              opacity: _isLockedOut ? 0.5 : 1.0,
              child: IgnorePointer(
                ignoring: _isLockedOut,
                child: _buildNumberPad(),
              ),
            ),

            const SizedBox(height: 24),

            const Spacer(),

            // Version info
            Text(
              'Version 1.0.0',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLockoutIndicator() {
    final minutes = _lockoutSeconds ~/ 60;
    final seconds = _lockoutSeconds % 60;
    final timeString = minutes > 0
        ? '${minutes}m ${seconds.toString().padLeft(2, '0')}s'
        : '${seconds}s';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.lock_clock,
            color: AppColors.error,
            size: 32,
          ),
          const SizedBox(height: 8),
          const Text(
            'Too Many Attempts',
            style: TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try again in $timeString',
            style: TextStyle(
              color: AppColors.error.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    String title;
    String subtitle;

    if (_isCreatingPin) {
      if (_isConfirmingPin) {
        title = 'Confirm PIN';
        subtitle = 'Re-enter your 4-digit PIN';
      } else {
        title = 'Create PIN';
        subtitle = 'Enter a 4-digit PIN to secure your app';
      }
    } else {
      title = 'Welcome Back';
      subtitle = _isLockedOut
          ? 'Account temporarily locked'
          : 'Enter your PIN to continue';
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = screenWidth < 360 ? 60.0 : 80.0;
    final titleSize = screenWidth < 360 ? 24.0 : 28.0;

    return Column(
      children: [
        // App Icon
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(iconSize / 4),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Icon(
            Icons.account_balance_wallet,
            size: iconSize / 2,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 16,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPinDots() {
    final currentPin = _isConfirmingPin ? _confirmPin : _pin;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isFilled = index < currentPin.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled
                ? (_hasError ? AppColors.error : AppColors.primary)
                : Colors.transparent,
            border: Border.all(
              color: _hasError
                  ? AppColors.error
                  : (isFilled ? AppColors.primary : AppColors.textSecondary),
              width: 2,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildNumberPad() {
    // Calculate dynamic padding based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 24.0 : 48.0;
    final buttonSize = screenWidth < 360 ? 60.0 : 72.0;
    final fontSize = screenWidth < 360 ? 24.0 : 28.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['1', '2', '3']
                .map((n) => _buildNumberButton(n, buttonSize, fontSize))
                .toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['4', '5', '6']
                .map((n) => _buildNumberButton(n, buttonSize, fontSize))
                .toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['7', '8', '9']
                .map((n) => _buildNumberButton(n, buttonSize, fontSize))
                .toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Empty space placeholder
              SizedBox(width: buttonSize, height: buttonSize),
              _buildNumberButton('0', buttonSize, fontSize),
              _buildIconButton(
                  Icons.backspace_outlined, _onBackspace, buttonSize),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumberButton(String number, double size, double fontSize) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onNumberPressed(number),
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surfaceContainer,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap, double size) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              icon,
              size: size * 0.39,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
