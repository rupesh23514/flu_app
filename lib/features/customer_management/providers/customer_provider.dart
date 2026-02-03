import 'package:flutter/foundation.dart';
import '../../../core/repositories/customer_repository.dart';
import '../../../shared/models/customer.dart';

class CustomerProvider extends ChangeNotifier {
  // Use repository for all customer operations (clean architecture)
  final CustomerRepository _customerRepository = CustomerRepository.instance;


  List<Customer> _customers = [];
  Customer? _selectedCustomer;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<Customer> get customers => _customers;
  Customer? get selectedCustomer => _selectedCustomer;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Search and filter
  String _searchQuery = '';
  List<Customer> get filteredCustomers {
    if (_searchQuery.isEmpty) return _customers;
    
    return _customers.where((customer) {
      final name = customer.name.toLowerCase();
      final phone = customer.phoneNumber.toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || phone.contains(query);
    }).toList();
  }

  String get searchQuery => _searchQuery;

  void updateSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  Future<void> loadCustomers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _customerRepository.getAll();
    result.fold(
      onSuccess: (customers) {
        _customers = customers;
      },
      onFailure: (message, _) {
        _errorMessage = 'Failed to load customers: $message';
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  /// Add a new customer and return the created customer ID
  /// Returns the customer ID on success, or null on failure
  Future<int?> addCustomerAndGetId(Customer customer) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final customerWithDates = customer.copyWith(
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final result = await _customerRepository.insert(customerWithDates);
    
    return result.fold(
      onSuccess: (id) async {
        if (id > 0) {
          await loadCustomers();
          _isLoading = false;
          notifyListeners();
          return id;
        } else {
          _errorMessage = 'Failed to add customer';
          _isLoading = false;
          notifyListeners();
          return null;
        }
      },
      onFailure: (message, _) {
        _errorMessage = 'Error adding customer: $message';
        _isLoading = false;
        notifyListeners();
        return null;
      },
    );
  }

  Future<bool> addCustomer(Customer customer) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Allow same phone number for different customers (different loans for same person)
    // Each loan can have its own customer entry

    final customerWithDates = customer.copyWith(
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final result = await _customerRepository.insert(customerWithDates);
    
    return result.fold(
      onSuccess: (id) async {
        if (id > 0) {
          await loadCustomers();
          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          _errorMessage = 'Failed to add customer';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      },
      onFailure: (message, _) {
        _errorMessage = 'Error adding customer: $message';
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> updateCustomer(Customer customer) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Allow editing phone number without restriction - same number can exist for different loans

    final result = await _customerRepository.update(customer);
    
    return result.fold(
      onSuccess: (updateCount) async {
        if (updateCount > 0) {
          await loadCustomers();
          
          // Update selected customer if it was the one being edited
          if (_selectedCustomer?.id == customer.id) {
            _selectedCustomer = customer;
          }
          
          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          _errorMessage = 'Failed to update customer';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      },
      onFailure: (message, _) {
        _errorMessage = 'Error updating customer: $message';
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> deleteCustomer(int customerId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Use repository for cascade delete operation
    final result = await _customerRepository.deleteEntirely(customerId);
    
    return result.fold(
      onSuccess: (_) async {
        await loadCustomers();
        // Clear selected customer if it was deleted
        if (_selectedCustomer?.id == customerId) {
          _selectedCustomer = null;
        }
        _isLoading = false;
        notifyListeners();
        return true;
      },
      onFailure: (message, _) {
        _errorMessage = 'Error deleting customer: $message';
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<Customer?> getCustomerById(int id) async {
    final result = await _customerRepository.getById(id);
    return result.fold(
      onSuccess: (customer) => customer,
      onFailure: (message, _) {
        _errorMessage = 'Failed to load customer: $message';
        notifyListeners();
        return null;
      },
    );
  }

  // Synchronous method to get customer from loaded data
  Customer? getLoadedCustomerById(int id) {
    final matches = _customers.where((customer) => customer.id == id);
    return matches.isNotEmpty ? matches.first : null;
  }

  Future<Customer?> getCustomerByPhone(String phoneNumber) async {
    final result = await _customerRepository.getByPhone(phoneNumber);
    return result.fold(
      onSuccess: (customer) => customer,
      onFailure: (message, _) {
        _errorMessage = 'Failed to find customer: $message';
        notifyListeners();
        return null;
      },
    );
  }

  void setSelectedCustomer(Customer? customer) {
    _selectedCustomer = customer;
    notifyListeners();
  }

  void clearSelectedCustomer() {
    _selectedCustomer = null;
    notifyListeners();
  }

  bool isPhoneNumberUnique(String phoneNumber, {int? excludeCustomerId}) {
    return !_customers.any((customer) => 
      customer.phoneNumber == phoneNumber && 
      customer.id != excludeCustomerId
    );
  }

  Customer? findCustomerByPhone(String phoneNumber) {
    final matches = _customers.where(
      (customer) => customer.phoneNumber == phoneNumber
    );
    return matches.isNotEmpty ? matches.first : null;
  }

  List<Customer> searchCustomers(String query) {
    if (query.isEmpty) return _customers;
    
    final lowercaseQuery = query.toLowerCase();
    return _customers.where((customer) {
      return customer.name.toLowerCase().contains(lowercaseQuery) ||
             customer.phoneNumber.contains(query) ||
             (customer.address?.toLowerCase().contains(lowercaseQuery) ?? false);
    }).toList();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    await loadCustomers();
  }
}