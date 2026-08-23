import 'package:flutter/foundation.dart';

/// Provider for managing multi-selection state in customer groups
/// Supports WhatsApp-style selection with bulk operations
class GroupSelectionProvider extends ChangeNotifier {
  /// Currently selected customer IDs
  final Set<int> _selectedIds = {};

  /// Whether selection mode is active
  bool _isSelectionMode = false;

  /// Currently active group ID (selection clears when group changes)
  int? _activeGroupId;

  // Getters
  Set<int> get selectedIds => Set.unmodifiable(_selectedIds);
  bool get isSelectionMode => _isSelectionMode;
  int get selectedCount => _selectedIds.length;
  bool get hasSelection => _selectedIds.isNotEmpty;
  int? get activeGroupId => _activeGroupId;

  /// Check if a specific customer is selected
  bool isSelected(int customerId) => _selectedIds.contains(customerId);

  /// Set the active group (clears selection if group changes)
  void setActiveGroup(int? groupId) {
    if (_activeGroupId != groupId) {
      _activeGroupId = groupId;
      clearAll();
    }
  }

  /// Enter selection mode (typically on long-press)
  void enterSelectionMode(int initialCustomerId) {
    _isSelectionMode = true;
    _selectedIds.add(initialCustomerId);
    notifyListeners();
  }

  /// Exit selection mode and clear all selections
  void exitSelectionMode() {
    _isSelectionMode = false;
    _selectedIds.clear();
    notifyListeners();
  }

  /// Toggle selection for a customer
  void toggleCustomer(int customerId) {
    if (_selectedIds.contains(customerId)) {
      _selectedIds.remove(customerId);
      // Auto-exit selection mode if no selections remain
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedIds.add(customerId);
      // Auto-enable selection mode when adding
      if (!_isSelectionMode) {
        _isSelectionMode = true;
      }
    }
    notifyListeners();
  }

  /// Select all customers from provided list
  void selectAll(List<int> customerIds) {
    _selectedIds.addAll(customerIds);
    if (_selectedIds.isNotEmpty && !_isSelectionMode) {
      _isSelectionMode = true;
    }
    notifyListeners();
  }

  /// Clear all selections but stay in selection mode
  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  /// Clear all selections and exit selection mode
  void clearAll() {
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  /// Get selected customer IDs as list
  List<int> getSelectedIdsList() => _selectedIds.toList();
}
