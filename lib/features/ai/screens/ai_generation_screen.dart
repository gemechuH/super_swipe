import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/providers/draft_recipe_provider.dart';
import 'package:super_swipe/core/providers/firestore_providers.dart';
import 'package:super_swipe/core/providers/selected_ingredients_provider.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
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
              'Kitchen Hub',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 24,
                color: const Color(0xFF2D2621),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Introduction
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColor.withValues(alpha: 0.1),
                    AppTheme.primaryColor.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Text('👨‍🍳', style: TextStyle(fontSize: 32)),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'What are we cooking today? Tell me what you\'re craving!',
                      style: TextStyle(fontSize: 16, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Meal Type Selector
            MealTypeSelector(
              label: 'Meal Type',
              selectedMealType: _selectedMealType,
              onChanged: (type) => setState(() => _selectedMealType = type),
            ),

            const SizedBox(height: 24),

            // Cravings Input
            _buildSectionTitle('Your Cravings', Icons.lightbulb_outline),
            const SizedBox(height: 12),
            TextField(
              controller: _cravingsController,
              decoration: InputDecoration(
                hintText: 'Something warm and comforting...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(20),
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 32),

            // Energy Level Slider (using MasterEnergySlider)
            _buildSectionTitle('Cooking Energy', Icons.bolt_rounded),
            const SizedBox(height: 12),
            MasterEnergySlider(
              value: _energyLevel,
              onChanged: (v) => setState(() => _energyLevel = v),
            ),

            const SizedBox(height: 24),

            // Calorie Toggle
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SwitchListTile(
                title: const Text(
                  'Include Nutrition Info',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Show calorie count in the recipe'),
                value: _showCalories,
                onChanged: (v) => setState(() => _showCalories = v),
                activeThumbColor: AppTheme.primaryColor,
              ),
            ),

            const SizedBox(height: 24),

            // Pantry Preview
            _buildPantryPreview(),

            const SizedBox(height: 32),

            // Generate Button with disabled state when no items selected
            Builder(
              builder: (context) {
                final selectedItems = ref.watch(selectedIngredientsProvider);
                return Tooltip(
                  message: selectedItems.isEmpty
                      ? 'Please select at least one ingredient'
                      : '',
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isGenerating || _isRefining || selectedItems.isEmpty
                          ? null
                          : _showPreFlightDialog,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: AppInlineLoading(
                                size: 24,
                                baseColor: Color(0xFFEFEFEF),
                                highlightColor: Color(0xFFFFFFFF),
                              ),
                            )
                          : const Icon(Icons.restaurant, size: 28),
                      label: Text(
                        _isGenerating
                            ? 'Chef is thinking...'
                            : selectedItems.isEmpty
                            ? 'Select Ingredients First'
                            : 'Create Recipe',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedItems.isEmpty
                            ? Colors.grey.shade400
                            : AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // Error Message
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // DRAFT Recipe Card (persists across navigation)
            Builder(
              builder: (context) {
                final draft = ref.watch(draftRecipeProvider);
                if (draft == null) return const SizedBox.shrink();
                return Column(
                  children: [
                    const SizedBox(height: 32),
                    _buildDraftRecipeCard(draft.recipe),
                  ],
                );
              },
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.dmSerifDisplay(
            fontSize: 20,
            color: const Color(0xFF2D2621),
          ),
        ),
      ],
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

    return Column(
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
        const SizedBox(height: 8),
        Text(
          '${selectedItems.length} of ${itemNames.length} selected',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        if (itemNames.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Add items to your pantry for personalized recipes!',
              style: TextStyle(color: Colors.orange),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: itemNames.map((name) {
              final isSelected = selectedItems.contains(name);
              return FilterChip(
                label: Text(name),
                selected: isSelected,
                onSelected: (selected) {
                  final success = selectedNotifier.toggleIngredient(name);
                  if (!success) {
                    // Tried to deselect last item - denied
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
    );
  }

  Widget _buildDraftRecipeCard(Recipe recipe) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Draft Badge
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber.shade700, Colors.amber.shade600],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.edit_note, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Text(
                  'Recipe Draft',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  recipe.title,
                  style: GoogleFonts.dmSerifDisplay(
                    fontSize: 24,
                    color: const Color(0xFF2D2621),
                  ),
                ),
                const SizedBox(height: 8),

                // Description
                Text(
                  recipe.description,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                // Meta info
                Row(
                  children: [
                    _buildMetaChip(
                      Icons.access_time,
                      '${recipe.timeMinutes} min',
                    ),
                    const SizedBox(width: 12),
                    if (_showCalories)
                      _buildMetaChip(
                        Icons.local_fire_department,
                        '${recipe.calories} cal',
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // Ingredients
                const Text(
                  'Ingredients',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...recipe.ingredients.map(
                  (ing) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Expanded(child: Text(ing)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Instructions
                const Text(
                  'Cooking Steps',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...recipe.instructions.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${entry.key + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: Text(entry.value)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // REFINE Section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tune, color: AppTheme.primaryColor),
                          SizedBox(width: 8),
                          Text(
                            'Not quite right? Let\'s refine it!',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _refineController,
                        decoration: InputDecoration(
                          hintText:
                              'e.g., Make it spicier, I don\'t have onions...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          // DISABLED when refining OR when input is empty
                          onPressed: _isRefining || _refineText.trim().isEmpty
                              ? null
                              : _refineRecipe,
                          icon: _isRefining
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: AppInlineLoading(size: 16),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(
                            _isRefining
                                ? 'Perfecting...'
                                : _refineText.trim().isEmpty
                                ? 'Enter refinement to continue'
                                : 'Refine Recipe',
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(14),
                            side: BorderSide(
                              color: _refineText.trim().isEmpty
                                  ? Colors.grey.shade400
                                  : AppTheme.primaryColor,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // SAVE Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveToMyCookbook,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: AppInlineLoading(
                              size: 20,
                              baseColor: Color(0xFFEFEFEF),
                              highlightColor: Color(0xFFFFFFFF),
                            ),
                          )
                        : const Icon(Icons.bookmark_add),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Save to My Cookbook',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
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
                fontSize: 22,
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
              _buildSummaryRow('Energy Level', _getEnergyLabel(_energyLevel)),
              if (_cravingsController.text.trim().isNotEmpty)
                _buildSummaryRow('Cravings', _cravingsController.text.trim()),
              const SizedBox(height: 16),
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
            onPressed: () {
              Navigator.pop(dialogContext);
              _generateRecipe();
            },
            icon: const Icon(Icons.restaurant),
            label: const Text('Continue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
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

  String _getEnergyLabel(int level) {
    switch (level) {
      case 0:
        return 'Zero (Ready-made)';
      case 1:
        return 'Low (Quick & Easy)';
      case 2:
        return 'Medium (Some Effort)';
      case 3:
        return 'High (Full Cooking)';
      default:
        return 'Medium';
    }
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
                  context.go('/login');
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

    setState(() => _isSaving = true);

    try {
      // Save using DatabaseService
      final db = ref.read(databaseServiceProvider);
      await db.saveAiGeneratedRecipe(userId, currentDraft.recipe);

      // Auto-deplete used pantry ingredients
      await _depleteUsedIngredients(userId, currentDraft.recipe.ingredients);

      // Clear draft after successful save
      ref.read(draftRecipeProvider.notifier).clearDraft();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Recipe saved! Pantry updated.'),
            backgroundColor: AppTheme.successColor,
          ),
        );

        // Navigate back or to recipes
        context.pop();
      }
    } catch (e) {
      setState(
        () => _errorMessage = 'Failed to save recipe. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Delete pantry items that were used in the recipe
  Future<void> _depleteUsedIngredients(
    String userId,
    List<String> recipeIngredients,
  ) async {
    final pantryItems = ref.read(pantryItemsProvider).value ?? [];
    final pantryService = ref.read(pantryServiceProvider);

    for (final pantryItem in pantryItems) {
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
