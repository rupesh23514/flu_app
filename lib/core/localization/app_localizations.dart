import 'package:flutter/material.dart';

/// Supported locales for the app
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en', ''), // English
    Locale('ta', ''), // Tamil
  ];

  // All translations
  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // App
      'app_name': 'Finance Manager',
      'version': 'Version',
      
      // Login
      'enter_pin': 'Enter PIN',
      'create_pin': 'Create PIN',
      'confirm_pin': 'Confirm PIN',
      'use_fingerprint': 'Use Fingerprint',
      'pin_mismatch': 'PIN does not match',
      'wrong_pin': 'Wrong PIN',
      'pin_created': 'PIN created successfully',
      
      // Home
      'loan_manager': 'Loan Manager',
      'search': 'Search',
      'total_given': 'Total Given',
      'todays_collection': "Today's Collection",
      'overdue': 'Overdue',
      'active': 'Active',
      'completed': 'Completed',
      'all': 'All',
      'filter': 'Filter',
      'no_loans': 'No loans found',
      'add_first_loan': 'Add your first loan',
      
      // Loan Card
      'due': 'Due',
      'balance': 'Balance',
      'paid': 'Paid',
      'collect': 'Collect',
      'details': 'Details',
      'call': 'Call',
      'overdue_days': 'Overdue by {days} days',
      
      // Add Loan
      'add_loan': 'Add Loan',
      'new_customer': 'New Customer',
      'existing_customer': 'Existing Customer',
      'select_customer': 'Select Customer',
      'customer_name': 'Customer Name',
      'phone_number': 'Phone Number',
      'address': 'Address',
      'aadhar_number': 'Book No (Optional)',
      'principal_amount': 'Principal Amount',
      'interest_rate': 'Interest Rate',
      'per_month': 'per month',
      'per_year': 'per year',
      'tenure': 'Tenure',
      'months': 'months',
      'start_date': 'Start Date',
      'notes': 'Notes',
      'save_loan': 'Save Loan',
      'loan_created': 'Loan created successfully',
      'customer_created': 'Customer created successfully',
      
      // Collect Payment
      'collect_payment': 'Collect Payment',
      'payment_amount': 'Payment Amount',
      'quick_amount': 'Quick Amount',
      'full_payment': 'Full',
      'payment_date': 'Payment Date',
      'record_payment': 'Record Payment',
      'generate_receipt': 'Generate Receipt',
      'payment_recorded': 'Payment recorded successfully',
      'loan_completed_msg': 'Loan fully paid! Congratulations!',
      
      // Loan Details
      'loan_details': 'Loan Details',
      'loan_info': 'Loan Info',
      'payments': 'Payments',
      'documents': 'Documents',
      'principal': 'Principal',
      'interest': 'Interest',
      'total_amount': 'Total Amount',
      'start': 'Start',
      'due_date': 'Due Date',
      'status': 'Status',
      'receipt': 'Receipt',
      'renew': 'Renew',
      'edit': 'Edit',
      'delete': 'Delete',
      'payment_history': 'Payment History',
      'no_payments': 'No payments yet',
      
      // Menu
      'home': 'Home',
      'calendar': 'Calendar',
      'reports': 'Reports',
      'calculator': 'Interest Calculator',
      'customer_groups': 'Customer Groups',
      'backup': 'Backup Data',
      'google_drive': 'Google Drive Sync',
      'whatsapp_backup': 'Share via WhatsApp',
      'settings': 'Settings',
      'about': 'About',
      'logout': 'Logout',
      
      // Settings
      'language': 'Language',
      'english': 'English',
      'tamil': 'Tamil',
      'security': 'Security',
      'change_pin': 'Change PIN',
      'fingerprint_login': 'Fingerprint Login',
      'auto_lock': 'Auto Lock',
      'auto_lock_time': 'Auto Lock Time',
      'voice_input': 'Voice Input',
      'voice_typing': 'Voice Typing',
      'voice_language': 'Voice Language',
      'notifications': 'Notifications',
      'daily_summary': 'Daily Summary',
      'due_reminders': 'Due Date Reminders',
      'overdue_alerts': 'Overdue Alerts',
      'data': 'Data',
      'auto_backup': 'Auto Backup',
      'export_data': 'Export All Data',
      'clear_data': 'Clear All Data',
      
      // Calendar
      'today': 'Today',
      'tomorrow': 'Tomorrow',
      'no_dues_today': 'No collections due today',
      
      // Reports
      'daily': 'Daily',
      'weekly': 'Weekly',
      'monthly': 'Monthly',
      'yearly': 'Yearly',
      'total_collected': 'Total Collected',
      'outstanding': 'Outstanding',
      'interest_earned': 'Interest Earned',
      'new_customers': 'New Customers',
      'loans_completed': 'Loans Completed',
      'overdue_loans': 'Overdue Loans',
      'download_pdf': 'Download PDF Report',
      'share_whatsapp': 'Share via WhatsApp',
      
      // Calculator
      'calculate': 'Calculate',
      'result': 'Result',
      'simple_interest': 'Simple',
      'compound_interest': 'Compound',
      'total_interest': 'Total Interest',
      'monthly_payment': 'Monthly Payment',
      
      // Customer Groups
      'customers': 'customers',
      'add_group': 'Add Group',
      'group_name': 'Group Name',
      'no_groups': 'No groups created',
      
      // Common
      'save': 'Save',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'yes': 'Yes',
      'no': 'No',
      'ok': 'OK',
      'error': 'Error',
      'success': 'Success',
      'warning': 'Warning',
      'loading': 'Loading...',
      'required': 'Required',
      'optional': 'Optional',
      'minutes': 'minutes',
    },
    'ta': {
      // App
      'app_name': 'நிதி மேலாளர்',
      'version': 'பதிப்பு',
      
      // Login
      'enter_pin': 'PIN உள்ளிடவும்',
      'create_pin': 'PIN உருவாக்கவும்',
      'confirm_pin': 'PIN உறுதிப்படுத்தவும்',
      'use_fingerprint': 'கைரேகை பயன்படுத்து',
      'pin_mismatch': 'PIN பொருந்தவில்லை',
      'wrong_pin': 'தவறான PIN',
      'pin_created': 'PIN வெற்றிகரமாக உருவாக்கப்பட்டது',
      
      // Home
      'loan_manager': 'கடன் மேலாளர்',
      'search': 'தேடு',
      'total_given': 'மொத்தம் கொடுத்தது',
      'todays_collection': 'இன்றைய வசூல்',
      'overdue': 'தாமதம்',
      'active': 'செயலில்',
      'completed': 'முடிந்தது',
      'all': 'அனைத்தும்',
      'filter': 'வடிகட்டு',
      'no_loans': 'கடன்கள் இல்லை',
      'add_first_loan': 'முதல் கடனைச் சேர்க்கவும்',
      
      // Loan Card
      'due': 'நிலுவை',
      'balance': 'மீதி',
      'paid': 'செலுத்தியது',
      'collect': 'வசூலி',
      'details': 'விவரங்கள்',
      'call': 'அழைப்பு',
      'overdue_days': '{days} நாட்கள் தாமதம்',
      
      // Add Loan
      'add_loan': 'கடன் சேர்',
      'new_customer': 'புதிய வாடிக்கையாளர்',
      'existing_customer': 'ஏற்கனவே உள்ள வாடிக்கையாளர்',
      'select_customer': 'வாடிக்கையாளரைத் தேர்ந்தெடுக்கவும்',
      'customer_name': 'வாடிக்கையாளர் பெயர்',
      'phone_number': 'தொலைபேசி எண்',
      'address': 'முகவரி',
      'aadhar_number': 'புத்தக எண் (விருப்பம்)',
      'principal_amount': 'அசல் தொகை',
      'interest_rate': 'வட்டி விகிதம்',
      'per_month': 'மாதத்திற்கு',
      'per_year': 'ஆண்டுக்கு',
      'tenure': 'காலம்',
      'months': 'மாதங்கள்',
      'start_date': 'தொடக்க தேதி',
      'notes': 'குறிப்புகள்',
      'save_loan': 'கடன் சேமி',
      'loan_created': 'கடன் வெற்றிகரமாக உருவாக்கப்பட்டது',
      'customer_created': 'வாடிக்கையாளர் வெற்றிகரமாக உருவாக்கப்பட்டது',
      
      // Collect Payment
      'collect_payment': 'பணம் வசூலி',
      'payment_amount': 'பணம் தொகை',
      'quick_amount': 'விரைவு தொகை',
      'full_payment': 'முழு',
      'payment_date': 'பணம் தேதி',
      'record_payment': 'பணம் பதிவு செய்',
      'generate_receipt': 'ரசீது உருவாக்கு',
      'payment_recorded': 'பணம் வெற்றிகரமாக பதிவு செய்யப்பட்டது',
      'loan_completed_msg': 'கடன் முழுமையாக செலுத்தப்பட்டது! வாழ்த்துக்கள்!',
      
      // Loan Details
      'loan_details': 'கடன் விவரங்கள்',
      'loan_info': 'கடன் தகவல்',
      'payments': 'பணங்கள்',
      'documents': 'ஆவணங்கள்',
      'principal': 'அசல்',
      'interest': 'வட்டி',
      'total_amount': 'மொத்த தொகை',
      'start': 'தொடக்கம்',
      'due_date': 'நிலுவை தேதி',
      'status': 'நிலை',
      'receipt': 'ரசீது',
      'renew': 'புதுப்பி',
      'edit': 'திருத்து',
      'delete': 'நீக்கு',
      'payment_history': 'பணம் வரலாறு',
      'no_payments': 'இன்னும் பணம் இல்லை',
      
      // Menu
      'home': 'முகப்பு',
      'calendar': 'நாட்காட்டி',
      'reports': 'அறிக்கைகள்',
      'calculator': 'வட்டி கணக்கி',
      'customer_groups': 'வாடிக்கையாளர் குழுக்கள்',
      'backup': 'காப்புப்பிரதி',
      'google_drive': 'Google Drive ஒத்திசைவு',
      'whatsapp_backup': 'WhatsApp வழியாக பகிர்',
      'settings': 'அமைப்புகள்',
      'about': 'பற்றி',
      'logout': 'வெளியேறு',
      
      // Settings
      'language': 'மொழி',
      'english': 'ஆங்கிலம்',
      'tamil': 'தமிழ்',
      'security': 'பாதுகாப்பு',
      'change_pin': 'PIN மாற்று',
      'fingerprint_login': 'கைரேகை உள்நுழைவு',
      'auto_lock': 'தானியங்கி பூட்டு',
      'auto_lock_time': 'தானியங்கி பூட்டு நேரம்',
      'voice_input': 'குரல் உள்ளீடு',
      'voice_typing': 'குரல் தட்டச்சு',
      'voice_language': 'குரல் மொழி',
      'notifications': 'அறிவிப்புகள்',
      'daily_summary': 'தினசரி சுருக்கம்',
      'due_reminders': 'நிலுவை நினைவூட்டல்கள்',
      'overdue_alerts': 'தாமத எச்சரிக்கைகள்',
      'data': 'தரவு',
      'auto_backup': 'தானியங்கி காப்புப்பிரதி',
      'export_data': 'அனைத்து தரவையும் ஏற்றுமதி செய்',
      'clear_data': 'அனைத்து தரவையும் அழி',
      
      // Calendar
      'today': 'இன்று',
      'tomorrow': 'நாளை',
      'no_dues_today': 'இன்று வசூல் இல்லை',
      
      // Reports
      'daily': 'தினசரி',
      'weekly': 'வாரந்தோறும்',
      'monthly': 'மாதந்தோறும்',
      'yearly': 'ஆண்டுதோறும்',
      'total_collected': 'மொத்தம் வசூலித்தது',
      'outstanding': 'நிலுவை',
      'interest_earned': 'வட்டி சம்பாதித்தது',
      'new_customers': 'புதிய வாடிக்கையாளர்கள்',
      'loans_completed': 'கடன்கள் முடிந்தது',
      'overdue_loans': 'தாமத கடன்கள்',
      'download_pdf': 'PDF அறிக்கை பதிவிறக்கு',
      'share_whatsapp': 'WhatsApp வழியாக பகிர்',
      
      // Calculator
      'calculate': 'கணக்கிடு',
      'result': 'முடிவு',
      'simple_interest': 'எளிய வட்டி',
      'compound_interest': 'கூட்டு வட்டி',
      'total_interest': 'மொத்த வட்டி',
      'monthly_payment': 'மாதாந்திர கட்டணம்',
      
      // Customer Groups
      'customers': 'வாடிக்கையாளர்கள்',
      'add_group': 'குழு சேர்',
      'group_name': 'குழு பெயர்',
      'no_groups': 'குழுக்கள் உருவாக்கப்படவில்லை',
      
      // Common
      'save': 'சேமி',
      'cancel': 'ரத்து செய்',
      'confirm': 'உறுதிப்படுத்து',
      'yes': 'ஆம்',
      'no': 'இல்லை',
      'ok': 'சரி',
      'error': 'பிழை',
      'success': 'வெற்றி',
      'warning': 'எச்சரிக்கை',
      'loading': 'ஏற்றுகிறது...',
      'required': 'தேவை',
      'optional': 'விருப்பம்',
      'minutes': 'நிமிடங்கள்',
    },
  };

  String get(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? 
           _localizedValues['en']?[key] ?? 
           key;
  }

  String getWithArgs(String key, Map<String, String> args) {
    String value = get(key);
    args.forEach((argKey, argValue) {
      value = value.replaceAll('{$argKey}', argValue);
    });
    return value;
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ta'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Extension to easily access translations
extension LocalizationExtension on BuildContext {
  AppLocalizations? get l10n => AppLocalizations.of(this);
  
  String tr(String key) => l10n?.get(key) ?? key;
  
  String trArgs(String key, Map<String, String> args) => 
      l10n?.getWithArgs(key, args) ?? key;
}
