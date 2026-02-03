// ignore_for_file: unused_element
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/google_drive_service.dart';
import '../../settings/screens/settings_screen.dart';
import '../../reports/screens/reports_screen.dart';
import '../../calendar/screens/calendar_screen.dart';
import '../../calculator/screens/calculator_screen.dart';
import '../../customers/screens/customer_groups_screen.dart';
import '../../backup/screens/backup_screen.dart';
import '../../transactions/screens/transaction_summary_screen.dart';

class SidebarMenu extends StatefulWidget {
  const SidebarMenu({super.key});

  @override
  State<SidebarMenu> createState() => _SidebarMenuState();
}

class _SidebarMenuState extends State<SidebarMenu> {
  final GoogleDriveService _driveService = GoogleDriveService.instance;
  bool _isGoogleSignedIn = false;
  bool _hasInternet = true;

  @override
  void initState() {
    super.initState();
    _loadBackupStatus();
    _checkConnectivity();
  }

  Future<void> _loadBackupStatus() async {
    await _driveService.initialize();
    if (mounted) {
      setState(() {
        _isGoogleSignedIn = _driveService.isSignedIn;
      });
    }
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _hasInternet = result != ConnectivityResult.none;
      });
    }
    
    Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) {
        setState(() {
          _hasInternet = result != ConnectivityResult.none;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context),
            
            const Divider(height: 1),
            
            // Menu Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildSectionHeader('MAIN'),
                  _buildMenuItem(
                    context,
                    icon: Icons.home,
                    title: 'Home',
                    isSelected: true,
                    onTap: () => Navigator.pop(context),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.calendar_month,
                    title: 'Calendar',
                    onTap: () => _navigateTo(context, const CalendarScreen()),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.bar_chart,
                    title: 'Reports',
                    onTap: () => _navigateTo(context, const ReportsScreen()),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.receipt_long,
                    title: 'Collection Summary',
                    onTap: () => _navigateTo(context, const TransactionSummaryScreen()),
                  ),
                  
                  const SizedBox(height: 8),
                  _buildSectionHeader('TOOLS'),
                  _buildMenuItem(
                    context,
                    icon: Icons.calculate,
                    title: 'Calculator',
                    onTap: () => _navigateTo(context, const CalculatorScreen()),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.group,
                    title: 'Customer Groups',
                    onTap: () => _navigateTo(context, const CustomerGroupsScreen()),
                  ),
                  
                  const SizedBox(height: 8),
                  _buildSectionHeader('SETTINGS'),
                  _buildMenuItem(
                    context,
                    icon: Icons.settings,
                    title: 'Settings',
                    onTap: () => _navigateTo(context, const SettingsScreen()),
                  ),
                ],
              ),
            ),
            
            // Footer
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupMenuItem(BuildContext context) {
    Widget? statusIndicator;
    
    if (!_hasInternet) {
      statusIndicator = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 12, color: AppColors.error),
            SizedBox(width: 4),
            Text(
              'Offline',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    } else if (_isGoogleSignedIn) {
      statusIndicator = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 12, color: AppColors.success),
            SizedBox(width: 4),
            Text(
              'Synced',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.success,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    } else {
      statusIndicator = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 12, color: AppColors.warning),
            SizedBox(width: 4),
            Text(
              'Not synced',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return _buildMenuItem(
      context,
      icon: Icons.cloud_upload,
      title: 'Backup',
      onTap: () => _navigateTo(context, const BackupScreen()),
      trailing: statusIndicator,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Loan Book',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Financial Management',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Pro Version',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    bool isSelected = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryLight : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 15,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        dense: true,
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.textSecondary.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(
                Icons.security,
                size: 16,
                color: AppColors.success,
              ),
              SizedBox(width: 8),
              Text(
                'Data encrypted & secure',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Version 1.0.0',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.pop(context); // Close drawer first
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _showHelpDialog(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHelpItem(Icons.email, 'Email: support@loanbook.app'),
            const SizedBox(height: 12),
            _buildHelpItem(Icons.phone, 'Phone: +91 XXXXX XXXXX'),
            const SizedBox(height: 12),
            _buildHelpItem(Icons.chat, 'WhatsApp: +91 XXXXX XXXXX'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
