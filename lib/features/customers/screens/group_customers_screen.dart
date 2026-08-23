import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/database_service.dart';
import '../../../core/repositories/customer_group_repository.dart';
import '../../../core/services/permission_service.dart';
import '../../../shared/models/customer_group.dart';
import '../../../shared/models/customer.dart';
import '../../customer_management/screens/customer_detail_screen.dart';
import '../../customer_management/providers/customer_provider.dart';
import '../../loan_management/providers/loan_provider.dart';
import '../providers/group_selection_provider.dart';
import '../widgets/customer_selection_card.dart';
import '../widgets/group_action_bottom_bar.dart';
import '../widgets/group_action_sheets.dart';

/// Screen to view and manage customers in a specific group - Like Home Page
/// Now with WhatsApp-style multi-selection support
class GroupCustomersScreen extends StatefulWidget {
  final CustomerGroup group;

  const GroupCustomersScreen({super.key, required this.group});

  @override
  State<GroupCustomersScreen> createState() => _GroupCustomersScreenState();
}

class _GroupCustomersScreenState extends State<GroupCustomersScreen> {
  List<Customer> _customers = [];
  List<Customer> _filteredCustomersCache = []; // Cached filtered results
  List<CustomerGroup> _allGroups = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Debounce timer for search input to prevent UI jank on large lists
  Timer? _searchDebounceTimer;
  static const _searchDebounceDuration = Duration(milliseconds: 300);

  // Scroll controller — persists position across rebuilds triggered by data reload
  final ScrollController _scrollController = ScrollController();

  // Multi-selection state
  final GroupSelectionProvider _selectionProvider = GroupSelectionProvider();

  @override
  void initState() {
    super.initState();
    _selectionProvider.setActiveGroup(widget.group.id);
    // Defer loading to after the first frame to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomers();
      _loadAllGroups();
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _selectionProvider.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers({bool showLoading = true}) async {
    if (!mounted) return;

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _isRefreshing = false;
      });
    } else {
      setState(() => _isRefreshing = true);
    }

    try {
      // Use CustomerGroupRepository which queries junction table for multi-group support
      final result =
          await CustomerGroupRepository.instance.getCustomers(widget.group.id);
      final customers = result.dataOrNull ?? [];

      if (mounted) {
        setState(() {
          _customers = customers;
          _updateFilteredCustomers(); // Refresh filtered cache
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading customers: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _loadAllGroups() async {
    try {
      final groups = await DatabaseService.instance.getAllCustomerGroups();
      if (mounted) {
        setState(() {
          _allGroups = groups;
        });
      }
    } catch (e) {
      debugPrint('Error loading groups: $e');
    }
  }

  /// Get filtered customers - uses cached results to avoid recalculating on every build
  List<Customer> get _filteredCustomers => _filteredCustomersCache;

  /// Update filtered customers cache - called when search query or customer list changes
  void _updateFilteredCustomers() {
    if (_searchQuery.isEmpty) {
      _filteredCustomersCache = _customers;
    } else {
      _filteredCustomersCache = _customers
          .where((c) =>
              c.name.toLowerCase().contains(_searchQuery) ||
              c.phoneNumber.contains(_searchQuery))
          .toList();
    }
  }

  /// Debounced search update to prevent frame drops on large customer lists
  void _onSearchChanged(String value) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounceDuration, () {
      if (!mounted) return;
      setState(() {
        _searchQuery = value.toLowerCase();
        _updateFilteredCustomers();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return ListenableBuilder(
      listenable: _selectionProvider,
      builder: (context, child) {
        final isSelectionMode = _selectionProvider.isSelectionMode;
        final selectedCount = _selectionProvider.selectedCount;

        return Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: _buildAppBar(isSelectionMode, selectedCount),
          body: SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      // Stats Header - hide when keyboard is visible or in selection mode
                      if (!keyboardVisible && !isSelectionMode)
                        _buildStatsHeader(),

                      // Selection info bar
                      if (isSelectionMode)
                        _buildSelectionInfoBar(selectedCount),

                      if (_isRefreshing)
                        const LinearProgressIndicator(minHeight: 2),

                      // Customer List
                      Expanded(
                        child: _filteredCustomers.isEmpty
                            ? _buildEmptyState()
                            : RefreshIndicator(
                                onRefresh: () =>
                                    _loadCustomers(showLoading: false),
                                child: ListView.builder(
                                  key: PageStorageKey('group_${widget.group.id}'),
                                  controller: _scrollController,
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _filteredCustomers.length,
                                  itemBuilder: (context, index) {
                                    final customer = _filteredCustomers[index];
                                    // Null-safe: skip customers without IDs
                                    final customerId = customer.id;
                                    return CustomerSelectionCard(
                                      key: customerId != null ? ValueKey(customerId) : null,
                                      customer: customer,
                                      groupColor: widget.group.color,
                                      isSelected: customerId != null &&
                                          _selectionProvider
                                              .isSelected(customerId),
                                      isSelectionMode: isSelectionMode,
                                      onTap: () => _handleCustomerTap(customer),
                                      onLongPress: () =>
                                          _handleCustomerLongPress(customer),
                                      onCall: () => _callCustomer(customer),
                                      onRemove: () =>
                                          _removeFromGroup(customer),
                                      onDelete: () =>
                                          _deleteCustomerEntirely(customer),
                                    );
                                  },
                                ),
                              ),
                      ),

                      // Action bar when in selection mode
                      if (isSelectionMode)
                        GroupActionBottomBar(
                          selectedCount: selectedCount,
                          groupColor: widget.group.color,
                          onRemoveFromGroup: _bulkRemoveFromGroup,
                          onMoveToGroup: _bulkMoveToGroup,
                          onAddToAnotherGroup: _bulkAddToAnotherGroup,
                          onDeletePermanently: _bulkDeletePermanently,
                        ),
                    ],
                  ),
          ),
          floatingActionButton: isSelectionMode
              ? null
              : FloatingActionButton(
                  onPressed: _showAddCustomerToGroupDialog,
                  backgroundColor: widget.group.color,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.person_add),
                ),
        );
      },
    );
  }

  Widget _buildSelectionInfoBar(int selectedCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: widget.group.color.withValues(alpha: 0.1),
      child: Row(
        children: [
          Text(
            '$selectedCount selected',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: widget.group.color,
              fontSize: 15,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              // Null-safe: filter out any customers without IDs (shouldn't happen but defensive)
              final validIds = _filteredCustomers
                  .where((c) => c.id != null)
                  .map((c) => c.id!)
                  .toList();
              _selectionProvider.selectAll(validIds);
            },
            child: const Text('Select All'),
          ),
          TextButton(
            onPressed: () => _selectionProvider.clearSelection(),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _handleCustomerTap(Customer customer) {
    // Null-safe check for customer ID
    if (customer.id == null) return;

    if (_selectionProvider.isSelectionMode) {
      HapticFeedback.selectionClick();
      _selectionProvider.toggleCustomer(customer.id!);
    } else {
      _openCustomerDetail(customer);
    }
  }

  void _handleCustomerLongPress(Customer customer) {
    // Null-safe check for customer ID
    if (customer.id == null) return;

    if (!_selectionProvider.isSelectionMode) {
      HapticFeedback.mediumImpact();
      _selectionProvider.enterSelectionMode(customer.id!);
    }
  }

  PreferredSizeWidget _buildAppBar(bool isSelectionMode, int selectedCount) {
    // Selection mode app bar
    if (isSelectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _selectionProvider.exitSelectionMode(),
        ),
        title: Text('$selectedCount selected'),
        backgroundColor: widget.group.color.withValues(alpha: 0.1),
      );
    }

    // Search mode app bar
    if (_isSearching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _searchDebounceTimer?.cancel();
            setState(() {
              _isSearching = false;
              _searchQuery = '';
              _searchController.clear();
              _updateFilteredCustomers();
            });
          },
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search customers...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: AppColors.textSecondary),
          ),
          style: const TextStyle(fontSize: 18),
          onChanged: _onSearchChanged, // Use debounced handler
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchDebounceTimer?.cancel();
                setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                  _updateFilteredCustomers();
                });
              },
            ),
        ],
      );
    }

    // Default app bar
    return AppBar(
      title: Text(widget.group.name),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            setState(() {
              _isSearching = true;
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.person_add),
          onPressed: _showAddCustomerToGroupDialog,
          tooltip: 'Add Customer',
        ),
      ],
    );
  }

  Widget _buildStatsHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.group.color,
            widget.group.color.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: widget.group.color.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.group,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.group.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_customers.length} Customer${_customers.length != 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                if (widget.group.description != null &&
                    widget.group.description!.isNotEmpty)
                  Text(
                    widget.group.description!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isSearchEmpty = _searchQuery.isNotEmpty;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearchEmpty ? Icons.search_off : Icons.people_outline,
            size: 80,
            color: widget.group.color.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isSearchEmpty ? 'No customers found' : 'No customers in this group',
            style: const TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSearchEmpty
                ? 'Try a different search term'
                : 'Tap + to add customers',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.8),
            ),
          ),
          if (!isSearchEmpty) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddCustomerToGroupDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Customer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.group.color,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openCustomerDetail(Customer customer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerDetailScreen(
          customerId: customer.id!,
          initialTabIndex: 0,
        ),
      ),
    ).then((dataChanged) {
      // Reload only when customer detail reported a data change (payment, edit, etc.)
      // Skipping reload on no-change preserves scroll position.
      if (dataChanged == true) {
        _loadCustomers(showLoading: false);
      }
    });
  }

  Future<void> _callCustomer(Customer customer) async {
    if (customer.phoneNumber.trim().isEmpty &&
        (customer.alternatePhone == null ||
            customer.alternatePhone!.trim().isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No phone number'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    String phoneToCall = customer.phoneNumber;

    if (customer.hasMultiplePhones) {
      final selectedPhone = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Phone Number'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: widget.group.color.withValues(alpha: 0.1),
                    child: const Text('1'),
                  ),
                  title: Text(customer.phoneNumber,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Primary'),
                  onTap: () => Navigator.of(context).pop(customer.phoneNumber),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: widget.group.color.withValues(alpha: 0.1),
                    child: const Text('2'),
                  ),
                  title: Text(customer.alternatePhone!,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Alternate'),
                  onTap: () =>
                      Navigator.of(context).pop(customer.alternatePhone),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selectedPhone == null) return;
      phoneToCall = selectedPhone;
    }

    final permissionService = PermissionService.instance;
    final result = await permissionService.launchPhoneCall(phoneToCall);

    if (!mounted) return;

    switch (result) {
      case PhoneCallResult.success:
        break;
      case PhoneCallResult.noNumber:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No phone number'),
            backgroundColor: AppColors.error,
          ),
        );
        break;
      case PhoneCallResult.permissionDenied:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Phone permission required to make calls'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => permissionService.openSettings(),
            ),
          ),
        );
        break;
      case PhoneCallResult.launchFailed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot make phone call'),
            backgroundColor: AppColors.error,
          ),
        );
        break;
    }
  }

  /// Show dialog to add customers to this group
  /// Uses database-side filtering for large datasets to avoid memory pressure
  void _showAddCustomerToGroupDialog() async {
    if (!mounted) return;

    final searchController = TextEditingController();
    List<Customer> filteredList = [];
    bool isLoading = true;
    bool hasSearched = false;
    Timer? debounceTimer;
    int searchRequestId = 0; // To prevent stale results from overwriting
    bool dialogOpen = true; // Guard to prevent setDialogState after dialog closes

    // Initial load - get first batch of customers not in group
    filteredList = await DatabaseService.instance.searchCustomersNotInGroup(
      '', // empty query = get first batch
      widget.group.id!,
      limit: 50,
    );
    isLoading = false;

    if (!mounted) return;

    if (filteredList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All customers are already in this group'),
          backgroundColor: AppColors.info,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Customer to Group'),
          content: SizedBox(
            width: double.maxFinite,
            height: 450,
            child: Column(
              children: [
                // Search Bar - searches database, not local list
                TextField(
                  controller: searchController,
                  maxLength: 50,
                  decoration: InputDecoration(
                    hintText: 'Search by name or phone...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    counterText: '',
                    suffixIcon: isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    // Cancel any pending search
                    debounceTimer?.cancel();

                    setDialogState(() {
                      isLoading = true;
                      hasSearched = value.isNotEmpty;
                    });

                    // Debounce search by 300ms to avoid excessive DB queries
                    final currentRequestId = ++searchRequestId;
                    debounceTimer = Timer(const Duration(milliseconds: 300), () async {
                      // Database-side filtering
                      final results = await DatabaseService.instance
                          .searchCustomersNotInGroup(
                        value,
                        widget.group.id!,
                        limit: 50,
                      );

                      // Only update if this is still the latest request AND dialog is still open
                      if (currentRequestId == searchRequestId && dialogOpen) {
                        setDialogState(() {
                          filteredList = results;
                          isLoading = false;
                        });
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),

                // Customer Count
                Text(
                  hasSearched
                      ? '${filteredList.length} result${filteredList.length != 1 ? 's' : ''}'
                      : '${filteredList.length} customer${filteredList.length != 1 ? 's' : ''} (showing first 50)',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),

                // Customer List
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : filteredList.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off,
                                      size: 48, color: AppColors.textSecondary),
                                  SizedBox(height: 8),
                                  Text(
                                    'No customers found',
                                    style: TextStyle(
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredList.length,
                              itemBuilder: (context, index) {
                                final customer = filteredList[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: widget.group.color
                                        .withValues(alpha: 0.1),
                                    child: Text(
                                      customer.name.isNotEmpty
                                          ? customer.name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: widget.group.color,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(customer.name),
                                  subtitle: Text(customer.phoneNumber),
                                  trailing: const Icon(Icons.add_circle_outline,
                                      color: AppColors.primary),
                                  onTap: () => _addToGroup(customer),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                dialogOpen = false;
                debounceTimer?.cancel();
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ).then((_) {
      // Ensure timer is canceled and guard is set when dialog closes by any means
      dialogOpen = false;
      debounceTimer?.cancel();
    });
  }

  Future<void> _addToGroup(Customer customer) async {
    Navigator.pop(context);

    try {
      // Use new multi-group junction table method
      await CustomerGroupRepository.instance
          .addCustomerToGroup(customer.id!, widget.group.id!);
      await _loadCustomers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${customer.name} added to group'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding customer: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _removeFromGroup(Customer customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Group'),
        content: SingleChildScrollView(
          child: Text(
            'Remove "${customer.name.length > 25 ? '${customer.name.substring(0, 25)}...' : customer.name}" from "${widget.group.name.length > 20 ? '${widget.group.name.substring(0, 20)}...' : widget.group.name}"?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      // Use new multi-group method - only removes from this specific group
      await CustomerGroupRepository.instance
          .removeCustomerFromGroup(customer.id!, widget.group.id!);
      await _loadCustomers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${customer.name} removed from group'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing customer: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteCustomerEntirely(Customer customer) async {
    // Get provider references BEFORE any async operations to avoid disposed context error
    final customerProvider =
        Provider.of<CustomerProvider>(context, listen: false);
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Customer Permanently'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to permanently delete "${customer.name.length > 25 ? '${customer.name.substring(0, 25)}...' : customer.name}"?',
              ),
              const SizedBox(height: 8),
              const Text(
                'This will also delete ALL their loans and payment records.',
              ),
              const SizedBox(height: 8),
              const Text(
                'This action CANNOT be undone!',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Delete customer and all related data
      await customerProvider.deleteCustomer(customer.id!);

      // Refresh loans to remove orphaned loans from UI
      await loanProvider.loadLoans();
      await loanProvider.loadLoansWithCustomers();

      await _loadCustomers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${customer.name} and all related data deleted'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting customer: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ==================== Bulk Actions ====================
  // Bulk operations use atomic transactions to prevent orphaned data.
  // If any operation fails mid-way, the entire batch is rolled back.

  /// Bulk remove selected customers from current group
  Future<void> _bulkRemoveFromGroup() async {
    final selectedIds = _selectionProvider.getSelectedIdsList();
    if (selectedIds.isEmpty) return;

    final confirm = await GroupActionSheets.showRemoveFromGroupSheet(
      context: context,
      count: selectedIds.length,
      groupName: widget.group.name,
    );

    if (confirm != true) return;

    try {
      // Use atomic bulk operation
      final result = await CustomerGroupRepository.instance.bulkRemoveFromGroup(
        customerIds: selectedIds,
        groupId: widget.group.id!,
      );

      final successCount = result.dataOrNull ?? 0;

      _selectionProvider.exitSelectionMode();
      await _loadCustomers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '$successCount customer${successCount > 1 ? 's' : ''} removed from group'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing customers: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Bulk move selected customers to another group (removes from current, adds to new)
  /// Uses atomic transaction to prevent orphaned customers
  Future<void> _bulkMoveToGroup() async {
    final selectedIds = _selectionProvider.getSelectedIdsList();
    if (selectedIds.isEmpty) return;

    final targetGroup = await GroupActionSheets.showMoveToGroupSheet(
      context: context,
      availableGroups: _allGroups,
      count: selectedIds.length,
      currentGroupId: widget.group.id!,
    );

    if (targetGroup == null) return;

    try {
      // Use atomic transaction - ensures no orphaned customers on partial failure
      final result = await CustomerGroupRepository.instance.bulkMoveCustomers(
        customerIds: selectedIds,
        fromGroupId: widget.group.id!,
        toGroupId: targetGroup.id!,
      );

      final successCount = result.dataOrNull ?? 0;

      _selectionProvider.exitSelectionMode();
      await _loadCustomers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '$successCount customer${successCount > 1 ? 's' : ''} moved to "${targetGroup.name}"'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error moving customers: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Bulk add selected customers to additional groups (keeps in current group)
  /// Uses atomic transaction
  Future<void> _bulkAddToAnotherGroup() async {
    final selectedIds = _selectionProvider.getSelectedIdsList();
    if (selectedIds.isEmpty) return;

    final targetGroups = await GroupActionSheets.showAddToGroupSheet(
      context: context,
      availableGroups: _allGroups,
      count: selectedIds.length,
      currentGroupId: widget.group.id!,
    );

    if (targetGroups == null || targetGroups.isEmpty) return;

    try {
      // Use atomic bulk operation
      final targetGroupIds =
          targetGroups.where((g) => g.id != null).map((g) => g.id!).toList();

      await CustomerGroupRepository.instance.bulkAddToGroups(
        customerIds: selectedIds,
        groupIds: targetGroupIds,
      );

      _selectionProvider.exitSelectionMode();

      if (mounted) {
        final groupNames = targetGroups.map((g) => g.name).join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Added ${selectedIds.length} customer${selectedIds.length > 1 ? 's' : ''} to: $groupNames'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding customers to groups: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Bulk delete selected customers permanently
  Future<void> _bulkDeletePermanently() async {
    final selectedIds = _selectionProvider.getSelectedIdsList();
    if (selectedIds.isEmpty) return;

    // Capture provider references and ScaffoldMessenger BEFORE any async operations
    final customerProvider =
        Provider.of<CustomerProvider>(context, listen: false);
    final loanProvider = Provider.of<LoanProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final confirm = await GroupActionSheets.showDeletePermanentlySheet(
      context: context,
      count: selectedIds.length,
    );

    if (confirm != true) return;

    try {
      // Use bulk delete with single SQL transaction instead of N+1 individual deletes
      final successCount =
          await customerProvider.bulkDeleteCustomers(selectedIds);

      // Refresh loans to remove orphaned loans from UI
      await loanProvider.loadLoans();
      await loanProvider.loadLoansWithCustomers();

      _selectionProvider.exitSelectionMode();
      if (mounted) {
        await _loadCustomers();
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
              '$successCount customer${successCount > 1 ? 's' : ''} and all related data deleted'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error deleting customers: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
