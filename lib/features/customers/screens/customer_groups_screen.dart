import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/models/customer_group.dart';
import 'group_customers_screen.dart';

// NOTE: GroupCustomersScreen has been extracted to group_customers_screen.dart
// This file now contains only CustomerGroupsScreen (~600 lines)

class CustomerGroupsScreen extends StatefulWidget {
  const CustomerGroupsScreen({super.key});

  @override
  State<CustomerGroupsScreen> createState() => _CustomerGroupsScreenState();
}

class _CustomerGroupsScreenState extends State<CustomerGroupsScreen> {
  List<CustomerGroup> _groups = [];
  Map<int, int> _groupCustomerCounts = {};
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Load groups with customer counts in a SINGLE optimized query
  /// Fixes N+1 query issue - previously did O(N) queries for N groups
  Future<void> _loadGroups({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }

    try {
      // Single query fetches all groups with their customer counts
      final groupsWithCounts =
          await DatabaseService.instance.getAllCustomerGroupsWithCounts();
      final groups = <CustomerGroup>[];
      final counts = <int, int>{};

      for (final row in groupsWithCounts) {
        final group = CustomerGroup.fromMap(row);
        groups.add(group);
        if (group.id != null) {
          counts[group.id!] = row['customer_count'] as int? ?? 0;
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
                  onRefresh: () => _loadGroups(showLoading: false),
                  child: ListView.builder(
                    key: const PageStorageKey('customer_groups_list'),
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
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

    // Capture ScaffoldMessenger before async gap to avoid invalid context
    final scaffoldMessenger = ScaffoldMessenger.of(context);
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
      if (mounted) {
        await _loadGroups();
      }

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Group created successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error creating group: $e'),
          backgroundColor: AppColors.error,
        ),
      );
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

    // Capture ScaffoldMessenger before async gap to avoid invalid context
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);

    try {
      final updated = group.copyWith(
        name: name,
        colorValue: colorValue,
        description: description.isEmpty ? null : description,
        updatedAt: DateTime.now(),
      );

      await DatabaseService.instance.updateCustomerGroup(updated);
      if (mounted) {
        await _loadGroups();
      }

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Group updated successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error updating group: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _viewGroupCustomers(CustomerGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupCustomersScreen(group: group),
      ),
    ).then((_) => _loadGroups(showLoading: false));
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
