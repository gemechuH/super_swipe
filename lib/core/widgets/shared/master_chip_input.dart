import 'package:flutter/material.dart';
import 'package:super_swipe/core/theme/app_theme.dart';

/// A reusable "Type & Add" chip input widget.
/// Users type text, press Enter or tap (+), and items appear as deletable chips.
class MasterChipInput extends StatefulWidget {
  final String label;
  final String hint;
  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final Color chipColor;
  final Color chipTextColor;
  final IconData? leadingIcon;

  const MasterChipInput({
    super.key,
    required this.label,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.chipColor = const Color(0xFFE8F5E9),
    this.chipTextColor = const Color(0xFF2E7D32),
    this.leadingIcon,
  });

  @override
  State<MasterChipInput> createState() => _MasterChipInputState();
}

class _MasterChipInputState extends State<MasterChipInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addItem(String value) {
    final trimmed = value.toLowerCase().trim();
    if (trimmed.isEmpty) return;
    if (widget.items.contains(trimmed)) return;

    final newList = [...widget.items, trimmed];
    widget.onChanged(newList);
    _controller.clear();
  }

  void _removeItem(String value) {
    final newList = widget.items.where((i) => i != value).toList();
    widget.onChanged(newList);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with icon
        if (widget.leadingIcon != null || widget.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D2621),
              ),
            ),
          ),

        // Input field
        SizedBox(
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                    ),
                    onSubmitted: _addItem,
                    textInputAction: TextInputAction.done,
                  ),
                ),
                GestureDetector(
                  onTap: () => _addItem(_controller.text),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.add_circle,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Chips display
        if (widget.items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.items
                .map(
                  (item) => Chip(
                    label: Text(item, style: const TextStyle(fontSize: 11)),
                    backgroundColor: widget.chipColor,
                    deleteIcon: const Icon(Icons.close, size: 14),
                    deleteIconColor: widget.chipTextColor,
                    onDeleted: () => _removeItem(item),
                    labelStyle: TextStyle(
                      color: widget.chipTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                    side: BorderSide.none,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: 0,
                      vertical: -2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}
