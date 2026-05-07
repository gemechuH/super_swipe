import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/core/config/pantry_constants.dart';
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';

/// Reusable 3-layer category selector for adding ingredients
/// Fetches category configuration dynamically
class PantryCategorySelector extends ConsumerWidget {
  final List<PantryItem> existingPantryItems;
  final Function(
    Set<String> toAdd,
    Set<String> toRemove,
    Map<String, String> categoryMap,
  )
  onApply;
  final bool isApplying;

  const PantryCategorySelector({
    super.key,
    this.existingPantryItems = const [],
    required this.onApply,
    this.isApplying = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(pantryCategoriesProvider);

    return categoriesAsync.when(
      data: (categories) => _PantryCategorySelectorContent(
        existingPantryItems: existingPantryItems,
        onApply: onApply,
        isApplying: isApplying,
        categories: categories,
      ),
      loading: () => SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: const AppListLoading(itemCount: 6),
      ),
      error: (err, stack) => SizedBox(
        height: 200,
        child: Center(child: Text('Error loading categories: $err')),
      ),
    );
  }
}

class _PantryCategorySelectorContent extends StatefulWidget {
  final List<PantryItem> existingPantryItems;
  final Function(
    Set<String> toAdd,
    Set<String> toRemove,
    Map<String, String> categoryMap,
  )
  onApply;
  final bool isApplying;
  final List<PantryCategory> categories;

  const _PantryCategorySelectorContent({
    // ignore: unused_element
    required this.existingPantryItems,
    required this.onApply,
    required this.isApplying,
    required this.categories,
  });

  @override
  State<_PantryCategorySelectorContent> createState() =>
      _PantryCategorySelectorContentState();
}

class _PantryCategorySelectorContentState
    extends State<_PantryCategorySelectorContent>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _customController;
  late final List<String> _tabs;

  // Normalization helper
  String _norm(String s) => s.toLowerCase().trim();

  // State
  final Map<String, String> _selectedByNorm = {}; // key -> category
  final Map<String, String> _labelByNorm = {}; // key -> display name

  // Predefined knowledge
  final Set<String> _predefinedNorms = {};
  final Map<String, String> _predefinedCategoryByNorm = {};

  // Custom/Manual items
  final Set<String> _customManualNorms = {};
  final Set<String> _customExistingNorms = {};

  // Existing pantry state (for "In pantry" / "Depleted" labels)
  final Map<String, bool> _activeInPantryByNorm = {};
  final Map<String, bool> _depletedInPantryByNorm = {};

  // Initial active set to check for removals
  late final Set<String> _initialActiveNorms;

  // Search state
  String _searchQuery = '';
  List<String> _searchSuggestions = [];
  bool _showSuggestions = false;
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _tabs = [...widget.categories.map((c) => c.title), 'Custom'];
    _tabController = TabController(length: _tabs.length, vsync: this);
    _customController = TextEditingController();

    _initializeData();
  }

  void _initializeData() {
    // 1. Index Predefined Categories (Dynamic)
    for (final category in widget.categories) {
      final categoryKey = category.title.toLowerCase();
      for (final sub in category.subCategories) {
        for (final item in sub.items) {
          final key = _norm(item);
          if (key.isEmpty) continue;
          _predefinedNorms.add(key);
          _predefinedCategoryByNorm[key] = categoryKey;
          _labelByNorm[key] = item;
        }
      }
    }

    // 2. Index Existing Pantry Items
    for (final item in widget.existingPantryItems) {
      final key = _norm(item.normalizedName);
      if (key.isEmpty) continue;

      _labelByNorm.putIfAbsent(key, () => item.name);

      if (item.quantity > 0) {
        _activeInPantryByNorm[key] = true;
        // Pre-select active items
        if (_predefinedNorms.contains(key)) {
          _selectedByNorm[key] = _predefinedCategoryByNorm[key] ?? 'other';
        } else {
          _selectedByNorm[key] = 'other'; // Or item.category
          _customExistingNorms.add(key); // It's custom if not in predefined
        }
      } else {
        _depletedInPantryByNorm[key] = true;
        // Depleted items are known but not currently selected
        if (!_predefinedNorms.contains(key)) {
          _customExistingNorms.add(key);
        }
      }
    }

    // Store initial active set for diffing
    _initialActiveNorms = _selectedByNorm.keys.toSet();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim();
      if (_searchQuery.length >= 2) {
        _searchSuggestions = _getSearchSuggestions(_searchQuery);
        _showSuggestions = true;
      } else {
        _searchSuggestions = [];
        _showSuggestions = false;
      }
    });
  }

  List<String> _getSearchSuggestions(String query) {
    final queryLower = query.toLowerCase();
    final suggestions = <String>[];

    // Search through all predefined ingredients
    for (final key in _predefinedNorms) {
      final label = _labelByNorm[key] ?? key;
      final labelLower = label.toLowerCase();

      // Exact match or starts with
      if (labelLower.contains(queryLower)) {
        suggestions.add(key);
      }
    }

    // Sort by relevance: starts with query first, then contains
    suggestions.sort((a, b) {
      final aLabel = (_labelByNorm[a] ?? a).toLowerCase();
      final bLabel = (_labelByNorm[b] ?? b).toLowerCase();
      final aStarts = aLabel.startsWith(queryLower);
      final bStarts = bLabel.startsWith(queryLower);

      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;
      return aLabel.compareTo(bLabel);
    });

    // Limit to 8 suggestions for performance
    return suggestions.take(8).toList();
  }

  void _selectSuggestion(String key) {
    setState(() {
      if (_predefinedNorms.contains(key)) {
        _selectedByNorm[key] = _predefinedCategoryByNorm[key] ?? 'other';
      } else {
        _selectedByNorm[key] = 'other';
      }
      _customController.clear();
      _searchQuery = '';
      _showSuggestions = false;
      _searchFocusNode.requestFocus();
    });
  }

  void _addCustomItem() {
    final raw = _customController.text.trim();
    if (raw.isEmpty) return;
    final key = _norm(raw);
    if (key.isEmpty) return;

    setState(() {
      if (_predefinedNorms.contains(key)) {
        // It's a known item, just select it
        _selectedByNorm[key] = _predefinedCategoryByNorm[key] ?? 'other';
        _labelByNorm[key] = _labelByNorm[key] ?? raw;
      } else {
        // It's a new custom item
        _customManualNorms.add(key);
        _selectedByNorm[key] = 'other';
        _labelByNorm[key] = raw;
      }
      _customController.clear();
      _searchQuery = '';
      _showSuggestions = false;
      _searchFocusNode.requestFocus();
    });
  }

  void _handleApply() {
    final currentSelected = _selectedByNorm.keys.toSet();
    final toAdd = currentSelected.difference(_initialActiveNorms);
    final toRemove = _initialActiveNorms.difference(currentSelected);

    widget.onApply(toAdd, toRemove, _selectedByNorm);
  }

  @override
  Widget build(BuildContext context) {
    final hasChanges = _checkForChanges();
    final screenHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenHeight * 0.85,
      child: Stack(
        children: [
          // Main content
          Column(
            children: [
              SizedBox(height: screenHeight * 0.005),
              // Handle
              Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),

              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  screenHeight * 0.008,
                  16,
                  screenHeight * 0.004,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select Ingredients',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // Custom Input with Search
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, screenHeight * 0.008),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customController,
                        focusNode: _searchFocusNode,
                        enabled: !widget.isApplying,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Search or add ingredient...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: Colors.grey[400],
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: _onSearchChanged,
                        onSubmitted: (_) => _addCustomItem(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: widget.isApplying ? null : _addCustomItem,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(10),
                        minimumSize: const Size(36, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Icon(Icons.add_rounded, size: 18),
                    ),
                  ],
                ),
              ),

              // Spacer for suggestions
              if (_showSuggestions) SizedBox(height: screenHeight * 0.008),

              // Tabs
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppTheme.primaryColor,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorColor: AppTheme.primaryColor,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                tabs: _tabs.map((c) => Tab(text: c)).toList(),
              ),

              // Content - takes remaining space minus button height
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    ...widget.categories.map(
                      (category) => _buildCategoryView(category),
                    ),
                    _buildCustomTab(),
                  ],
                ),
              ),

              // Bottom padding for fixed button
              const SizedBox(height: 70),
            ],
          ),

          // Positioned Search Suggestions Dropdown (overlays on top)
          if (_showSuggestions && _searchSuggestions.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              top: screenHeight * 0.12,
              child: Container(
                constraints: BoxConstraints(maxHeight: screenHeight * 0.35),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _searchSuggestions.length,
                  itemBuilder: (context, index) {
                    final key = _searchSuggestions[index];
                    final label = _labelByNorm[key] ?? key;
                    final isAlreadySelected = _selectedByNorm.containsKey(key);

                    return ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -2),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      leading: Icon(
                        isAlreadySelected
                            ? Icons.check_circle_rounded
                            : Icons.add_circle_outline_rounded,
                        size: 18,
                        color: isAlreadySelected
                            ? Colors.green[600]
                            : AppTheme.primaryColor,
                      ),
                      title: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isAlreadySelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isAlreadySelected
                              ? Colors.green[700]
                              : Colors.black87,
                        ),
                      ),
                      subtitle: _getSubtitle(key),
                      onTap: isAlreadySelected
                          ? null
                          : () => _selectSuggestion(key),
                    );
                  },
                ),
              ),
            ),

          // Positioned "Add as new" option when no results
          if (_showSuggestions &&
              _searchSuggestions.isEmpty &&
              _searchQuery.length >= 2)
            Positioned(
              left: 16,
              right: 16,
              top: screenHeight * 0.12,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -2),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  leading: Icon(
                    Icons.add_circle_rounded,
                    size: 18,
                    color: AppTheme.primaryColor,
                  ),
                  title: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                      children: [
                        const TextSpan(text: 'Add "'),
                        TextSpan(
                          text: _searchQuery,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(text: '" as new ingredient'),
                      ],
                    ),
                  ),
                  onTap: _addCustomItem,
                ),
              ),
            ),

          // Fixed Apply Button at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (!hasChanges || widget.isApplying)
                          ? null
                          : _handleApply,
                      icon: widget.isApplying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: AppInlineLoading(
                                size: 16,
                                baseColor: Color(0xFFEFEFEF),
                                highlightColor: Color(0xFFFFFFFF),
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _getButtonLabel(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _checkForChanges() {
    final currentSelected = _selectedByNorm.keys.toSet();
    final toAdd = currentSelected.difference(_initialActiveNorms);
    final toRemove = _initialActiveNorms.difference(currentSelected);
    return toAdd.isNotEmpty || toRemove.isNotEmpty;
  }

  String _getButtonLabel() {
    final currentSelected = _selectedByNorm.keys.toSet();
    final toAdd = currentSelected.difference(_initialActiveNorms);
    final toRemove = _initialActiveNorms.difference(currentSelected);

    if (toAdd.isEmpty && toRemove.isEmpty) return 'No changes';

    final parts = <String>[];
    if (toAdd.isNotEmpty) parts.add('+${toAdd.length}');
    if (toRemove.isNotEmpty) parts.add('-${toRemove.length}');

    return 'Apply Changes (${parts.join(" / ")})';
  }

  Widget _buildCustomTab() {
    final items =
        <String>{..._customExistingNorms, ..._customManualNorms}.toList()..sort(
          (a, b) => (_labelByNorm[a] ?? a).compareTo(_labelByNorm[b] ?? b),
        );

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline_rounded,
                size: 40,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                'Type an ingredient above to add a custom item',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final key = items[index];
        final isSelected = _selectedByNorm.containsKey(key);
        return CheckboxListTile(
          value: isSelected,
          dense: true,
          onChanged: widget.isApplying
              ? null
              : (v) => setState(() {
                  if (v == true) {
                    _selectedByNorm[key] = 'other';
                  } else {
                    _selectedByNorm.remove(key);
                  }
                }),
          title: Text(
            _labelByNorm[key] ?? key,
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: _getSubtitle(key),
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppTheme.primaryColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 0,
          ),
          visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
        );
      },
    );
  }

  Widget _buildCategoryView(PantryCategory category) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      itemCount: category.subCategories.length,
      separatorBuilder: (context, index) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final subCategory = category.subCategories[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 0,
              ),
              childrenPadding: EdgeInsets.zero,
              title: Text(
                subCategory.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              trailing: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: Colors.grey[600],
              ),
              children: subCategory.items.map((item) {
                final key = _norm(item);
                final isSelected = _selectedByNorm.containsKey(key);
                return CheckboxListTile(
                  dense: true,
                  value: isSelected,
                  onChanged: widget.isApplying
                      ? null
                      : (v) => setState(() {
                          if (v == true) {
                            _selectedByNorm[key] = category.title.toLowerCase();
                            _labelByNorm[key] = item;
                          } else {
                            _selectedByNorm.remove(key);
                          }
                        }),
                  title: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  subtitle: _getSubtitle(key),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppTheme.primaryColor,
                  contentPadding: const EdgeInsets.only(
                    left: 10,
                    right: 6,
                    top: 0,
                    bottom: 0,
                  ),
                  visualDensity: const VisualDensity(
                    horizontal: 0,
                    vertical: -3,
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Text? _getSubtitle(String key) {
    if (_activeInPantryByNorm.containsKey(key)) {
      return Text(
        'In pantry',
        style: TextStyle(fontSize: 10, color: Colors.green[700]),
      );
    }
    if (_depletedInPantryByNorm.containsKey(key)) {
      return Text(
        'Depleted',
        style: TextStyle(fontSize: 10, color: Colors.orange[700]),
      );
    }
    return null;
  }
}

