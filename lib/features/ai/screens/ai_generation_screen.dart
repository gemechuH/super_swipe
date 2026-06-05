import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/config/swipe_constants.dart';
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/providers/draft_recipe_provider.dart';
import 'package:super_swipe/core/providers/firestore_providers.dart';
import 'package:super_swipe/core/providers/selected_ingredients_provider.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/core/widgets/loading/app_shimmer.dart';
import 'package:super_swipe/core/widgets/loading/skeleton.dart';
import 'package:super_swipe/core/widgets/shared/shared_widgets.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/services/ai/ai_recipe_service.dart';
import 'package:super_swipe/services/database/database_provider.dart';
import 'package:super_swipe/services/image/image_search_service.dart';

class AiGenerationScreen extends ConsumerStatefulWidget {
  const AiGenerationScreen({super.key});

  @override
  ConsumerState<AiGenerationScreen> createState() => _AiGenerationScreenState();
}

class _AiGenerationScreenState extends ConsumerState<AiGenerationScreen> {
  final TextEditingController _cravingsController = TextEditingController();
  final TextEditingController _refineController = TextEditingController();

  String? _selectedMealType;
  int _energyLevel = 2;
  bool _showCalories = true;
  bool _isGenerating = false;
  bool _isRefining = false;
  bool _isSaving = false;
  int _completedSteps = 0; // tracks how many steps user has clicked through

  // Draft recipe now stored in DraftRecipeNotifier for navigation persistence
  // Use ref.watch(draftRecipeProvider) to get current draft
  String? _errorMessage;

  // Track refinement text for button enable/disable
  String _refineText = '';

  // Rate limiting: max 5 generations per minute
  final List<DateTime> _generationTimestamps = [];
  static const int _maxGenerationsPerMinute = 5;

  // Refinement limit: max 2 refinements per draft (tracked in DraftRecipeNotifier)
  static const int _maxRefinements = 2;

  // Image service
  final ImageSearchService _imageService = ImageSearchService();

  // Selected pantry items are now managed by selectedIngredientsProvider for persistence

  @override
  void initState() {
    super.initState();
    // Load default meal type from user settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProfile = ref.read(userProfileProvider).value;
      if (userProfile != null && _selectedMealType == null) {
        setState(() {
          _selectedMealType = userProfile.preferences.defaultMealType.isNotEmpty
              ? userProfile.preferences.defaultMealType
              : 'dinner';
        });
      }
    });

    // Listen to refine controller for button enable/disable
    _refineController.addListener(() {
      if (_refineText != _refineController.text) {
        setState(() => _refineText = _refineController.text);
      }
    });
  }

  @override
  void dispose() {
    _cravingsController.dispose();
    _refineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text(
              'AI Chef',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: AppTheme.primaryColor),
            tooltip: 'Recipe History',
            onPressed: () => _showRecipeHistory(context),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                MediaQuery.of(context).padding.bottom + 20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Introduction - compact
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryColor.withValues(alpha: 0.1),
                            AppTheme.primaryColor.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Text('👨‍🍳', style: TextStyle(fontSize: 22)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Create a recipe from your pantry.',
                              style: TextStyle(fontSize: 12, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: constraints.maxHeight * 0.018),

                    // Meal Type Selector
                    MealTypeSelector(
                      label: 'Meal Type',
                      selectedMealType: _selectedMealType,
                      onChanged: (type) =>
                          setState(() => _selectedMealType = type),
                    ),

                    SizedBox(height: constraints.maxHeight * 0.018),

                    // Energy Level Slider
                    _buildSectionTitle('Cooking Energy', Icons.bolt_rounded),
                    const SizedBox(height: 6),
                    MasterEnergySlider(
                      value: _energyLevel,
                      onChanged: (v) => setState(() => _energyLevel = v),
                    ),

                    SizedBox(height: constraints.maxHeight * 0.015),

                    // Calorie Toggle - compact
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Include Nutrition Info',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Show calorie count in the recipe',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Transform.scale(
                            scale: 0.85,
                            child: Switch(
                              value: _showCalories,
                              onChanged: (v) =>
                                  setState(() => _showCalories = v),
                              activeThumbColor: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: constraints.maxHeight * 0.015),

                    // Pantry Preview
                    _buildPantryPreview(),

                    SizedBox(height: constraints.maxHeight * 0.02),

                    if (_errorMessage != null) _buildErrorBanner(),

                    // DRAFT Recipe Card
                    Builder(
                      builder: (context) {
                        final draft = ref.watch(draftRecipeProvider);
                        if (draft == null) return const SizedBox.shrink();
                        return Column(
                          children: [
                            const SizedBox(height: 16),
                            _buildDraftRecipeCard(draft.recipe),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: ref.watch(draftRecipeProvider) == null
          ? _buildPromptComposer()
          : null,
    );
  }

  Widget _buildSectionTitle(String title, [IconData? icon]) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF2D2621),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[700], size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red[700], fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptComposer() {
    final selectedItems = ref.watch(selectedIngredientsProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final disabled = _isGenerating || _isRefining || selectedItems.isEmpty;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 50),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBF5),
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: disabled
                    ? Colors.grey.shade200
                    : AppTheme.primaryColor.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _cravingsController,
                    enabled: !_isGenerating && !_isRefining,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(fontSize: 14, height: 1.35),
                    decoration: InputDecoration(
                      hintText: selectedItems.isEmpty
                          ? 'Add pantry items first'
                          : 'Ask for spicy pasta, quick lunch, cozy soup...',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 42,
                  height: 42,
                  child: IconButton(
                    onPressed: disabled ? null : _showPreFlightDialog,
                    tooltip: 'Create Recipe',
                    style: IconButton.styleFrom(
                      backgroundColor: disabled
                          ? Colors.grey.shade200
                          : AppTheme.primaryColor,
                      foregroundColor: disabled
                          ? Colors.grey.shade500
                          : Colors.white,
                    ),
                    icon: _isGenerating
                        ? const AppInlineLoading(
                            size: 18,
                            baseColor: Color(0xFFEFEFEF),
                            highlightColor: Color(0xFFFFFFFF),
                          )
                        : const Icon(Icons.arrow_upward_rounded, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPantryPreview() {
    final pantryItems = ref.watch(pantryItemsProvider).value ?? [];
    final itemNames = pantryItems.map((i) => i.name).toList();
    final selectedItems = ref.watch(selectedIngredientsProvider);
    final selectedNotifier = ref.read(selectedIngredientsProvider.notifier);

    // Initialize/sync selected items with current pantry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        selectedNotifier.syncWithPantry(itemNames);
      }
    });

    final allSelected = selectedNotifier.isAllSelected(itemNames);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSectionTitle('Your Pantry', Icons.kitchen_rounded),
              ),
              if (itemNames.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    if (allSelected) {
                      // Deselect all except one (keep first)
                      selectedNotifier.deselectAllExceptOne(itemNames);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'At least one ingredient must be selected',
                          ),
                          duration: Duration(seconds: 2),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    } else {
                      selectedNotifier.selectAll(itemNames);
                    }
                  },
                  icon: Icon(
                    allSelected ? Icons.deselect : Icons.select_all,
                    size: 18,
                    color: AppTheme.primaryColor,
                  ),
                  label: Text(
                    allSelected ? 'Deselect All' : 'Select All',
                    style: const TextStyle(color: AppTheme.primaryColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${selectedItems.length} of ${itemNames.length} selected',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 8),
          if (itemNames.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3DF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.orange,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'At least 1 pantry ingredient is required.',
                          style: TextStyle(
                            color: Color(0xFF9A650F),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: () => context.go(AppRoutes.pantry),
                      icon: const Icon(Icons.kitchen_rounded, size: 15),
                      label: const Text('Go to Pantry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: itemNames.map((name) {
                final isSelected = selectedItems.contains(name);
                return FilterChip(
                  label: Text(name, style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(
                    horizontal: 0,
                    vertical: -2,
                  ),
                  onSelected: (selected) {
                    final success = selectedNotifier.toggleIngredient(name);
                    if (!success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'At least one ingredient must be selected',
                          ),
                          duration: Duration(seconds: 2),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                  checkmarkColor: AppTheme.primaryColor,
                  backgroundColor: Colors.white,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildDraftRecipeCard(Recipe recipe) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — compact
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade600,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.edit_note, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  'Recipe Draft',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  recipe.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D2621),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),

                // Description — max 2 lines
                Text(
                  recipe.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),

                // Meta info
                Row(
                  children: [
                    _buildMetaChip(
                      Icons.access_time,
                      '${recipe.timeMinutes} min',
                    ),
                    const SizedBox(width: 8),
                    if (_showCalories)
                      _buildMetaChip(
                        Icons.local_fire_department,
                        '${recipe.calories} cal',
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // Ingredients
                const Text(
                  'Ingredients',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...recipe.ingredients.map(
                  (ing) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Text(
                            ing,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Instructions — step by step reveal
                const Text(
                  'Cooking Steps',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...recipe.instructions.asMap().entries.map((entry) {
                  final stepIndex = entry.key;
                  final stepText = entry.value;
                  final isVisible = stepIndex <= _completedSteps;
                  final isCompleted = stepIndex < _completedSteps;
                  final isCurrent = stepIndex == _completedSteps;

                  if (!isVisible) return const SizedBox.shrink();

                  return GestureDetector(
                    onTap: isCurrent
                        ? () => setState(() => _completedSteps++)
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? Colors.green.shade50
                            : isCurrent
                            ? AppTheme.primaryColor.withValues(alpha: 0.06)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCompleted
                              ? Colors.green.shade200
                              : isCurrent
                              ? AppTheme.primaryColor.withValues(alpha: 0.3)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            margin: const EdgeInsets.only(right: 8, top: 1),
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? Colors.green
                                  : isCurrent
                                  ? AppTheme.primaryColor
                                  : Colors.grey.shade400,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: isCompleted
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 12,
                                    )
                                  : Text(
                                      '${stepIndex + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stepText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: isCompleted
                                        ? Colors.grey.shade600
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                if (isCurrent) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Tap to mark done ✓',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 12),

                // REFINE Section
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.tune,
                            color: AppTheme.primaryColor,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Not quite right? Let\'s refine it!',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _refineController,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText:
                              'e.g., Make it spicier, I don\'t have onions...',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: OutlinedButton.icon(
                          onPressed: _isRefining || _refineText.trim().isEmpty
                              ? null
                              : _refineRecipe,
                          icon: _isRefining
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: AppInlineLoading(size: 14),
                                )
                              : const Icon(Icons.refresh, size: 14),
                          label: Text(
                            _isRefining
                                ? 'Perfecting...'
                                : _refineText.trim().isEmpty
                                ? 'Enter refinement to continue'
                                : 'Refine Recipe',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            side: BorderSide(
                              color: _refineText.trim().isEmpty
                                  ? Colors.grey.shade400
                                  : AppTheme.primaryColor,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // SAVE Button — only active when all steps completed
                Builder(
                  builder: (context) {
                    final totalSteps = recipe.instructions.length;
                    final allDone = _completedSteps >= totalSteps;
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_isSaving || !allDone)
                            ? null
                            : _saveToMyCookbook,
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
                            : Icon(
                                allDone
                                    ? Icons.bookmark_add
                                    : Icons.lock_outline_rounded,
                                size: 16,
                              ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _isSaving
                                ? 'Saving...'
                                : allDone
                                ? 'Save to My Cookbook'
                                : 'Complete steps ($_completedSteps/$totalSteps)',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: allDone
                              ? AppTheme.primaryColor
                              : Colors.grey.shade300,
                          foregroundColor: allDone
                              ? Colors.white
                              : Colors.grey.shade600,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  /// Pre-flight confirmation dialog before generating recipe
  void _showPreFlightDialog() {
    final selectedItems = ref.read(selectedIngredientsProvider);
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select at least one ingredient for the Chef to work with!',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Check carrot balance before showing dialog
    final profile = ref.read(userProfileProvider).value;
    final subscription = profile?.subscriptionStatus.toLowerCase() ?? 'free';
    final isPremium = subscription == 'premium';
    final currentCarrots = profile?.carrots.current ?? 0;
    final maxCarrots = profile?.carrots.max ?? 5;

    if (!isPremium && currentCarrots < 1) {
      // Out of carrots — show upgrade dialog
      _showOutOfCarrotsDialog(currentCarrots, maxCarrots);
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text(
              'Ready to Cook?',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 18,
                color: const Color(0xFF2D2621),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _buildSummaryRow(
                'Ingredients',
                '${selectedItems.length} selected',
              ),
              _buildSummaryRow('Meal Type', _selectedMealType ?? 'Any'),
              _buildSummaryRow(
                'Energy Level',
                EnergyLevel.fromInt(_energyLevel).summaryLabel,
              ),
              if (_cravingsController.text.trim().isNotEmpty)
                _buildSummaryRow('Cravings', _cravingsController.text.trim()),
              // Show carrot cost for free users
              if (!isPremium) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Text('🥕', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        'Costs 1 carrot  ($currentCarrots/$maxCarrots remaining)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: selectedItems
                    .take(10)
                    .map(
                      (name) => Chip(
                        label: Text(name, style: const TextStyle(fontSize: 12)),
                        backgroundColor: AppTheme.primaryColor.withValues(
                          alpha: 0.1,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
              if (selectedItems.length > 10)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '+${selectedItems.length - 10} more',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Deduct carrot before generating
              final userId = ref.read(authProvider).user?.uid;
              if (userId != null && !isPremium) {
                final success = await ref
                    .read(databaseServiceProvider)
                    .deductCarrot(userId);
                if (!success) {
                  if (mounted) {
                    _showOutOfCarrotsDialog(currentCarrots, maxCarrots);
                  }
                  return;
                }
              }
              _generateRecipe();
            },
            icon: const Icon(Icons.restaurant),
            label: Text(isPremium ? 'Continue' : 'Use 1 🥕 & Generate'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showOutOfCarrotsDialog(int current, int max) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🥕', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              const Text(
                'Weekly limit reached',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'You\'ve used all $max weekly carrots. Come back next week or upgrade for unlimited recipes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Premium plan coming soon! 🚀'),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Upgrade for Unlimited',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Come back later',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateRecipe() async {
    // Rate limiting check: max 5 per minute
    final now = DateTime.now();
    _generationTimestamps.removeWhere(
      (ts) => now.difference(ts).inMinutes >= 1,
    );

    if (_generationTimestamps.length >= _maxGenerationsPerMinute) {
      setState(() {
        _errorMessage =
            'Slow down! You can generate up to $_maxGenerationsPerMinute recipes per minute.';
      });
      return;
    }

    // Validation: need at least 1 selected ingredient
    final selectedItems = ref.read(selectedIngredientsProvider);
    if (selectedItems.isEmpty) {
      setState(() {
        _errorMessage = 'Please select at least one ingredient.';
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      ref.read(draftRecipeProvider.notifier).clearDraft();
      // Refinement counter is tracked in DraftRecipeNotifier
    });

    try {
      final userProfile = ref.read(userProfileProvider).value;
      final strictMatch =
          userProfile?.preferences.pantryFlexibility == 'strict';

      final messenger = ScaffoldMessenger.of(context);
      final aiService = AiRecipeService(
        onStatus: (message) {
          if (!mounted) return;
          messenger.removeCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
      var recipe = await aiService.generateRecipe(
        pantryItems: selectedItems.toList(),
        allergies: userProfile?.preferences.allergies ?? [],
        dietaryRestrictions: userProfile?.preferences.dietaryRestrictions ?? [],
        cravings: _cravingsController.text.trim(),
        energyLevel: _energyLevel,
        showCalories: _showCalories,
        preferredCuisines: userProfile?.preferences.preferredCuisines ?? [],
        mealType: _selectedMealType ?? 'dinner',
        strictPantryMatch: strictMatch,
      );

      // Fetch matching image from Unsplash
      final imageResult = await _imageService.searchRecipeImage(
        recipeTitle: recipe.title,
        ingredients: recipe.ingredients.take(3).toList(),
      );

      // Update recipe with fetched image if available
      if (imageResult != null) {
        recipe = recipe.copyWith(imageUrl: imageResult.imageUrl);
      }

      // Record this generation timestamp for rate limiting
      _generationTimestamps.add(now);

      // Store draft in provider for navigation persistence
      ref
          .read(draftRecipeProvider.notifier)
          .setDraft(recipe, imageResult: imageResult);

      _cravingsController.clear();

      // Reset step tracker for new recipe
      setState(() => _completedSteps = 0);

      // Toast message after generation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '🍽️ Recipe ready! Scroll down to view it. Enjoy!',
            ),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      setState(() {}); // Trigger rebuild
    } catch (e) {
      debugPrint('Recipe generation error: $e');
      setState(() {
        // Show clean error message to user
        final message = e.toString().replaceAll('Exception:', '').trim();
        _errorMessage = message.isNotEmpty
            ? message
            : 'Oops! Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _refineRecipe() async {
    final currentDraft = ref.read(draftRecipeProvider);

    // Input validation: require refinement text
    if (_refineController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please describe what you\'d like to change."';
      });
      return;
    }

    if (currentDraft == null) {
      setState(() {
        _errorMessage = 'No recipe to refine. Please generate a recipe first.';
      });
      return;
    }

    // Refinement limit check: max 2 refinements per draft
    if (currentDraft.refinementCount >= _maxRefinements) {
      setState(() {
        _errorMessage =
            'Maximum refinements reached! You can refine up to $_maxRefinements times per recipe. Try generating a new recipe.';
      });
      return;
    }

    setState(() {
      _isRefining = true;
      _errorMessage = null;
    });

    try {
      final messenger = ScaffoldMessenger.of(context);
      final aiService = AiRecipeService(
        onStatus: (message) {
          if (!mounted) return;
          messenger.removeCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
      final currentDraft = ref.read(draftRecipeProvider)!;
      // Use the new refineRecipe method that sends original JSON to Gemini
      var refinedRecipe = await aiService.refineRecipe(
        originalRecipe: currentDraft.recipe,
        refinementText: _refineController.text.trim(),
        showCalories: _showCalories,
      );

      // IMPORTANT: Reuse existing image URL from draft - don't fetch new one!
      // This preserves Unsplash API quota and maintains attribution
      if (currentDraft.imageUrl != null &&
          currentDraft.imageUrl!.isNotEmpty &&
          !currentDraft.imageUrl!.startsWith('assets/')) {
        refinedRecipe = refinedRecipe.copyWith(imageUrl: currentDraft.imageUrl);
      }

      // Update draft with refinement (increments counter automatically)
      ref
          .read(draftRecipeProvider.notifier)
          .updateWithRefinement(refinedRecipe);
      _refineController.clear();
      setState(() {}); // Trigger rebuild
    } catch (e) {
      setState(() => _errorMessage = 'Refinement failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isRefining = false);
    }
  }

  Future<void> _saveToMyCookbook() async {
    if (_isSaving) return;
    final currentDraft = ref.read(draftRecipeProvider);
    if (currentDraft == null) return;

    final authState = ref.read(authProvider);
    if (!authState.isSignedIn || authState.user?.isAnonymous == true) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign In Required'),
            content: const Text(
              'Please sign in to save recipes to your cookbook.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go(AppRoutes.login);
                },
                child: const Text('Sign In'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final userId = authState.user!.uid;
    final recipeToSave = currentDraft.recipe;

    setState(() => _isSaving = true);

    try {
      // Save using DatabaseService
      final db = ref.read(databaseServiceProvider);
      await db.saveAiGeneratedRecipe(userId, recipeToSave);

      // Navigate immediately after the critical save.
      if (!mounted) return;
      context.push(
        '${AppRoutes.recipes}/${recipeToSave.id}',
        extra: {
          'recipe': recipeToSave,
          'assumeUnlocked': true,
          'openDirections': true,
        },
      );

      // Clear draft so returning to this screen doesn't show stale data.
      ref.read(draftRecipeProvider.notifier).clearDraft();

      // Run slower post-save tasks in the background.
      final pantryService = ref.read(pantryServiceProvider);
      final pantryItemsSnapshot =
          ref.read(pantryItemsProvider).value ?? const <PantryItem>[];
      unawaited(
        _runPostSaveTasks(
          db: db,
          pantryService: pantryService,
          pantryItemsSnapshot: pantryItemsSnapshot,
          userId: userId,
          recipe: recipeToSave,
        ),
      );
    } catch (e) {
      setState(
        () => _errorMessage = 'Failed to save recipe. Please try again.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save recipe. Please try again.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _runPostSaveTasks({
    required dynamic db,
    required dynamic pantryService,
    required List<PantryItem> pantryItemsSnapshot,
    required String userId,
    required Recipe recipe,
  }) async {
    try {
      await db.publishRecipeToGlobal(userId: userId, recipe: recipe);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Publish to global failed: $e');
      }
    }

    try {
      await _depleteUsedIngredientsSnapshot(
        pantryService: pantryService,
        pantryItemsSnapshot: pantryItemsSnapshot,
        userId: userId,
        recipeIngredients: recipe.ingredients,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Deplete pantry failed: $e');
      }
    }
  }

  /// Delete pantry items that were used in the recipe
  Future<void> _depleteUsedIngredientsSnapshot({
    required dynamic pantryService,
    required List<PantryItem> pantryItemsSnapshot,
    required String userId,
    required List<String> recipeIngredients,
  }) async {
    for (final pantryItem in pantryItemsSnapshot) {
      final pantryName = pantryItem.name.toLowerCase();

      // Check if any recipe ingredient matches this pantry item
      final isUsed = recipeIngredients.any((ingredient) {
        final ingredientLower = ingredient.toLowerCase();
        return ingredientLower.contains(pantryName) ||
            pantryName.contains(ingredientLower);
      });

      if (isUsed) {
        // Delete the pantry item entirely (Issue 2 fix)
        await pantryService.deletePantryItem(userId, pantryItem.id);
      }
    }
  }

  void _showRecipeHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.history, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text(
                    'Recipe History',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildHistoryList(scrollController)),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList(ScrollController scrollController) {
    final authState = ref.read(authProvider);
    if (!authState.isSignedIn || authState.user == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Sign in to see your recipe history',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return StreamBuilder(
      stream: ref
          .read(databaseServiceProvider)
          .getAiRecipeHistory(authState.user!.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return AppShimmer(
            baseColor: Colors.grey.shade200,
            highlightColor: Colors.grey.shade100,
            child: ListView.builder(
              controller: scrollController,
              itemCount: 8,
              itemBuilder: (context, index) => const SkeletonListTile(),
            ),
          );
        }

        if (!snapshot.hasData || (snapshot.data as List).isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.restaurant_menu, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No recipes generated yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Create your first recipe above!',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        final recipes = snapshot.data as List<Map<String, dynamic>>;
        return ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: recipes.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final recipe = recipes[index];
            return ListTile(
              contentPadding: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.restaurant,
                  color: AppTheme.primaryColor,
                ),
              ),
              title: Text(
                recipe['title'] ?? 'Untitled Recipe',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                recipe['description'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                // Could navigate to detail or load into draft
              },
            );
          },
        );
      },
    );
  }
}
