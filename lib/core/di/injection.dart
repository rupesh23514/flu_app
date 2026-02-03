// Dependency Injection Setup
// Using GetIt for service locator pattern

import 'package:get_it/get_it.dart';
import '../repositories/customer_repository.dart';
import '../repositories/customer_group_repository.dart';
import '../repositories/loan_repository.dart';
import '../repositories/payment_repository.dart';
import '../services/database_service.dart';
import '../services/transaction_service.dart';

/// Global service locator instance
final GetIt sl = GetIt.instance;

/// Initialize all dependencies
/// Call this in main() before runApp()
Future<void> configureDependencies() async {
  // ==================== Core Services ====================
  
  // Database Service (singleton - already initialized in main)
  sl.registerLazySingleton<DatabaseService>(() => DatabaseService.instance);
  
  // Transaction Service
  sl.registerLazySingleton<TransactionService>(() => TransactionService.instance);
  
  // ==================== Repositories ====================
  
  // Customer Repository
  sl.registerLazySingleton<CustomerRepository>(() => CustomerRepository.instance);
  
  // Customer Group Repository
  sl.registerLazySingleton<CustomerGroupRepository>(() => CustomerGroupRepository.instance);
  
  // Loan Repository
  sl.registerLazySingleton<LoanRepository>(() => LoanRepository.instance);
  
  // Payment Repository
  sl.registerLazySingleton<PaymentRepository>(() => PaymentRepository.instance);
}

/// Reset all dependencies (useful for testing)
Future<void> resetDependencies() async {
  await sl.reset();
}

/// Check if dependencies are configured
bool get areDependenciesConfigured => sl.isRegistered<CustomerRepository>();
