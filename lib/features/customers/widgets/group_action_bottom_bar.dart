import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Floating action bar for bulk operations on selected customers (WhatsApp-style)
class GroupActionBottomBar extends StatelessWidget {
  final int selectedCount;
  final Color groupColor;
  final VoidCallback onRemoveFromGroup;
  final VoidCallback onMoveToGroup;
  final VoidCallback onAddToAnotherGroup;
  final VoidCallback onDeletePermanently;

  const GroupActionBottomBar({
    super.key,
    required this.selectedCount,
    required this.groupColor,
    required this.onRemoveFromGroup,
    required this.onMoveToGroup,
    required this.onAddToAnotherGroup,
    required this.onDeletePermanently,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        // Use group color as a subtle top border accent
        border: Border(
          top: BorderSide(color: groupColor.withValues(alpha: 0.3), width: 2),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show selected count with group color accent
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$selectedCount selected',
                style: TextStyle(
                  color: groupColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.remove_circle_outline,
                  label: 'Remove',
                  color: Colors.orange,
                  onTap: onRemoveFromGroup,
                ),
                _buildActionButton(
                  icon: Icons.drive_file_move_outline,
                  label: 'Move',
                  color: AppColors.info,
                  onTap: onMoveToGroup,
                ),
                _buildActionButton(
                  icon: Icons.add_circle_outline,
                  label: 'Add to',
                  color: AppColors.success,
                  onTap: onAddToAnotherGroup,
                ),
            _buildActionButton(
              icon: Icons.delete_forever,
              label: 'Delete',
              color: AppColors.error,
              onTap: onDeletePermanently,
            ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
