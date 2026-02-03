import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  static const String _languageKey = 'selected_language';
  
  Locale _currentLocale = const Locale('en', '');
  
  Locale get currentLocale => _currentLocale;
  
  String get currentLanguageName {
    switch (_currentLocale.languageCode) {
      case 'ta':
        return 'தமிழ்';
      case 'en':
      default:
        return 'English';
    }
  }
  
  String get currentLanguageCode => _currentLocale.languageCode;
  
  LanguageProvider() {
    _loadSavedLanguage();
  }
  
  Future<void> _loadSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLanguage = prefs.getString(_languageKey) ?? 'en';
      _currentLocale = Locale(savedLanguage, '');
      notifyListeners();
    } catch (e) {
      // Default to English if error
      _currentLocale = const Locale('en', '');
    }
  }
  
  Future<void> setLanguage(String languageCode) async {
    if (_currentLocale.languageCode == languageCode) return;
    
    _currentLocale = Locale(languageCode, '');
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, languageCode);
    } catch (e) {
      debugPrint('Error saving language preference: $e');
    }
  }
  
  void setEnglish() => setLanguage('en');
  void setTamil() => setLanguage('ta');
}
