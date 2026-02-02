import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/core/config/swipe_constants.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/features/swipe/models/swipe_filters.dart';
import 'package:super_swipe/features/swipe/providers/swipe_filters_provider.dart';

/// A bottom sheet panel for configuring swipe filters
class SwipeFiltersPanel extends ConsumerStatefulWidget {
  final VoidCallback? onFiltersChanged;
  final int initialEnergyLevel;
  final ValueChanged<int>? onEnergyLevelChanged;

  const SwipeFiltersPanel({
    super.key,
    this.onFiltersChanged,
    this.initialEnergyLevel = 2,
    this.onEnergyLevelChanged,
  });

  @override
  ConsumerState<SwipeFiltersPanel> createState() => _SwipeFiltersPanelState();
}

class _SwipeFiltersPanelState extends ConsumerState<SwipeFiltersPanel> {
  late TextEditingController _customTextController;
  late int _currentEnergyLevel;
  String? _previousSignature;

  @override
  void initState() {
    super.initState();
    _currentEnergyLevel = widget.initialEnergyLevel;
    _customTextController = TextEditingController(
      text: ref.read(swipeFiltersProvider).customText,
    );
    _previousSignature = ref.read(swipeFiltersProvider).signature;
  }

  @override
  void dispose() {
    _customTextController.dispose();
    super.dispose();
  }

  void _checkAndNotifyChange() {
    final currentSignature = ref.read(swipeFiltersProvider).signature;
    if (_previousSignature != currentSignature) {
      _previousSignature = currentSignature;
      widget.onFiltersChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(swipeFiltersProvider);
    final notifier = ref.read(swipeFiltersProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: AppTheme.mediumShadow,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Swipe Filters',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (filters.hasActiveFilters)
                    TextButton(
                      onPressed: () {
                        notifier.clearAll();
                        _customTextController.clear();
                        _checkAndNotifyChange();
                      },
                      child: const Text('Clear All'),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // ENERGY LEVEL SECTION (Moved from main screen)
              _SectionHeader(
                title: 'Energy Level',
                subtitle: 'How elaborate should recipes be?',
                icon: Icons.bolt_rounded,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppTheme.primaryColor,
                        inactiveTrackColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                        thumbColor: AppTheme.primaryColor,
                        trackHeight: 6,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                      ),
                      child: Slider(
                        value: _currentEnergyLevel.toDouble(),
                        min: 0,
                        max: 4,
                        divisions: 4,
                        label: EnergyLevel.fromInt(_currentEnergyLevel).sliderLabel,
                        onChanged: (v) {
                          final newVal = v.round();
                          if (newVal != _currentEnergyLevel) {
                            setState(() => _currentEnergyLevel = newVal);
                            widget.onEnergyLevelChanged?.call(newVal);
                          }
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            EnergyLevel.fromInt(_currentEnergyLevel).sliderLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            EnergyLevel.fromInt(_currentEnergyLevel).promptScale,
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // DIET SECTION (Hard Constraints)
              _SectionHeader(
                title: 'Diet',
                subtitle: 'Strict rules - recipes must follow these',
                icon: Icons.restaurant_menu_rounded,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SwipeDiet.values.map((diet) {
                  final isSelected = filters.diets.contains(diet);
                  return FilterChip(
                    label: Text(diet.displayName),
                    selected: isSelected,
                    onSelected: (selected) {
                      notifier.toggleDiet(diet);
                      _checkAndNotifyChange();
                    },
                    selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.primaryColor,
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // TIME SECTION
              _SectionHeader(
                title: 'Time Available',
                subtitle: 'How much time do you have?',
                icon: Icons.timer_outlined,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SwipeTimeFilter.values.map((time) {
                  final isSelected = filters.timeFilter == time;
                  return ChoiceChip(
                    label: Text(time.displayName),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        notifier.setTimeFilter(time);
                        _checkAndNotifyChange();
                      }
                    },
                    selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // MEAL TYPE SECTION
              _SectionHeader(
                title: 'Meal Type',
                subtitle: 'What kind of meal?',
                icon: Icons.food_bank_outlined,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // "Any" option
                  ChoiceChip(
                    label: const Text('Any'),
                    selected: filters.mealType == null,
                    onSelected: (selected) {
                      if (selected) {
                        notifier.setMealType(null);
                        _checkAndNotifyChange();
                      }
                    },
                    selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: filters.mealType == null ? AppTheme.primaryColor : AppTheme.textPrimary,
                      fontWeight: filters.mealType == null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  ...SwipeMealType.values.map((meal) {
                    final isSelected = filters.mealType == meal;
                    return ChoiceChip(
                      label: Text(meal.displayName),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          notifier.setMealType(meal);
                          _checkAndNotifyChange();
                        }
                      },
                      selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 24),

              // COOKING METHOD SECTION (Optional)
              _SectionHeader(
                title: 'Cooking Method',
                subtitle: 'Optional - prefer specific equipment',
                icon: Icons.microwave_outlined,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SwipeCookingMethod.values.map((method) {
                  final isSelected = filters.cookingMethods.contains(method);
                  return FilterChip(
                    label: Text(method.displayName),
                    selected: isSelected,
                    onSelected: (selected) {
                      notifier.toggleCookingMethod(method);
                      _checkAndNotifyChange();
                    },
                    selectedColor: Colors.blue.withValues(alpha: 0.15),
                    checkmarkColor: Colors.blue,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.blue : AppTheme.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // CUSTOM PREFERENCES SECTION
              _SectionHeader(
                title: 'Custom Preferences',
                subtitle: 'Add specific requests (max 200 chars)',
                icon: Icons.edit_note_rounded,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customTextController,
                maxLength: 200,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'e.g., Mediterranean style, spicy, kid-friendly...',
                  hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                  ),
                  counterStyle: TextStyle(color: AppTheme.textSecondary),
                ),
                onChanged: (value) {
                  notifier.setCustomText(value);
                  // Don't notify immediately on typing - wait for done
                },
                onEditingComplete: () {
                  FocusScope.of(context).unfocus();
                  _checkAndNotifyChange();
                },
              ),
              const SizedBox(height: 24),

              // APPLY BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Update custom text before closing
                    notifier.setCustomText(_customTextController.text);
                    _checkAndNotifyChange();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Apply Filters',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section header widget
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Helper function to show the filters panel as a bottom sheet
Future<void> showSwipeFiltersPanel(
  BuildContext context, {
  VoidCallback? onFiltersChanged,
  int initialEnergyLevel = 2,
  ValueChanged<int>? onEnergyLevelChanged,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return SwipeFiltersPanel(
          onFiltersChanged: onFiltersChanged,
          initialEnergyLevel: initialEnergyLevel,
          onEnergyLevelChanged: onEnergyLevelChanged,
        );
      },
    ),
  );
}

/// Small filter badge to show active filter count in app bar
class SwipeFilterBadge extends ConsumerWidget {
  const SwipeFilterBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(swipeFiltersProvider);
    final activeCount = _countActiveFilters(filters);

    if (activeCount == 0) {
      return const Icon(Icons.tune_rounded);
    }

    return Badge(
      label: Text('$activeCount'),
      backgroundColor: AppTheme.primaryColor,
      child: const Icon(Icons.tune_rounded),
    );
  }

  int _countActiveFilters(SwipeFilters filters) {
    int count = 0;
    count += filters.diets.length;
    if (filters.timeFilter != SwipeTimeFilter.anyTime) count++;
    if (filters.mealType != null) count++;
    count += filters.cookingMethods.length;
    if (filters.customText.trim().isNotEmpty) count++;
    return count;
  }
}

