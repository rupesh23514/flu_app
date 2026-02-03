import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/auth_service.dart';

/// A widget that displays a balance amount with password-protected visibility toggle.
///
/// Shows the actual amount or "****" based on visibility state.
/// - Hiding: Instant (no password required)
/// - Revealing: Requires PIN verification via AlertDialog (uses app login PIN)
///
/// NOTE: Visibility state is SHARED across all SecureBalanceWidget instances.
/// When one is unlocked, ALL widgets show their values.
class SecureBalanceWidget extends StatefulWidget {
  final String value;
  final String label;
  final IconData icon;
  final TextStyle? valueStyle;
  final TextStyle? labelStyle;
  final Color iconColor;

  const SecureBalanceWidget({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.valueStyle,
    this.labelStyle,
    this.iconColor = Colors.white,
  });

  /// Static method to hide all secure balance widgets (e.g., on app background)
  static void hideAll() {
    _SecureBalanceWidgetState._sharedVisibility.value = false;
  }

  @override
  State<SecureBalanceWidget> createState() => _SecureBalanceWidgetState();
}

class _SecureBalanceWidgetState extends State<SecureBalanceWidget> {
  // SHARED visibility state across ALL SecureBalanceWidget instances
  static final ValueNotifier<bool> _sharedVisibility =
      ValueNotifier<bool>(false);

  final AuthService _authService = AuthService.instance;

  void _toggleVisibility() {
    if (_sharedVisibility.value) {
      // Hide immediately without password - affects ALL widgets
      _sharedVisibility.value = false;
    } else {
      // Show password dialog to reveal
      _showPasswordDialog();
    }
  }

  void _showPasswordDialog() {
    final passwordController = TextEditingController();
    String? errorMessage;
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.lock_outline,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Enter PIN'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your login PIN to view the balance',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  hintText: 'Enter 4-digit PIN',
                  prefixIcon: const Icon(Icons.pin),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: errorMessage,
                  errorStyle: const TextStyle(color: AppColors.error),
                ),
                onSubmitted: (_) async {
                  if (isVerifying) return;
                  // Capture navigator before async
                  final navigator = Navigator.of(dialogContext);
                  final enteredPin = passwordController.text;

                  debugPrint(
                      '🔐 SecureBalance: PIN entered (onSubmitted): ${enteredPin.length} chars');

                  setDialogState(() {
                    isVerifying = true;
                    errorMessage = null;
                  });

                  final isValid = await _authService.verifyPin(enteredPin);
                  debugPrint('🔐 SecureBalance: PIN valid = $isValid');

                  if (isValid) {
                    debugPrint(
                        '🔐 SecureBalance: Closing dialog and setting visibility to TRUE');
                    navigator.pop();
                    // Update shared visibility - affects ALL widgets
                    _sharedVisibility.value = true;
                    debugPrint(
                        '🔐 SecureBalance: _sharedVisibility.value = ${_sharedVisibility.value}');
                  } else {
                    debugPrint(
                        '🔐 SecureBalance: PIN incorrect, showing error');
                    setDialogState(() {
                      isVerifying = false;
                      errorMessage = 'Incorrect PIN. Try again.';
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isVerifying
                  ? null
                  : () async {
                      // Capture navigator before async
                      final navigator = Navigator.of(dialogContext);
                      final enteredPin = passwordController.text;

                      debugPrint(
                          '🔐 SecureBalance: PIN entered (Unlock button): ${enteredPin.length} chars');

                      setDialogState(() {
                        isVerifying = true;
                        errorMessage = null;
                      });

                      final isValid = await _authService.verifyPin(enteredPin);
                      debugPrint('🔐 SecureBalance: PIN valid = $isValid');

                      if (isValid) {
                        debugPrint(
                            '🔐 SecureBalance: Closing dialog and setting visibility to TRUE');
                        navigator.pop();
                        // Update shared visibility - affects ALL widgets
                        _sharedVisibility.value = true;
                        debugPrint(
                            '🔐 SecureBalance: _sharedVisibility.value = ${_sharedVisibility.value}');
                      } else {
                        debugPrint(
                            '🔐 SecureBalance: PIN incorrect, showing error');
                        setDialogState(() {
                          isVerifying = false;
                          errorMessage = 'Incorrect PIN. Try again.';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isVerifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultValueStyle = widget.valueStyle ??
        const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        );

    final defaultLabelStyle = widget.labelStyle ??
        TextStyle(
          fontSize: 11,
          color: Colors.white.withValues(alpha: 0.8),
        );

    // Use ValueListenableBuilder to react to shared visibility changes
    return ValueListenableBuilder<bool>(
      valueListenable: _sharedVisibility,
      builder: (context, isVisible, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with visibility toggle
            GestureDetector(
              onTap: _toggleVisibility,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.icon,
                    color: widget.iconColor.withValues(alpha: 0.9),
                    size: 22,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isVisible ? Icons.visibility : Icons.visibility_off,
                    color: widget.iconColor.withValues(alpha: 0.7),
                    size: 16,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Value (visible or hidden)
            GestureDetector(
              onTap: _toggleVisibility,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  isVisible ? widget.value : '****',
                  style: defaultValueStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Label
            Flexible(
              child: Text(
                widget.label,
                style: defaultLabelStyle,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}
