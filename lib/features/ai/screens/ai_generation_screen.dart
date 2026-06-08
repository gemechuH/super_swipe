import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/config/swipe_constants.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/providers/draft_recipe_provider.dart';
import 'package:super_swipe/core/providers/selected_ingredients_provider.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/core/widgets/loading/app_shimmer.dart';
import 'package:super_swipe/core/widgets/loading/skeleton.dart';
import 'package:super_swipe/core/widgets/shared/shared_widgets.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/core/providers/recipe_providers.dart';
import 'package:super_swipe/services/ai/ai_recipe_service.dart';
import 'package:super_swipe/services/database/database_provider.dart';
import 'package:super_swipe/services/image/image_search_service.dart';
import 'package:super_swipe/core/providers/firestore_providers.dart';

class AiGenerationScreen extends ConsumerStatefulWidget {
  const AiGenerationScreen({super.key});

  @override
  ConsumerState<AiGenerationScreen> createState() => _AiGenerationScreenState();
}

class _AiGenerationScreenState extends ConsumerState<AiGenerationScreen> {
  final TextEditingController _cravingsController = TextEditingController();
  final TextEditingController _refineController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _selectedMealType;
  int _energyLevel = 2;
  bool _showCalories = true;
  bool _isGenerating = false;
  bool _isRefining = false;
  bool _isSaving = false;
  bool _settingsExpanded = false; // controls collapse when draft is shown
  final Set<int> _checkedSteps = {}; // tracks which steps are marked done

  // Loading message cycling during generation
  String _loadingMessage = 'Checking your pantry...';
  Timer? _loadingMessageTimer;
  static const List<String> _loadingMessages = [
    'Checking your pantry...',
    'Consulting the Michelin guide...',
    'Crafting your recipe...',
    'Balancing the flavours...',
    'Adding the finishing touches...',
    'Almost ready to plate...',
  ];

  // Draft recipe now stored in DraftRecipeNotifier for navigation persistence
  // Use ref.watch(draftRecipeProvider) to get current draft
  String? _errorMessage;

  // Track refinement text for button enable/disable
  String _refineText = '';
  String? _selectedQuickRefine; // tracks selected quick-refine chip

  // Quick refine options with their AI prompts
  static const Map<String, String> _quickRefineOptions = {
    '🌶️ Spicier':
        'Make this recipe significantly spicier. Add more chilli, hot sauce, cayenne, or other heat sources with specific amounts. Mention the heat level in the description.',
    '🥗 Healthier':
        'Make this recipe healthier. Reduce saturated fat, use leaner proteins, add more vegetables, reduce sugar and sodium, and use whole grain alternatives where possible. Keep it delicious.',
    '⚡ Easier':
        'Simplify this recipe for a beginner cook. Reduce steps, use simpler techniques, cut prep time, and reduce the number of ingredients while keeping the core flavour.',
    '✨ Fancier':
        'Elevate this recipe to restaurant quality. Add a sophisticated garnish, use a more refined technique, incorporate a luxurious ingredient, and improve the plating description.',
    '👶 Kid-friendly':
        'Adapt this recipe to be more appealing to children. Remove strong or very spicy flavours, simplify the presentation, and use familiar ingredients. Ensure it remains nutritious.',
    '💪 More Protein':
        'Increase the protein content of this recipe. Suggest adding or substituting higher protein ingredients like eggs, Greek yoghurt, beans, lean meats, or tofu without drastically changing the core dish.',
  };

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
    _scrollController.dispose();
    _loadingMessageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftRecipeProvider);
    final hasDraft = draft != null;

    return PopScope(
      canPop: !hasDraft,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (hasDraft) {
          ref.read(draftRecipeProvider.notifier).clearDraft();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFFFFFBF5),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () {
              if (hasDraft) {
                ref.read(draftRecipeProvider.notifier).clearDraft();
              } else {
                if (Navigator.of(context).canPop()) {
                  context.pop();
                }
              }
            },
          ),
          title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text(
              'My Chef',
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
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    MediaQuery.of(context).padding.bottom +
                        100, // clear FAB + nav bar
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── SETTINGS SECTION ──────────────────────────────────
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) =>
                              SizeTransition(sizeFactor: animation, child: child),
                          child: hasDraft
                              // Collapsed: show a compact summary chip
                              ? _buildSettingsSummaryChip(
                                  key: const ValueKey('collapsed'),
                                )
                              // Expanded: show all settings
                              : _buildSettingsFull(
                                  key: const ValueKey('expanded'),
                                  constraints: constraints,
                                ),
                        ),

                        if (_errorMessage != null) _buildErrorBanner(),

                        // ── DRAFT CARD ────────────────────────────────────────
                        if (hasDraft) ...[
                          const SizedBox(height: 12),
                          _buildDraftRecipeCard(draft.recipe),
                        ],

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // ── LOADING OVERLAY (while generating) ──
          if (_isGenerating)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.4),
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Material(
                    color: Colors.transparent,
                    child: _buildGeneratingCard(),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: null,
    ),
    );
  }

  // ── GENERATING CARD — shown while AI is working ───────────────────────────
  Widget _buildGeneratingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated chef icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('👨‍🍳', style: TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(height: 16),
          // Pulsing dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) => _PulsingDot(delayMs: i * 200)),
          ),
          const SizedBox(height: 14),
          // Cycling status message
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              _loadingMessage,
              key: ValueKey(_loadingMessage),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D2621),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your recipe is being crafted...',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── SETTINGS: collapsed summary chip shown when a draft exists ────────────
  Widget _buildSettingsSummaryChip({Key? key}) {
    final selectedItems = ref.watch(selectedIngredientsProvider);
    final mealLabel = _selectedMealType ?? 'Any';
    final energyLabel = EnergyLevel.fromInt(_energyLevel).summaryLabel;

    return GestureDetector(
      key: key,
      onTap: () => setState(() => _settingsExpanded = !_settingsExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _settingsExpanded
                ? AppTheme.primaryColor.withValues(alpha: 0.4)
                : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary row — always visible
            Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 15,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$mealLabel  •  $energyLabel  •  ${selectedItems.length} ingredients',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D2621),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  _settingsExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
            // Expandable full settings
            if (_settingsExpanded) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              MealTypeSelector(
                label: 'Meal Type',
                selectedMealType: _selectedMealType,
                onChanged: (type) => setState(() => _selectedMealType = type),
              ),
              const SizedBox(height: 12),
              _buildSectionTitle('Cooking Energy', Icons.bolt_rounded),
              const SizedBox(height: 6),
              MasterEnergySlider(
                value: _energyLevel,
                onChanged: (v) => setState(() => _energyLevel = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Include Nutrition Info',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
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
                    scale: 0.8,
                    child: Switch(
                      value: _showCalories,
                      onChanged: (v) => setState(() => _showCalories = v),
                      activeThumbColor: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildPantryPreview(),
            ],
          ],
        ),
      ),
    );
  }

  // ── SETTINGS: full expanded view shown when no draft exists ───────────────
  Widget _buildSettingsFull({Key? key, required BoxConstraints constraints}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Introduction
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

        MealTypeSelector(
          label: 'Meal Type',
          selectedMealType: _selectedMealType,
          onChanged: (type) => setState(() => _selectedMealType = type),
        ),

        SizedBox(height: constraints.maxHeight * 0.018),

        _buildSectionTitle('Cooking Energy', Icons.bolt_rounded),
        const SizedBox(height: 6),
        MasterEnergySlider(
          value: _energyLevel,
          onChanged: (v) => setState(() => _energyLevel = v),
        ),

        SizedBox(height: constraints.maxHeight * 0.015),

        // Calorie Toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  onChanged: (v) => setState(() => _showCalories = v),
                  activeThumbColor: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: constraints.maxHeight * 0.015),

        _buildPantryPreview(),

        SizedBox(height: constraints.maxHeight * 0.02),

        // Optional cravings text field
        _buildInlineCravingsInput(),

        SizedBox(height: constraints.maxHeight * 0.015),

        // Generate button — always visible, enabled when pantry has items
        _buildGenerateButton(),

        SizedBox(height: constraints.maxHeight * 0.02),
      ],
    );
  }

  // ── Optional cravings input ───────────────────────────────────────────────
  Widget _buildInlineCravingsInput() {
    final selectedItems = ref.watch(selectedIngredientsProvider);
    final disabled = _isGenerating || selectedItems.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Any cravings?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D2621),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Optional',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: disabled
                  ? Colors.grey.shade200
                  : AppTheme.primaryColor.withValues(alpha: 0.2),
            ),
          ),
          child: TextField(
            controller: _cravingsController,
            enabled: !disabled,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 13, height: 1.4),
            decoration: InputDecoration(
              hintText: 'e.g. spicy, quick lunch, cozy soup...',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Fixed generate button ─────────────────────────────────────────────────
  Widget _buildGenerateButton() {
    final selectedItems = ref.watch(selectedIngredientsProvider);
    final disabled = _isGenerating || selectedItems.isEmpty;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: disabled ? null : _showPreFlightDialog,
        style: ElevatedButton.styleFrom(
          backgroundColor: disabled
              ? Colors.grey.shade300
              : AppTheme.primaryColor,
          foregroundColor: disabled ? Colors.grey.shade500 : Colors.white,
          elevation: disabled ? 0 : 3,
          shadowColor: AppTheme.primaryColor.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isGenerating)
              const AppInlineLoading(
                size: 18,
                baseColor: Color(0xFFEFEFEF),
                highlightColor: Color(0xFFFFFFFF),
              )
            else
              const Icon(Icons.auto_awesome_rounded, size: 20),
            const SizedBox(width: 10),
            Text(
              disabled && !_isGenerating
                  ? 'Add pantry items to generate'
                  : _isGenerating
                  ? 'Generating...'
                  : 'Generate Recipe',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
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
              color: Colors.green.shade600,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_note, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                const Text(
                  'Recipe Draft',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // Regenerate button — solid orange, clearly visible
                TextButton.icon(
                  onPressed: _isGenerating ? null : _regenerateRecipe,
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text(
                    'Regenerate',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
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
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D2621),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),

                // Description — fully visible
                Text(
                  recipe.description,
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

                // Instructions — all steps visible, each individually checkable
                const Text(
                  'Cooking Steps',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ...recipe.instructions.asMap().entries.map((entry) {
                  final stepIndex = entry.key;
                  final stepText = entry.value;
                  final isDone = _checkedSteps.contains(stepIndex);

                  return GestureDetector(
                    onTap: () => setState(() {
                      if (isDone) {
                        _checkedSteps.remove(stepIndex);
                      } else {
                        _checkedSteps.add(stepIndex);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: isDone
                            ? Colors.green.shade50
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDone
                              ? Colors.green.shade300
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Step number badge
                          Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(right: 10, top: 1),
                            decoration: BoxDecoration(
                              color: isDone
                                  ? Colors.green
                                  : AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: isDone
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 13,
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
                          // Step text
                          Expanded(
                            child: Text(
                              stepText,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: isDone
                                    ? Colors.grey.shade500
                                    : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          // Checkbox on the right
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: isDone ? Colors.green : Colors.white,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: isDone
                                      ? Colors.green
                                      : Colors.grey.shade400,
                                  width: 1.5,
                                ),
                              ),
                              child: isDone
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 13,
                                    )
                                  : null,
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
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4FA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFD0E8F5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      const Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            color: AppTheme.primaryColor,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Not quite right? Refine it!',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Color(0xFF2D2621),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Quick-select chips
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.4, // controls the height of the buttons
                        children: _quickRefineOptions.keys.map((label) {
                          final isSelected = _selectedQuickRefine == label;
                          return GestureDetector(
                            onTap: _isRefining
                                ? null
                                : () => setState(() {
                                    _selectedQuickRefine = isSelected
                                        ? null
                                        : label;
                                  }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primaryColor
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.primaryColor
                                      : Colors.grey.shade300,
                                ),
                                boxShadow: isSelected
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.03),
                                          blurRadius: 3,
                                          offset: const Offset(0, 1),
                                        )
                                      ],
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF4A4A4A),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 14),

                      // Custom text field
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: TextField(
                          controller: _refineController,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Add more detail (optional)...',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                            ),
                            filled: false,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Refine button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed:
                              (_isRefining ||
                                      (_selectedQuickRefine == null &&
                                          _refineText.trim().isEmpty))
                                  ? null
                                  : _refineRecipe,
                          icon: _isRefining
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: AppInlineLoading(
                                    size: 18,
                                    baseColor: Color(0xFFEFEFEF),
                                    highlightColor: Color(0xFFFFFFFF),
                                  ),
                                )
                              : const Icon(
                                  Icons.auto_fix_high_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            _isRefining
                                ? 'Refining...'
                                : _selectedQuickRefine != null
                                    ? 'Refine: $_selectedQuickRefine'
                                    : 'Refine Recipe',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (_selectedQuickRefine != null ||
                                    _refineText.trim().isNotEmpty)
                                ? AppTheme.primaryColor
                                : Colors.grey.shade300,
                            foregroundColor: (_selectedQuickRefine != null ||
                                    _refineText.trim().isNotEmpty)
                                ? Colors.white
                                : Colors.grey.shade500,
                            elevation: (_selectedQuickRefine != null ||
                                    _refineText.trim().isNotEmpty)
                                ? 2
                                : 0,
                            shadowColor:
                                AppTheme.primaryColor.withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
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
                    final allDone = _checkedSteps.length >= totalSteps;
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
                                : 'Complete steps (${_checkedSteps.length}/$totalSteps)',
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
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textSecondary),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
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
      _showOutOfCarrotsDialog();
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
              _generateRecipe();
            },
            icon: const Icon(Icons.restaurant, size: 16),
            label: Text(
              isPremium ? 'Continue' : 'Use 1 🥕 & Generate',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  void _showOutOfCarrotsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Text('🥕', style: TextStyle(fontSize: 24)),
            SizedBox(width: 8),
            Text('Out of Carrots!'),
          ],
        ),
        content: const Text(
            'You have run out of carrots. Please visit the store to get more or upgrade to Chef Pro for unlimited generation!'),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              context.pop();
              context.push(AppRoutes.store);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Visit Store', style: TextStyle(color: Colors.white)),
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

  /// Regenerate: clear current draft and generate a fresh recipe with same settings
  void _regenerateRecipe() {
    ref.read(draftRecipeProvider.notifier).clearDraft();
    _checkedSteps.clear();
    _refineController.clear();
    setState(() => _selectedQuickRefine = null);
    _generateRecipe();
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

    // Check & deduct carrots
    final uid = ref.read(authProvider).user?.uid;
    final userProfile = ref.read(userProfileProvider).value;
    final isPremium = userProfile?.subscriptionStatus == 'premium';

    if (uid != null && !isPremium) {
      // spendCarrots returns true if successful, false if insufficient balance
      final success = await ref.read(userServiceProvider).spendCarrots(uid, 1);
      if (!success) {
        _showOutOfCarrotsDialog();
        return;
      }
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _loadingMessage = _loadingMessages[0];
      ref.read(draftRecipeProvider.notifier).clearDraft();
      // Refinement counter is tracked in DraftRecipeNotifier
    });

    // Dismiss keyboard immediately so the loading card is visible
    FocusScope.of(context).unfocus();

    // Scroll to top so the loading card is the first thing the user sees
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // Cycle through loading messages every 2 seconds
    var _msgIndex = 1;
    _loadingMessageTimer?.cancel();
    _loadingMessageTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() {
        _loadingMessage = _loadingMessages[_msgIndex % _loadingMessages.length];
        _msgIndex++;
      });
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
      // Collapse settings and scroll to top so draft is immediately visible
      setState(() {
        _checkedSteps.clear();
        _settingsExpanded = false;
      });

      // Scroll to top so the draft card is the first thing the user sees
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }
      });

      // Toast message after generation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('🍽️ Your recipe is ready!'),
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
      _loadingMessageTimer?.cancel();
      _loadingMessageTimer = null;
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _refineRecipe() async {
    final currentDraft = ref.read(draftRecipeProvider);

    // Build combined refinement text: chip prompt + optional custom text
    final chipPrompt = _selectedQuickRefine != null
        ? _quickRefineOptions[_selectedQuickRefine!] ?? ''
        : '';
    final customText = _refineController.text.trim();
    final combinedRefinement = [
      chipPrompt,
      customText,
    ].where((s) => s.isNotEmpty).join(' Additionally: ');

    // Require at least a chip or custom text
    if (combinedRefinement.isEmpty) {
      setState(() {
        _errorMessage = 'Please select an option or describe what to change.';
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
      var refinedRecipe = await aiService.refineRecipe(
        originalRecipe: currentDraft.recipe,
        refinementText: combinedRefinement,
        showCalories: _showCalories,
      );

      // IMPORTANT: Reuse existing image URL from draft - don't fetch new one!
      if (currentDraft.imageUrl != null &&
          currentDraft.imageUrl!.isNotEmpty &&
          !currentDraft.imageUrl!.startsWith('assets/')) {
        refinedRecipe = refinedRecipe.copyWith(imageUrl: currentDraft.imageUrl);
      }

      // Update draft with refinement (increments counter automatically)
      ref
          .read(draftRecipeProvider.notifier)
          .updateWithRefinement(refinedRecipe);

      // Reset refine inputs
      _refineController.clear();
      setState(() => _selectedQuickRefine = null);

      // Show success toast
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recipe successfully refined! ✨'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Refinement Error: $e');
      }
      setState(() => _errorMessage = 'Refinement failed: $e');
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

      // Navigate to recipes list so the user sees their saved cookbook.
      if (!mounted) return;
      ref.read(draftRecipeProvider.notifier).clearDraft();
      context.go(AppRoutes.recipes);

      // Publish to global in the background (non-blocking)
      unawaited(
        db
            .publishRecipeToGlobal(userId: userId, recipe: recipeToSave)
            .catchError((e) {
              if (kDebugMode) debugPrint('Publish to global failed: $e');
            }),
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

  void _showRecipeHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        snap: true,
        snapSizes: const [0.4, 0.7, 0.9],
        builder: (context, scrollController) => Column(
          children: [
            // Drag handle — tapping it also closes
            GestureDetector(
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.history, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Text(
                    'Recipe History',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
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
    // Use the same provider the Recipes page uses — already live and cached
    final savedAsync = ref.watch(savedRecipesProvider);

    return savedAsync.when(
      loading: () => AppShimmer(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade100,
        child: ListView.builder(
          controller: scrollController,
          itemCount: 6,
          itemBuilder: (context, index) => const SkeletonListTile(),
        ),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Could not load recipes: $e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ),
      data: (recipes) {
        if (recipes.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.restaurant_menu, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No saved recipes yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Generate and save a recipe to see it here!',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: recipes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final recipe = recipes[index];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.pop(context);
                context.push(
                  '${AppRoutes.recipes}/${recipe.id}',
                  extra: recipe,
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    // Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: recipe.imageUrl.startsWith('http')
                            ? Image.network(
                                recipe.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.1,
                                  ),
                                  child: const Icon(
                                    Icons.restaurant,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              )
                            : Container(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.1,
                                ),
                                child: const Icon(
                                  Icons.restaurant,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recipe.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${recipe.timeMinutes} min'
                            '${recipe.calories > 0 ? '  •  ${recipe.calories} cal' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                      size: 18,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Three-dot pulsing animation for the generating card.
class _PulsingDot extends StatefulWidget {
  final int delayMs;
  const _PulsingDot({required this.delayMs});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: FadeTransition(
        opacity: _anim,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppTheme.primaryColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
