import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/core/widgets/shared/shared_widgets.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/services/database/database_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Form state - ALL are type-and-add lists
  List<String> _allergies = [];
  List<String> _dietaryRestrictions = [];
  List<String> _preferredCuisines = [];
  String? _defaultMealType;
  String _pantryFlexibility = 'lenient';
  String _defaultDifficulty = 'easy';
  int _defaultEnergyLevel = 2;
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  void _loadPreferences() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProfile = ref.read(userProfileProvider).value;
      if (userProfile != null) {
        setState(() {
          _allergies = List.from(userProfile.preferences.allergies);
          _dietaryRestrictions = List.from(
            userProfile.preferences.dietaryRestrictions,
          );
          _preferredCuisines = List.from(
            userProfile.preferences.preferredCuisines,
          );
          _pantryFlexibility = userProfile.preferences.pantryFlexibility;
          _defaultDifficulty = userProfile.preferences.defaultDifficulty;
          _defaultEnergyLevel = userProfile.preferences.defaultEnergyLevel;
          // Load default meal type
          _defaultMealType = userProfile.preferences.defaultMealType.isNotEmpty
              ? userProfile.preferences.defaultMealType
              : 'dinner';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final userProfileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Settings',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_hasUnsavedChanges && !_isSaving)
            TextButton(
              onPressed: _savePreferences,
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: AppInlineLoading(size: 16),
              ),
            ),
        ],
      ),
      body: userProfileAsync.when(
        loading: () => const AppPageLoading(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (profile) => MasterScrollWrapper(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // =============================================
              // ALLERGIES - Type & Add
              // =============================================
              _buildSectionCard(
                child: MasterChipInput(
                  label: 'Allergies',
                  hint: 'Type allergy (e.g., Peanuts)...',
                  leadingIcon: Icons.warning_amber_rounded,
                  items: _allergies,
                  chipColor: Colors.red.shade50,
                  chipTextColor: Colors.red.shade700,
                  onChanged: (items) {
                    setState(() {
                      _allergies = items;
                      _hasUnsavedChanges = true;
                    });
                  },
                ),
              ),

              const SizedBox(height: 12),

              // =============================================
              // DIETARY RESTRICTIONS - Type & Add
              // =============================================
              _buildSectionCard(
                child: MasterChipInput(
                  label: 'Dietary Restrictions',
                  hint: 'Type restriction (e.g., Vegan)...',
                  leadingIcon: Icons.eco_rounded,
                  items: _dietaryRestrictions,
                  chipColor: Colors.green.shade50,
                  chipTextColor: Colors.green.shade700,
                  onChanged: (items) {
                    setState(() {
                      _dietaryRestrictions = items;
                      _hasUnsavedChanges = true;
                    });
                  },
                ),
              ),

              const SizedBox(height: 12),

              // =============================================
              // FAVORITE CUISINES - Type & Add
              // =============================================
              _buildSectionCard(
                child: MasterChipInput(
                  label: 'Favorite Cuisines',
                  hint: 'Type cuisine (e.g., Italian)...',
                  leadingIcon: Icons.public_rounded,
                  items: _preferredCuisines,
                  chipColor: Colors.blue.shade50,
                  chipTextColor: Colors.blue.shade700,
                  onChanged: (items) {
                    setState(() {
                      _preferredCuisines = items;
                      _hasUnsavedChanges = true;
                    });
                  },
                ),
              ),

              const SizedBox(height: 12),

              // =============================================
              // DEFAULT MEAL TYPE - Selector
              // =============================================
              _buildSectionCard(
                child: MealTypeSelector(
                  label: 'Default Meal Type',
                  selectedMealType: _defaultMealType,
                  scrollable: true,
                  onChanged: (type) {
                    setState(() {
                      _defaultMealType = type;
                      _hasUnsavedChanges = true;
                    });
                  },
                ),
              ),

              const SizedBox(height: 12),

              // =============================================
              // PANTRY FLEXIBILITY & DIFFICULTY
              // =============================================
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      'Pantry Matching',
                      Icons.kitchen_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildSegmentedSelector(
                      options: const ['strict', 'lenient'],
                      labels: const ['Strict', 'Lenient'],
                      selected: _pantryFlexibility,
                      onSelected: (value) {
                        setState(() {
                          _pantryFlexibility = value;
                          _hasUnsavedChanges = true;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      'Recipe Difficulty',
                      Icons.speed_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildSegmentedSelector(
                      options: const ['easy', 'medium', 'hard'],
                      labels: const ['Easy', 'Medium', 'Hard'],
                      selected: _defaultDifficulty,
                      onSelected: (value) {
                        setState(() {
                          _defaultDifficulty = value;
                          _hasUnsavedChanges = true;
                        });
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // =============================================
              // ENERGY LEVEL - Master Slider
              // =============================================
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(
                    'Default Energy Level',
                    Icons.bolt_rounded,
                  ),
                  const SizedBox(height: 10),
                  MasterEnergySlider(
                    value: _defaultEnergyLevel,
                    onChanged: (v) {
                      setState(() {
                        _defaultEnergyLevel = v;
                        _hasUnsavedChanges = true;
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _savePreferences,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: AppInlineLoading(
                            size: 16,
                            baseColor: Color(0xFFEFEFEF),
                            highlightColor: Color(0xFFFFFFFF),
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(
                    _isSaving ? 'Saving...' : 'Save All Preferences',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF2D2621),
      ),
    );
  }

  Widget _buildSegmentedSelector({
    required List<String> options,
    required List<String> labels,
    required String selected,
    required void Function(String) onSelected,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(options.length, (index) {
          final isSelected = options[index] == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(options[index]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Future<void> _savePreferences() async {
    final userId = ref.read(authProvider).user?.uid;
    if (userId == null) return;

    setState(() => _isSaving = true);

    try {
      await ref.read(databaseServiceProvider).updateUserPreferences(userId, {
        'allergies': _allergies,
        'dietaryRestrictions': _dietaryRestrictions,
        'preferredCuisines': _preferredCuisines,
        'pantryFlexibility': _pantryFlexibility,
        'defaultDifficulty': _defaultDifficulty,
        'defaultMealType': _defaultMealType ?? 'dinner',
        'defaultEnergyLevel': _defaultEnergyLevel,
      });

      _hasUnsavedChanges = false;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preferences saved! 🎉'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
