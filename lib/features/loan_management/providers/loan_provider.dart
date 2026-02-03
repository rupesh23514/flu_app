import 'package:flutter/foundation.dart';
import 'package:decimal/decimal.dart';
import 'dart:async';
import '../../../core/repositories/loan_repository.dart';
import '../../../core/repositories/payment_repository.dart';
import '../../../core/services/transaction_service.dart';
import '../../../shared/models/loan.dart';
import '../../../shared/models/payment.dart';

class LoanProvider extends ChangeNotifier {
  // Use repositories for data access (clean architecture)
  final LoanRepository _loanRepository = LoanRepository.instance;
  final PaymentRepository _paymentRepository = PaymentRepository.instance;
  // Keep TransactionService for transaction recording
  final TransactionService _transactionService = TransactionService.instance;

  // === PERFORMANCE OPTIMIZATIONS ===
  // Cache timestamps to avoid redundant loads
  DateTime? _lastLoansLoad;
  DateTime? _lastStatsLoad;
  static const _cacheDuration =
      Duration(seconds: 60); // LEGENDARY: Extended for stability

  // Prevent concurrent loads
  bool _isLoadingLoans = false;
  bool _isLoadingStats = false;

  List<Map<String, dynamic>> _loansWithCustomers = [];
  List<Loan> _loans = [];
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, Decimal> _dashboardStats = {};

  // Debounce timer to prevent rapid refresh cycles
  Timer? _refreshDebounceTimer;

  // Getters
  List<Map<String, dynamic>> get loansWithCustomers => _loansWithCustomers;
  List<Loan> get loans => _loans;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, Decimal> get dashboardStats => _dashboardStats;

  // Filter and search
  String _searchQuery = '';
  LoanStatus? _statusFilter;

  String get searchQuery => _searchQuery;
  LoanStatus? get statusFilter => _statusFilter;

  // === CACHED FILTERED LIST ===
  List<Map<String, dynamic>>? _cachedFilteredLoans;
  String? _lastSearchQuery;
  LoanStatus? _lastStatusFilter;

  List<Map<String, dynamic>> get filteredLoansWithCustomers {
    // Return cached result if filters haven't changed
    if (_cachedFilteredLoans != null &&
        _lastSearchQuery == _searchQuery &&
        _lastStatusFilter == _statusFilter) {
      return _cachedFilteredLoans!;
    }

    var filtered = _loansWithCustomers;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((loan) {
        final customerName =
            loan['customer_name']?.toString().toLowerCase() ?? '';
        final customerPhone =
            loan['customer_phone']?.toString().toLowerCase() ?? '';
        final bookNo = loan['book_no']?.toString().toLowerCase() ?? '';
        return customerName.contains(query) ||
            customerPhone.contains(query) ||
            bookNo.contains(query);
      }).toList();
    }

    // Apply status filter
    if (_statusFilter != null) {
      filtered = filtered.where((loan) {
        return loan['status'] == _statusFilter!.index;
      }).toList();
    }

    // Cache the result
    _cachedFilteredLoans = filtered;
    _lastSearchQuery = _searchQuery;
    _lastStatusFilter = _statusFilter;

    return filtered;
  }

  void updateSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void updateStatusFilter(LoanStatus? status) {
    _statusFilter = status;
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _statusFilter = null;
    notifyListeners();
  }

  Future<void> loadLoansWithCustomers({bool forceRefresh = false}) async {
    // Skip if already loading (prevents duplicate calls)
    if (_isLoadingLoans) return;

    // Skip if data is fresh (within cache duration)
    if (!forceRefresh &&
        _lastLoansLoad != null &&
        _loansWithCustomers.isNotEmpty) {
      final timeSinceLoad = DateTime.now().difference(_lastLoansLoad!);
      if (timeSinceLoad < _cacheDuration) {
        debugPrint('⚡ Using cached loans (${timeSinceLoad.inSeconds}s old)');
        return;
      }
    }

    _isLoadingLoans = true;
    _isLoading = true;
    _errorMessage = null;
    // Don't notify here - let final notify handle it

    final result = await _loanRepository.getWithCustomers();
    result.fold(
      onSuccess: (loansData) {
        _loansWithCustomers = loansData;
        _cachedFilteredLoans = null; // Clear filter cache
        _lastLoansLoad = DateTime.now();
      },
      onFailure: (message, _) {
        _errorMessage = 'Failed to load loans: $message';
      },
    );

    _isLoading = false;
    _isLoadingLoans = false;
    notifyListeners();
  }

  Future<void> loadLoans() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _loanRepository.getAllWithPayments();
    result.fold(
      onSuccess: (loansData) async {
        _loans = loansData;
        debugPrint('📋 LoanProvider: Loaded ${_loans.length} loans');
        // Check and update weekly overdue status for all active loans
        await _checkAndUpdateWeeklyOverdue();
      },
      onFailure: (message, _) {
        _errorMessage = 'Failed to load loans: $message';
        debugPrint('❌ LoanProvider: Error loading loans: $message');
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  /// Calculate the number of weekly payments expected by today based on loan start date
  int _getExpectedPaymentCount(Loan loan) {
    final now = DateTime.now();
    final loanStart = loan.loanDate;
    final daysSinceLoan = now.difference(loanStart).inDays;
    // First payment is due 7 days after loan date, so weeks elapsed = days / 7
    final weeksElapsed = daysSinceLoan ~/ 7;
    // Cap at loan tenure (total weeks)
    return weeksElapsed.clamp(0, loan.tenure);
  }

  /// Calculate the actual number of payments made based on totalPaid and EMI
  int _getActualPaymentCount(Loan loan) {
    // EMI = Principal / 10 (fixed 10-week tenure as per requirement)
    final emiAmount = loan.principal.toDouble() / 10;
    if (emiAmount <= 0) return 0;
    // Number of complete weekly payments made
    return (loan.totalPaid.toDouble() / emiAmount).floor();
  }

  /// Get the next weekly due date for a loan
  DateTime getNextWeeklyDueDate(Loan loan) {
    final actualPayments = _getActualPaymentCount(loan);
    // Next due date is (actualPayments + 1) weeks after loan start
    return loan.loanDate.add(Duration(days: (actualPayments + 1) * 7));
  }

  /// Get all weekly due dates for a loan
  List<DateTime> getWeeklyDueDates(Loan loan) {
    List<DateTime> dates = [];
    for (int week = 1; week <= loan.tenure; week++) {
      dates.add(loan.loanDate.add(Duration(days: week * 7)));
    }
    return dates;
  }

  /// Check if a loan is overdue based on weekly payment schedule
  bool isWeeklyOverdue(Loan loan) {
    if (loan.status == LoanStatus.completed ||
        loan.status == LoanStatus.closed ||
        loan.status == LoanStatus.cancelled) {
      return false;
    }

    final expectedPayments = _getExpectedPaymentCount(loan);
    final actualPayments = _getActualPaymentCount(loan);

    return actualPayments < expectedPayments;
  }

  /// Check and update overdue status for all active loans based on weekly schedule
  Future<void> _checkAndUpdateWeeklyOverdue() async {
    for (final loan in _loans) {
      // Skip non-active loans
      if (loan.status == LoanStatus.completed ||
          loan.status == LoanStatus.closed ||
          loan.status == LoanStatus.cancelled) {
        continue;
      }

      final expectedPayments = _getExpectedPaymentCount(loan);
      final actualPayments = _getActualPaymentCount(loan);

      // If behind on payments, mark as overdue
      if (actualPayments < expectedPayments &&
          loan.status != LoanStatus.overdue) {
        final updatedLoan = loan.copyWith(
          status: LoanStatus.overdue,
          updatedAt: DateTime.now(),
        );
        await _loanRepository.update(updatedLoan);
      }
      // If caught up on payments (paid missing weeks), return to active
      else if (actualPayments >= expectedPayments &&
          loan.status == LoanStatus.overdue) {
        final updatedLoan = loan.copyWith(
          status: LoanStatus.active,
          updatedAt: DateTime.now(),
        );
        await _loanRepository.update(updatedLoan);
      }
    }

    // Reload loans to reflect status changes
    final result = await _loanRepository.getAllWithPayments();
    if (result.isSuccess) {
      _loans = result.dataOrNull ?? [];
    }
  }

  Future<void> loadDashboardStats({bool forceRefresh = false}) async {
    // Skip if already loading
    if (_isLoadingStats) return;

    // Skip if data is fresh
    if (!forceRefresh && _lastStatsLoad != null && _dashboardStats.isNotEmpty) {
      final timeSinceLoad = DateTime.now().difference(_lastStatsLoad!);
      if (timeSinceLoad < _cacheDuration) {
        debugPrint('⚡ Using cached stats (${timeSinceLoad.inSeconds}s old)');
        return;
      }
    }

    _isLoadingStats = true;
    final result = await _loanRepository.getDashboardStats();
    result.fold(
      onSuccess: (stats) {
        _dashboardStats = stats;
        _lastStatsLoad = DateTime.now();
      },
      onFailure: (message, _) {
        _errorMessage = 'Failed to load dashboard statistics: $message';
      },
    );
    _isLoadingStats = false;
    notifyListeners();
  }

  Future<bool> addLoan(Loan loan) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Simple principal-based calculation, no interest
    final totalAmount = loan.principal;

    final loanWithCalculatedAmounts = loan.copyWith(
      totalAmount: totalAmount,
      remainingAmount: totalAmount,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    debugPrint('📝 Creating loan for customer ID: ${loan.customerId}');
    final result = await _loanRepository.insert(loanWithCalculatedAmounts);

    return await result.fold(
      onSuccess: (id) async {
        debugPrint('📝 Loan created with ID: $id');

        if (id > 0) {
          // Record transaction for loan disbursement (DEBIT - money given out)
          try {
            await _transactionService.recordDebit(
              customerId: loan.customerId,
              amount: loan.principal,
              loanId: id,
              description: loan.isMonthlyInterest
                  ? 'Monthly Interest Loan disbursed'
                  : 'Weekly Loan disbursed',
              transactionDate: loan.loanDate,
            );
            debugPrint('✅ Transaction recorded for loan $id');
          } catch (e) {
            debugPrint('⚠️ Warning: Failed to record transaction: $e');
          }

          debugPrint('🔄 Reloading loans after creation...');
          await loadLoans(); // Update the main loans list for home page
          await loadLoansWithCustomers();
          await loadDashboardStats();
          debugPrint('✅ Loan creation complete, total loans: ${_loans.length}');
          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          _errorMessage = 'Failed to add loan';
          debugPrint('❌ Failed to add loan - ID was 0 or negative');
          _isLoading = false;
          notifyListeners();
          return false;
        }
      },
      onFailure: (message, _) {
        _errorMessage = 'Error adding loan: $message';
        debugPrint('❌ Error adding loan: $message');
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> updateLoan(Loan loan) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _loanRepository.update(loan);

    return await result.fold(
      onSuccess: (updateCount) async {
        if (updateCount > 0) {
          await loadLoans(); // Update the main loans list for home page
          await loadLoansWithCustomers();
          await loadDashboardStats();
          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          _errorMessage = 'Failed to update loan';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      },
      onFailure: (message, _) {
        _errorMessage = 'Error updating loan: $message';
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> updateLoanStatus(int loanId, LoanStatus status) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Find the loan first - safely handle not found case
    Map<String, dynamic>? loanMap;
    for (final loan in _loansWithCustomers) {
      if (loan['id'] == loanId) {
        loanMap = loan;
        break;
      }
    }

    if (loanMap == null || loanMap.isEmpty) {
      _errorMessage = 'Loan not found';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Create loan object and update status
    final loan = Loan.fromMap(loanMap).copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );

    final result = await _loanRepository.update(loan);

    return await result.fold(
      onSuccess: (updateCount) async {
        if (updateCount > 0) {
          await loadLoans(); // Update the main loans list for home page
          await loadLoansWithCustomers();
          await loadDashboardStats();
          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          _errorMessage = 'Failed to update loan status';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      },
      onFailure: (message, _) {
        _errorMessage = 'Error updating loan status: $message';
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<List<Loan>> getLoansByCustomer(int customerId) async {
    final result = await _loanRepository.getByCustomer(customerId);
    return result.fold(
      onSuccess: (loans) => loans,
      onFailure: (message, _) {
        _errorMessage = 'Failed to load customer loans: $message';
        notifyListeners();
        return [];
      },
    );
  }

  // Calculate interest for overdue loans
  Future<void> updateOverdueInterest() async {
    try {
      final overdueLoans = _loansWithCustomers.where((loanMap) {
        final dueDate = DateTime.parse(loanMap['due_date']);
        final status = LoanStatus.values[loanMap['status']];
        return dueDate.isBefore(DateTime.now()) && status == LoanStatus.active;
      }).toList();

      for (final loanMap in overdueLoans) {
        final loan = Loan.fromMap(loanMap);

        // Calculate penalty if applicable
        if (loan.penaltyRate != null && loan.penaltyRate! > Decimal.zero) {
          final daysDiff = DateTime.now().difference(loan.dueDate).inDays;
          // Simple penalty calculation without interest
          final penaltyAmount = (loan.principal *
                  loan.penaltyRate! *
                  Decimal.fromInt(daysDiff > 0 ? daysDiff : 0) /
                  Decimal.fromInt(100))
              .toDecimal();
          final newTotalAmount = loan.principal + penaltyAmount;

          final updatedLoan = loan.copyWith(
            totalAmount: newTotalAmount,
            remainingAmount: newTotalAmount - loan.totalPaid,
            updatedAt: DateTime.now(),
          );

          await _loanRepository.update(updatedLoan);
        }
      }

      await loadLoans(); // Update the main loans list for home page
      await loadLoansWithCustomers();
      await loadDashboardStats();
    } catch (e) {
      _errorMessage = 'Failed to update overdue interest: $e';
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    // Cancel any pending refresh to prevent rapid refresh cycles
    _refreshDebounceTimer?.cancel();

    // Shorter debounce for faster responsiveness (100ms instead of 300ms)
    _refreshDebounceTimer = Timer(const Duration(milliseconds: 100), () async {
      try {
        // Force refresh to bypass cache - parallel loading for speed
        await Future.wait([
          loadLoansWithCustomers(forceRefresh: true),
          loadDashboardStats(forceRefresh: true),
        ]);
        debugPrint('⚡ Refresh completed');
      } catch (e) {
        debugPrint('⚠️ Error during refresh: $e');
        _errorMessage = 'Failed to refresh data';
        notifyListeners();
      }
    });
  }

  /// Invalidate all caches - call when data changes
  void invalidateCache() {
    _lastLoansLoad = null;
    _lastStatsLoad = null;
    _cachedFilteredLoans = null;
  }

  // Missing methods
  Future<Loan?> getLoanById(int id) async {
    final result = await _loanRepository.getById(id);
    return result.fold(
      onSuccess: (loan) => loan,
      onFailure: (message, _) {
        _errorMessage = 'Error getting loan: $message';
        notifyListeners();
        return null;
      },
    );
  }

  Future<bool> addPayment(int loanId, Decimal amount, DateTime paymentDate,
      {String? notes,
      int? customerId,
      PaymentMethod paymentMethod = PaymentMethod.cash}) async {
    try {
      // Debug logging
      debugPrint(
          'DEBUG: Starting payment addition for loan $loanId, amount: $amount');

      // Validate amount first
      if (amount <= Decimal.zero) {
        _errorMessage = 'Payment amount must be greater than zero';
        debugPrint('DEBUG: Payment validation failed - amount <= 0');
        notifyListeners();
        return false;
      }

      // Get the customer ID from the loan if not provided
      int resolvedCustomerId = customerId ?? 0;
      if (resolvedCustomerId == 0) {
        debugPrint('DEBUG: Looking up customer ID for loan $loanId');
        final loan = await getLoanById(loanId);
        if (loan != null) {
          resolvedCustomerId = loan.customerId;
          debugPrint('DEBUG: Found customer ID: $resolvedCustomerId');
        } else {
          _errorMessage = 'Loan not found';
          debugPrint('DEBUG: Loan $loanId not found');
          notifyListeners();
          return false;
        }
      }

      // Validate we have a valid customer ID
      if (resolvedCustomerId == 0) {
        _errorMessage = 'Could not determine customer for this loan';
        debugPrint('DEBUG: Failed to resolve customer ID for loan $loanId');
        notifyListeners();
        return false;
      }

      debugPrint('DEBUG: Creating payment object');
      final payment = Payment(
        loanId: loanId,
        customerId: resolvedCustomerId,
        amount: amount,
        paymentDate: paymentDate,
        paymentMethod: paymentMethod,
        notes: notes,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      debugPrint('DEBUG: Inserting payment into database');
      final insertResult = await _paymentRepository.insert(payment);

      return await insertResult.fold(
        onSuccess: (paymentId) async {
          debugPrint('DEBUG: Insert result: $paymentId');

          if (paymentId > 0) {
            debugPrint('DEBUG: Payment inserted successfully, updating loan');

            // Record transaction for payment received (CREDIT - money received)
            try {
              await _transactionService.recordCredit(
                customerId: resolvedCustomerId,
                amount: amount,
                loanId: loanId,
                description: notes ?? 'Payment received',
                transactionDate: paymentDate,
              );
              debugPrint('Transaction recorded for payment on loan $loanId');
            } catch (e) {
              debugPrint('Warning: Failed to record transaction: $e');
            }

            // Update loan's paid amount and remaining amount
            final loan = await getLoanById(loanId);
            if (loan != null) {
              final newTotalPaid = loan.totalPaid + amount;
              // Remaining based on principal (not totalAmount with interest)
              final newRemainingAmount = loan.principal - newTotalPaid;

              // Determine new status based on loan type
              LoanStatus newStatus = loan.status;
              if (newTotalPaid >= loan.principal) {
                newStatus = LoanStatus.completed;
              } else if (loan.isMonthlyInterest) {
                // For monthly interest loans, check 30-day overdue
                final daysSinceLoan =
                    DateTime.now().difference(loan.loanDate).inDays;
                final monthsElapsed = daysSinceLoan ~/ 30;
                // Monthly loans stay active unless principal is not repaid after tenure
                if (monthsElapsed > loan.tenure &&
                    newRemainingAmount > Decimal.zero) {
                  newStatus = LoanStatus.overdue;
                } else {
                  newStatus = LoanStatus.active;
                }
              } else {
                // Weekly loan: Calculate EMI and expected payments
                final emiAmount = loan.principal.toDouble() / 10;
                final actualPayments =
                    (newTotalPaid.toDouble() / emiAmount).floor();
                final daysSinceLoan =
                    DateTime.now().difference(loan.loanDate).inDays;
                final expectedPayments =
                    (daysSinceLoan ~/ 7).clamp(0, loan.tenure);

                // If caught up on payments, return to active; otherwise overdue
                if (actualPayments >= expectedPayments) {
                  newStatus = LoanStatus.active;
                } else {
                  newStatus = LoanStatus.overdue;
                }
              }

              final updatedLoan = loan.copyWith(
                totalPaid: newTotalPaid,
                remainingAmount: newRemainingAmount > Decimal.zero
                    ? newRemainingAmount
                    : Decimal.zero,
                status: newStatus,
                lastPaymentDate: paymentDate,
                updatedAt: DateTime.now(),
              );

              debugPrint('DEBUG: Updating loan with new totals');
              final updateResult = await _loanRepository.update(updatedLoan);

              return updateResult.fold(
                onSuccess: (count) async {
                  debugPrint('DEBUG: Loan update result: $count');
                  if (count > 0) {
                    debugPrint(
                        'DEBUG: Loan updated successfully, refreshing data');
                    await refresh();
                    return true;
                  } else {
                    _errorMessage = 'Failed to update loan after payment';
                    debugPrint('DEBUG: Failed to update loan');
                    notifyListeners();
                    return false;
                  }
                },
                onFailure: (message, _) {
                  _errorMessage =
                      'Failed to update loan after payment: $message';
                  debugPrint('DEBUG: Failed to update loan: $message');
                  notifyListeners();
                  return false;
                },
              );
            } else {
              _errorMessage = 'Could not find loan to update after payment';
              debugPrint('DEBUG: Could not find loan to update');
              notifyListeners();
              return false;
            }
          } else {
            _errorMessage = 'Failed to save payment to database';
            debugPrint('DEBUG: Failed to insert payment, result: $paymentId');
            notifyListeners();
            return false;
          }
        },
        onFailure: (message, _) {
          _errorMessage = 'Failed to save payment: $message';
          debugPrint('DEBUG: Payment insert error: $message');
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _errorMessage = 'Error adding payment: $e';
      debugPrint('DEBUG: Payment error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Add payment for monthly interest loan with separate interest and principal tracking
  Future<bool> addMonthlyInterestPayment(
    int loanId,
    Decimal interestAmount,
    Decimal principalAmount,
    DateTime paymentDate, {
    String? notes,
    PaymentMethod paymentMethod = PaymentMethod.cash,
  }) async {
    debugPrint('DEBUG: addMonthlyInterestPayment called for loan $loanId');
    debugPrint('DEBUG: Interest: $interestAmount, Principal: $principalAmount');

    try {
      final loan = await getLoanById(loanId);
      if (loan == null) {
        _errorMessage = 'Loan not found';
        notifyListeners();
        return false;
      }

      if (!loan.isMonthlyInterest) {
        _errorMessage = 'This method is only for monthly interest loans';
        notifyListeners();
        return false;
      }

      final resolvedCustomerId = loan.customerId;
      final totalPayment = interestAmount + principalAmount;

      // Create payment record
      final payment = Payment(
        customerId: resolvedCustomerId,
        loanId: loanId,
        amount: totalPayment,
        paymentDate: paymentDate,
        paymentMethod: paymentMethod,
        notes: notes,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final insertResult = await _paymentRepository.insert(payment);

      return await insertResult.fold(
        onSuccess: (paymentId) async {
          if (paymentId > 0) {
            debugPrint('DEBUG: Monthly interest payment inserted successfully');

            // Record transaction for total payment (CREDIT - money received)
            try {
              await _transactionService.recordCredit(
                customerId: resolvedCustomerId,
                amount: totalPayment,
                loanId: loanId,
                description: notes ?? 'Monthly payment (Interest + Principal)',
                transactionDate: paymentDate,
              );
              debugPrint(
                  'Transaction recorded for monthly payment on loan $loanId');
            } catch (e) {
              debugPrint('Warning: Failed to record transaction: $e');
            }

            // Update loan with new totals
            // totalPaid tracks only principal repayment for loan completion
            // totalInterestCollected tracks cumulative interest
            final newTotalPaid = loan.totalPaid + principalAmount;
            final newTotalInterestCollected =
                (loan.totalInterestCollected ?? Decimal.zero) + interestAmount;
            final newRemainingAmount = loan.principal - newTotalPaid;

            // Determine new status
            LoanStatus newStatus = loan.status;
            if (newTotalPaid >= loan.principal) {
              newStatus = LoanStatus.completed;
            } else {
              // Check 30-day overdue for monthly loans
              final daysSinceLoan =
                  DateTime.now().difference(loan.loanDate).inDays;
              final monthsElapsed = daysSinceLoan ~/ 30;
              if (monthsElapsed > loan.tenure &&
                  newRemainingAmount > Decimal.zero) {
                newStatus = LoanStatus.overdue;
              } else {
                newStatus = LoanStatus.active;
              }
            }

            final updatedLoan = loan.copyWith(
              totalPaid: newTotalPaid,
              remainingAmount: newRemainingAmount > Decimal.zero
                  ? newRemainingAmount
                  : Decimal.zero,
              totalInterestCollected: newTotalInterestCollected,
              status: newStatus,
              lastPaymentDate: paymentDate,
              updatedAt: DateTime.now(),
            );

            debugPrint('DEBUG: Updating monthly interest loan with new totals');
            final updateResult = await _loanRepository.update(updatedLoan);

            return updateResult.fold(
              onSuccess: (count) async {
                if (count > 0) {
                  debugPrint(
                      'DEBUG: Monthly interest loan updated successfully');
                  await refresh();
                  return true;
                } else {
                  _errorMessage = 'Failed to update loan after payment';
                  notifyListeners();
                  return false;
                }
              },
              onFailure: (message, _) {
                _errorMessage = 'Failed to update loan after payment: $message';
                notifyListeners();
                return false;
              },
            );
          } else {
            _errorMessage = 'Failed to save payment to database';
            notifyListeners();
            return false;
          }
        },
        onFailure: (message, _) {
          _errorMessage = 'Failed to save payment: $message';
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _errorMessage = 'Error adding monthly interest payment: $e';
      debugPrint('DEBUG: Monthly interest payment error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Get all payments for a specific loan
  Future<List<Payment>> getPaymentsForLoan(int loanId) async {
    final result = await _paymentRepository.getByLoan(loanId);
    return result.fold(
      onSuccess: (payments) => payments,
      onFailure: (message, _) {
        _errorMessage = 'Failed to load payments: $message';
        notifyListeners();
        return [];
      },
    );
  }

  /// Get a single payment by ID
  Future<Payment?> getPaymentById(int paymentId) async {
    final result = await _paymentRepository.getById(paymentId);
    return result.fold(
      onSuccess: (payment) => payment,
      onFailure: (message, _) {
        _errorMessage = 'Error getting payment: $message';
        notifyListeners();
        return null;
      },
    );
  }

  /// Update an existing payment
  Future<bool> updatePayment(Payment payment) async {
    try {
      debugPrint('DEBUG: Updating payment ID: ${payment.id}');

      // Get the old payment to calculate difference
      final oldPaymentResult = await _paymentRepository.getById(payment.id!);
      final oldPayment = oldPaymentResult.dataOrNull;
      if (oldPayment == null) {
        _errorMessage = 'Payment not found';
        notifyListeners();
        return false;
      }

      // Update the payment in database
      final updateResult = await _paymentRepository.update(payment);

      return await updateResult.fold(
        onSuccess: (count) async {
          if (count > 0) {
            // Calculate the difference in payment amount
            final amountDifference = payment.amount - oldPayment.amount;

            // Update the loan totals
            final loan = await getLoanById(payment.loanId);
            if (loan != null) {
              final newTotalPaid = loan.totalPaid + amountDifference;
              final newRemainingAmount = loan.principal - newTotalPaid;

              // Determine new status
              LoanStatus newStatus = loan.status;
              if (newTotalPaid >= loan.principal) {
                newStatus = LoanStatus.completed;
              } else if (newTotalPaid < Decimal.zero) {
                // Edge case: if somehow overpaid before
                newStatus = LoanStatus.active;
              } else {
                final emiAmount = loan.principal.toDouble() / 10;
                final actualPayments =
                    (newTotalPaid.toDouble() / emiAmount).floor();
                final daysSinceLoan =
                    DateTime.now().difference(loan.loanDate).inDays;
                final expectedPayments =
                    (daysSinceLoan ~/ 7).clamp(0, loan.tenure);

                if (actualPayments >= expectedPayments) {
                  newStatus = LoanStatus.active;
                } else {
                  newStatus = LoanStatus.overdue;
                }
              }

              final updatedLoan = loan.copyWith(
                totalPaid:
                    newTotalPaid > Decimal.zero ? newTotalPaid : Decimal.zero,
                remainingAmount: newRemainingAmount > Decimal.zero
                    ? newRemainingAmount
                    : Decimal.zero,
                status: newStatus,
                updatedAt: DateTime.now(),
              );

              await _loanRepository.update(updatedLoan);

              // Record transaction adjustment for the payment change
              if (amountDifference != Decimal.zero) {
                try {
                  if (amountDifference > Decimal.zero) {
                    // Payment was increased
                    await _transactionService.recordCredit(
                      customerId: payment.customerId,
                      amount: amountDifference,
                      loanId: payment.loanId,
                      description:
                          'Payment adjustment (+${amountDifference.toString()})',
                      transactionDate: DateTime.now(),
                    );
                  } else {
                    // Payment was decreased
                    await _transactionService.recordDebit(
                      customerId: payment.customerId,
                      amount: amountDifference.abs(),
                      loanId: payment.loanId,
                      description:
                          'Payment adjustment (-${amountDifference.abs().toString()})',
                      transactionDate: DateTime.now(),
                    );
                  }
                  debugPrint('Transaction recorded for payment adjustment');
                } catch (e) {
                  debugPrint(
                      'Warning: Failed to record payment adjustment transaction: $e');
                }
              }
            }

            // Reload all data to ensure transaction summary and all screens update
            await loadLoans();
            await loadLoansWithCustomers();
            await loadDashboardStats();
            notifyListeners();
            return true;
          } else {
            _errorMessage = 'Failed to update payment';
            notifyListeners();
            return false;
          }
        },
        onFailure: (message, _) {
          _errorMessage = 'Error updating payment: $message';
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _errorMessage = 'Error updating payment: $e';
      debugPrint('DEBUG: Update payment error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Delete a payment and recalculate loan totals
  Future<bool> deletePayment(int paymentId,
      {bool permanentDelete = false}) async {
    try {
      debugPrint('DEBUG: Deleting payment ID: $paymentId');

      // Get the payment first to know the amount and loan
      final paymentResult = await _paymentRepository.getById(paymentId);
      final payment = paymentResult.dataOrNull;
      if (payment == null) {
        _errorMessage = 'Payment not found';
        notifyListeners();
        return false;
      }

      // Delete the payment
      final deleteResult = permanentDelete
          ? await _paymentRepository.permanentlyDelete(paymentId)
          : await _paymentRepository.delete(paymentId);

      return await deleteResult.fold(
        onSuccess: (count) async {
          if (count > 0) {
            // Update the loan totals - subtract the deleted payment amount
            final loan = await getLoanById(payment.loanId);
            if (loan != null) {
              final newTotalPaid = loan.totalPaid - payment.amount;
              final newRemainingAmount = loan.principal - newTotalPaid;

              // Determine new status
              LoanStatus newStatus = loan.status;
              if (newTotalPaid >= loan.principal) {
                newStatus = LoanStatus.completed;
              } else {
                final emiAmount = loan.principal.toDouble() / 10;
                final actualPayments =
                    (newTotalPaid.toDouble() / emiAmount).floor();
                final daysSinceLoan =
                    DateTime.now().difference(loan.loanDate).inDays;
                final expectedPayments =
                    (daysSinceLoan ~/ 7).clamp(0, loan.tenure);

                if (actualPayments >= expectedPayments) {
                  newStatus = LoanStatus.active;
                } else {
                  newStatus = LoanStatus.overdue;
                }
              }

              // Find the new last payment date
              final remainingPaymentsResult =
                  await _paymentRepository.getByLoan(payment.loanId);
              final remainingPayments =
                  remainingPaymentsResult.dataOrNull ?? [];
              DateTime? newLastPaymentDate;
              if (remainingPayments.isNotEmpty) {
                newLastPaymentDate = remainingPayments
                    .map((p) => p.paymentDate)
                    .reduce((a, b) => a.isAfter(b) ? a : b);
              }

              final updatedLoan = loan.copyWith(
                totalPaid:
                    newTotalPaid > Decimal.zero ? newTotalPaid : Decimal.zero,
                remainingAmount: newRemainingAmount > Decimal.zero
                    ? newRemainingAmount
                    : loan.principal,
                status: newStatus,
                lastPaymentDate: newLastPaymentDate,
                updatedAt: DateTime.now(),
              );

              await _loanRepository.update(updatedLoan);
            }

            await refresh();
            debugPrint('DEBUG: Payment deleted successfully');
            return true;
          } else {
            _errorMessage = 'Failed to delete payment';
            notifyListeners();
            return false;
          }
        },
        onFailure: (message, _) {
          _errorMessage = 'Error deleting payment: $message';
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _errorMessage = 'Error deleting payment: $e';
      debugPrint('DEBUG: Delete payment error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Delete a loan and all its payments
  /// If permanentDelete is true, performs hard delete (data cannot be recovered)
  /// If permanentDelete is false, performs soft delete (sets is_active = 0)
  /// This only affects the specific loan and its payments
  /// Other loans for the same customer remain untouched
  Future<bool> deleteLoan(int loanId, {bool permanentDelete = false}) async {
    try {
      debugPrint(
          'DEBUG: Deleting loan ID: $loanId (permanent: $permanentDelete)');

      // First, verify the loan exists
      final loan = await getLoanById(loanId);
      if (loan == null) {
        _errorMessage = 'Loan not found';
        notifyListeners();
        return false;
      }

      if (permanentDelete) {
        // Use hard delete - permanently removes from database
        final deleteResult = await _loanRepository.deleteEntirely(loanId);
        return await deleteResult.fold(
          onSuccess: (_) async {
            debugPrint(
                'DEBUG: Permanently deleted loan $loanId and all its payments');
            await refresh();
            debugPrint(
                'DEBUG: Loan $loanId permanently deleted. Other loans for customer ${loan.customerId} remain intact.');
            return true;
          },
          onFailure: (message, _) {
            _errorMessage = 'Failed to delete loan: $message';
            notifyListeners();
            return false;
          },
        );
      } else {
        // Use soft delete - sets is_active = 0
        // Step 1: Soft delete all payments for this specific loan only
        final deletePaymentsResult =
            await _paymentRepository.deleteByLoan(loanId);
        final paymentsDeleted = deletePaymentsResult.fold(
          onSuccess: (count) {
            debugPrint('DEBUG: Soft-deleted $count payments for loan $loanId');
            return count;
          },
          onFailure: (message, _) {
            _errorMessage = 'Failed to delete payments: $message';
            return -1;
          },
        );

        if (paymentsDeleted == -1) {
          notifyListeners();
          return false;
        }

        // Step 2: Soft delete the loan itself
        final deleteLoanResult = await _loanRepository.delete(loanId);
        return await deleteLoanResult.fold(
          onSuccess: (count) async {
            if (count > 0) {
              debugPrint('DEBUG: Successfully soft-deleted loan $loanId');
              await refresh();
              debugPrint(
                  'DEBUG: Loan $loanId and its payments soft-deleted. Other loans for customer ${loan.customerId} remain intact.');
              return true;
            } else {
              _errorMessage = 'Failed to delete loan';
              notifyListeners();
              return false;
            }
          },
          onFailure: (message, _) {
            _errorMessage = 'Failed to delete loan: $message';
            notifyListeners();
            return false;
          },
        );
      }
    } catch (e) {
      _errorMessage = 'Error deleting loan: $e';
      debugPrint('DEBUG: Delete loan error: $e');
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    // Cancel debounce timer to prevent memory leaks
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = null;
    super.dispose();
  }
}
