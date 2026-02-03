import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Feature flags for safe rollback and gradual feature release
class FeatureFlagsService {
  static final FeatureFlagsService _instance = FeatureFlagsService._internal();
  static FeatureFlagsService get instance => _instance;
  FeatureFlagsService._internal();

  SharedPreferences? _prefs;
  final Map<String, bool> _cachedFlags = {};

  // Feature flag keys
  static const String kTransactionTracking = 'feature_transaction_tracking';
  static const String kAdvancedSearch = 'feature_advanced_search';
  static const String kRemindersEnabled = 'feature_reminders';
  static const String kEnhancedReports = 'feature_enhanced_reports';
  static const String kPaginationEnabled = 'feature_pagination';
  static const String kPerformanceMonitoring = 'feature_performance_monitoring';

  // Default flag values
  static final Map<String, bool> _defaultFlags = {
    kTransactionTracking: true,
    kAdvancedSearch: true,
    kRemindersEnabled: true,
    kEnhancedReports: true,
    kPaginationEnabled: true,
    kPerformanceMonitoring: false, // Disabled by default in production
  };

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Load all flags
    for (final key in _defaultFlags.keys) {
      _cachedFlags[key] = _prefs!.getBool(key) ?? _defaultFlags[key]!;
    }
    
    debugPrint('Feature flags initialized: $_cachedFlags');
  }

  /// Check if a feature is enabled
  bool isEnabled(String featureKey) {
    return _cachedFlags[featureKey] ?? _defaultFlags[featureKey] ?? false;
  }

  /// Enable a feature
  Future<void> enableFeature(String featureKey) async {
    _cachedFlags[featureKey] = true;
    await _prefs?.setBool(featureKey, true);
    debugPrint('Feature enabled: $featureKey');
  }

  /// Disable a feature (for rollback)
  Future<void> disableFeature(String featureKey) async {
    _cachedFlags[featureKey] = false;
    await _prefs?.setBool(featureKey, false);
    debugPrint('Feature disabled: $featureKey');
  }

  /// Reset all flags to defaults
  Future<void> resetToDefaults() async {
    for (final entry in _defaultFlags.entries) {
      _cachedFlags[entry.key] = entry.value;
      await _prefs?.setBool(entry.key, entry.value);
    }
    debugPrint('Feature flags reset to defaults');
  }

  /// Get all current flag states
  Map<String, bool> getAllFlags() {
    return Map.from(_cachedFlags);
  }

  // Convenience getters for common checks
  bool get isTransactionTrackingEnabled => isEnabled(kTransactionTracking);
  bool get isAdvancedSearchEnabled => isEnabled(kAdvancedSearch);
  bool get isRemindersEnabled => isEnabled(kRemindersEnabled);
  bool get isEnhancedReportsEnabled => isEnabled(kEnhancedReports);
  bool get isPaginationEnabled => isEnabled(kPaginationEnabled);
  bool get isPerformanceMonitoringEnabled => isEnabled(kPerformanceMonitoring);
}
