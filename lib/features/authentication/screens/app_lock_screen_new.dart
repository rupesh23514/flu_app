import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/restore_helper_service.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final RestoreHelperService _restoreHelper = RestoreHelperService.instance;
  final List<String> _pin = [];
  final List<String> _confirmPin = [];
  
  bool _isCreatingPin = false;
  bool _isConfirmingPin = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isLoading = true;
  bool _isRestoringFromCloud = false;
  
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
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _checkPinStatus() async {
    final hasPin = await _authService.hasPin();
    
    if (!mounted) return; // Safety check for async operation
    
    setState(() {
      _isCreatingPin = !hasPin;
      _isLoading = false;
    });
  }
  
  /// Restore data from Google Drive - for fresh installs
  Future<void> _restoreFromCloud() async {
    if (_isRestoringFromCloud) return;
    
    setState(() {
      _isRestoringFromCloud = true;
      _hasError = false;
      _errorMessage = '';
    });
    
    // Use centralized restore helper to avoid code duplication
    final result = await _restoreHelper.restoreFromGoogleDrive(signInIfNeeded: true);
    
    if (!mounted) return;
    
    setState(() {
      _isRestoringFromCloud = false;
    });
    
    if (result.success) {
      // Show success message and continue with PIN setup
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Data restored successfully! Now create your PIN.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      setState(() {
        _hasError = true;
        _errorMessage = result.errorMessage ?? 'Restore failed. Please try again.';
      });
    }
  }

  void _onNumberPressed(String number) {
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
        if (!success && mounted) {
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
      _showError(authProvider.errorMessage ?? 'Wrong PIN');
      _shakeController.forward().then((_) => _shakeController.reset());
      setState(() {
        _pin.clear();
      });
    }
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
            
            // PIN Dots
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeAnimation.value * (_hasError ? 1 : 0), 0),
                  child: _buildPinDots(),
                );
              },
            ),
            
            // Error Message
            if (_hasError) ...[
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
            
            // Restore from Cloud button (shown only when creating PIN for first time)
            if (_isCreatingPin && !_isConfirmingPin) ...[
              const SizedBox(height: 20),
              _buildRestoreFromCloudButton(),
            ],
            
            const Spacer(),
            
            // Number Pad (hide when restoring)
            if (!_isRestoringFromCloud)
              _buildNumberPad()
            else
              const Padding(
                padding: EdgeInsets.all(48),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text(
                      'Restoring your data...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ],
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
      subtitle = 'Enter your PIN to continue';
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
            children: ['1', '2', '3'].map((n) => _buildNumberButton(n, buttonSize, fontSize)).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['4', '5', '6'].map((n) => _buildNumberButton(n, buttonSize, fontSize)).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['7', '8', '9'].map((n) => _buildNumberButton(n, buttonSize, fontSize)).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Empty space placeholder
              SizedBox(width: buttonSize, height: buttonSize),
              _buildNumberButton('0', buttonSize, fontSize),
              _buildIconButton(Icons.backspace_outlined, _onBackspace, buttonSize),
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
  
  /// Build the "Restore from Cloud" button for fresh installs
  Widget _buildRestoreFromCloudButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          const Divider(height: 32),
          Text(
            'Have existing data?',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isRestoringFromCloud ? null : _restoreFromCloud,
              icon: const Icon(Icons.cloud_download_outlined, size: 20),
              label: const Text('Restore from Google Drive'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to recover your backed up data',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.6),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
