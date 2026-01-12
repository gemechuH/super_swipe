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
    super.dispose();
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

    return SizedBox(
      height:
          MediaQuery.of(context).size.height *
          0.80, // 80% to ensure button visible
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select Ingredients',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),

          // Custom Input
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customController,
                    enabled: !widget.isApplying,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: 'Type to add item...',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _addCustomItem(),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: widget.isApplying ? null : _addCustomItem,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primaryColor,
            tabs: _tabs.map((c) => Tab(text: c)).toList(),
          ),

          // Content
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

          // Action Button - Wrapped in SafeArea to ensure visibility
          SafeArea(
            minimum: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (!hasChanges || widget.isApplying)
                      ? null
                      : _handleApply,
                  icon: widget.isApplying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: AppInlineLoading(
                            size: 18,
                            baseColor: Color(0xFFEFEFEF),
                            highlightColor: Color(0xFFFFFFFF),
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_getButtonLabel()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
    // Combine existing custom norms and manually added norms
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
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Type an ingredient above to add a custom item',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final key = items[index];
        final isSelected = _selectedByNorm.containsKey(key);
        return CheckboxListTile(
          value: isSelected,
          onChanged: widget.isApplying
              ? null
              : (v) => setState(() {
                  if (v == true) {
                    _selectedByNorm[key] = 'other';
                  } else {
                    _selectedByNorm.remove(key);
                  }
                }),
          title: Text(_labelByNorm[key] ?? key),
          subtitle: _getSubtitle(key),
          controlAffinity: ListTileControlAffinity.leading,
        );
      },
    );
  }

  Widget _buildCategoryView(PantryCategory category) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: category.subCategories.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
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
              title: Text(
                subCategory.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              childrenPadding: EdgeInsets.zero,
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
                  title: Text(item),
                  // Optional: show status if relevant
                  subtitle: _getSubtitle(key),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppTheme.primaryColor,
                  contentPadding: const EdgeInsets.only(left: 16, right: 8),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Text? _getSubtitle(String key) {
    if (_activeInPantryByNorm.containsKey(key)) return const Text('In pantry');
    if (_depletedInPantryByNorm.containsKey(key)) return const Text('Depleted');
    return null;
  }
}
