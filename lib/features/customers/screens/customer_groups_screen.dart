import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/database_service.dart';
import '../../../core/repositories/customer_group_repository.dart';
import '../../../core/services/permission_service.dart';
import '../../../shared/models/customer_group.dart';
import '../../../shared/models/customer.dart';
import '../../customer_management/screens/customer_detail_screen.dart';
import '../../customer_management/providers/customer_provider.dart';
import '../../loan_management/providers/loan_provider.dart';

class CustomerGroupsScreen extends StatefulWidget {
  const CustomerGroupsScreen({super.key});

  @override
  State<CustomerGroupsScreen> createState() => _CustomerGroupsScreenState();
}

class _CustomerGroupsScreenState extends State<CustomerGroupsScreen> {
  List<CustomerGroup> _groups = [];
  Map<int, int> _groupCustomerCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);

    try {
      final groups = await DatabaseService.instance.getAllCustomerGroups();
      final counts = <int, int>{};

      for (final group in groups) {
        if (group.id != null) {
          counts[group.id!] =
              await DatabaseService.instance.getCustomerCountInGroup(group.id!);
        }
      }

      if (mounted) {
        setState(() {
          _groups = groups;
          _groupCustomerCounts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading groups: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddGroupDialog,
            tooltip: 'Create Group',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadGroups,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _groups.length,
                    itemBuilder: (context, index) {
                      return _buildGroupCard(_groups[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_outlined,
            size: 80,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No customer groups',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create groups to organize your customers',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showAddGroupDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create Group'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(CustomerGroup group) {
    final count = _groupCustomerCounts[group.id] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: group.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.group,
            color: group.color,
            size: 28,
          ),
        ),
        title: Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$count customer${count != 1 ? 's' : ''}'),
            if (group.description != null && group.description!.isNotEmpty)
              Text(
                group.description!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleGroupAction(value, group),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit),
                title: Text('Edit'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'view',
              child: ListTile(
                leading: Icon(Icons.visibility),
                title: Text('View Customers'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('Delete', style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        onTap: () => _viewGroupCustomers(group),
      ),
    );
  }

  void _showAddGroupDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    int selectedColorIndex = 0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  maxLength: 50,
                  decoration: const InputDecoration(
                    labelText: 'Group Name *',
                    hintText: 'Enter group name',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    hintText: 'Enter description',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                const Text('Select Color:',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                _buildColorPicker(selectedColorIndex, (index) {
                  setDialogState(() => selectedColorIndex = index);
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _createGroup(
                nameController.text.trim(),
                descController.text.trim(),
                GroupColors.presetColors[selectedColorIndex],
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker(int selectedIndex, Function(int) onSelect) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(GroupColors.presetColors.length, (index) {
        final color = Color(GroupColors.presetColors[index]);
        final isSelected = index == selectedIndex;

        return GestureDetector(
          onTap: () => onSelect(index),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border:
                  isSelected ? Border.all(color: Colors.white, width: 3) : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 2)
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
        );
      }),
    );
  }

  Future<void> _createGroup(
      String name, String description, int colorValue) async {
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a group name'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    Navigator.pop(context);

    try {
      final now = DateTime.now();
      final group = CustomerGroup(
        name: name,
        colorValue: colorValue,
        description: description.isEmpty ? null : description,
        createdAt: now,
        updatedAt: now,
      );

      await DatabaseService.instance.insertCustomerGroup(group);
      await _loadGroups();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group created successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating group: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _handleGroupAction(String action, CustomerGroup group) {
    switch (action) {
      case 'edit':
        _showEditGroupDialog(group);
        break;
      case 'view':
        _viewGroupCustomers(group);
        break;
      case 'delete':
        _deleteGroup(group);
        break;
    }
  }

  void _showEditGroupDialog(CustomerGroup group) {
    final nameController = TextEditingController(text: group.name);
    final descController = TextEditingController(text: group.description ?? '');
    int selectedColorIndex = GroupColors.presetColors.indexOf(group.colorValue);
    if (selectedColorIndex < 0) selectedColorIndex = 0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  maxLength: 50,
                  decoration: const InputDecoration(
                    labelText: 'Group Name *',
                    hintText: 'Enter group name',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    hintText: 'Enter description',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                const Text('Select Color:',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                _buildColorPicker(selectedColorIndex, (index) {
                  setDialogState(() => selectedColorIndex = index);
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _updateGroup(
                group,
                nameController.text.trim(),
                descController.text.trim(),
                GroupColors.presetColors[selectedColorIndex],
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateGroup(CustomerGroup group, String name,
      String description, int colorValue) async {
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a group name'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    Navigator.pop(context);

    try {
      final updated = group.copyWith(
        name: name,
        colorValue: colorValue,
        description: description.isEmpty ? null : description,
        updatedAt: DateTime.now(),
      );

      await DatabaseService.instance.updateCustomerGroup(updated);
      await _loadGroups();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating group: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _viewGroupCustomers(CustomerGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupCustomersScreen(group: group),
      ),
    ).then((_) => _loadGroups());
  }

  void _deleteGroup(CustomerGroup group) {
    final count = _groupCustomerCounts[group.id] ?? 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete "${group.name.length > 30 ? '${group.name.substring(0, 30)}...' : group.name}"?',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (count > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.warning, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$count customer${count != 1 ? 's' : ''} will be removed from this group.',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Capture context-dependent references before async
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);

              try {
                await DatabaseService.instance.deleteCustomerGroup(group.id!);
                if (mounted) {
                  await _loadGroups();
                }

                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Group deleted'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Error deleting group: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Screen to view and manage customers in a specific group - Like Home Page
class GroupCustomersScreen extends StatefulWidget {
  final CustomerGroup group;

  const GroupCustomersScreen({super.key, required this.group});

  @override
  State<GroupCustomersScreen> createState() => _GroupCustomersScreenState();
}

class _GroupCustomersScreenState extends State<GroupCustomersScreen> {
  List<Customer> _customers = [];
  List<Customer> _allCustomersForSearch = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Defer loading to after the first frame to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);

    try {
      // Use CustomerGroupRepository which queries junction table for multi-group support
      final result =
          await CustomerGroupRepository.instance.getCustomers(widget.group.id);
      final customers = result.dataOrNull ?? [];

      if (mounted) {
        setState(() {
          _customers = customers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading customers: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  List<Customer> get _filteredCustomers {
    if (_searchQuery.isEmpty) return _customers;
    return _customers
        .where((c) =>
            c.name.toLowerCase().contains(_searchQuery) ||
            c.phoneNumber.contains(_searchQuery))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Stats Header - hide when keyboard is visible
                  if (!keyboardVisible) _buildStatsHeader(),

                  // Customer List
                  Expanded(
                    child: _filteredCustomers.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _loadCustomers,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredCustomers.length,
                              itemBuilder: (context, index) {
                                return _buildCustomerCard(
                                    _filteredCustomers[index]);
                              },
                            ),
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCustomerToGroupDialog,
        backgroundColor: widget.group.color,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_isSearching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _isSearching = false;
              _searchQuery = '';
              _searchController.clear();
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
          onChanged: (value) {
            setState(() {
              _searchQuery = value.toLowerCase();
            });
          },
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                });
              },
            ),
        ],
      );
    }

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

  Widget _buildCustomerCard(Customer customer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openCustomerDetail(customer),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 28,
                backgroundColor: widget.group.color.withValues(alpha: 0.15),
                child: Text(
                  customer.name.isNotEmpty
                      ? customer.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: widget.group.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Customer Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.phone,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          customer.phoneNumber,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    if (customer.address != null &&
                        customer.address!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on,
                                size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                customer.address!,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Action Buttons
              Column(
                children: [
                  // Call Button
                  IconButton(
                    icon: const Icon(Icons.call, color: AppColors.success),
                    onPressed: () => _callCustomer(customer),
                    tooltip: 'Call',
                  ),
                  // More Options Menu
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        color: AppColors.textSecondary),
                    onSelected: (value) {
                      switch (value) {
                        case 'remove':
                          _removeFromGroup(customer);
                          break;
                        case 'delete':
                          _deleteCustomerEntirely(customer);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(Icons.remove_circle_outline,
                                color: Colors.orange),
                            SizedBox(width: 8),
                            Text('Remove from Group'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_forever, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('Delete Entirely',
                                style: TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCustomerDetail(Customer customer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerDetailScreen(
          customerId: customer.id!,
          initialTabIndex: 0, // Show overview tab (same as homepage)
        ),
      ),
    ).then((_) => _loadCustomers());
  }

  Future<void> _callCustomer(Customer customer) async {
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

    final hasPermission =
        await PermissionService.instance.requestPhonePermission();

    if (hasPermission) {
      final uri = Uri.parse('tel:$phoneToCall');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Phone permission required'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => PermissionService.instance.openSettings(),
            ),
          ),
        );
      }
    }
  }

  void _showAddCustomerToGroupDialog() async {
    // Get all customers and check which are already in this group
    final allCustomers = await DatabaseService.instance.getAllCustomers();

    // Get customers already in this group
    final customersInGroupResult =
        await CustomerGroupRepository.instance.getCustomers(widget.group.id);
    final customersInGroup = customersInGroupResult.dataOrNull ?? [];
    final customerIdsInGroup = customersInGroup.map((c) => c.id).toSet();

    // Allow ALL customers to be added (they can be in multiple groups)
    _allCustomersForSearch =
        allCustomers.where((c) => !customerIdsInGroup.contains(c.id)).toList();

    if (!mounted) return;

    if (_allCustomersForSearch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All customers are already in this group'),
          backgroundColor: AppColors.info,
        ),
      );
      return;
    }

    final searchController = TextEditingController();
    List<Customer> filteredList = List.from(_allCustomersForSearch);

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
                // Search Bar
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
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      if (value.isEmpty) {
                        filteredList = List.from(_allCustomersForSearch);
                      } else {
                        final query = value.toLowerCase();
                        filteredList = _allCustomersForSearch
                            .where((c) =>
                                c.name.toLowerCase().contains(query) ||
                                c.phoneNumber.contains(query))
                            .toList();
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),

                // Customer Count
                Text(
                  '${filteredList.length} customer${filteredList.length != 1 ? 's' : ''} available',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),

                // Customer List
                Expanded(
                  child: filteredList.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off,
                                  size: 48, color: AppColors.textSecondary),
                              SizedBox(height: 8),
                              Text(
                                'No customers found',
                                style:
                                    TextStyle(color: AppColors.textSecondary),
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
                                backgroundColor:
                                    widget.group.color.withValues(alpha: 0.1),
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
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
}
