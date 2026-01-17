import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/providers/recipe_providers.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/core/widgets/loading/app_shimmer.dart';
import 'package:super_swipe/core/widgets/loading/skeleton.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/services/database/database_provider.dart';

class RecipeDetailScreen extends ConsumerStatefulWidget {
  final String recipeId;
  final Recipe? initialRecipe;
  final bool assumeUnlocked;
  final bool openDirections;
  final bool isGenerating;

  const RecipeDetailScreen({
    super.key,
    required this.recipeId,
    this.initialRecipe,
    this.assumeUnlocked = false,
    this.openDirections = false,
    this.isGenerating = false,
  });

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _directionsKey = GlobalKey();
  bool _didAutoScrollToDirections = false;

  bool _isUpdatingProgress = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeAutoScrollToDirections() {
    if (_didAutoScrollToDirections) return;
    if (!widget.openDirections) return;
    _didAutoScrollToDirections = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _directionsKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: 0.1,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(title: const Text('Recipe')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 56),
                const SizedBox(height: AppTheme.spacingM),
                const Text(
                  'Sign in required',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppTheme.spacingS),
                const Text(
                  'Please sign in to view unlocked recipes and track progress.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.spacingL),
                ElevatedButton(
                  onPressed: () => context.go(AppRoutes.login),
                  child: const Text('Sign In'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final savedRecipeAsync = ref.watch(savedRecipeProvider(widget.recipeId));
    final userProfileAsync = ref.watch(userProfileProvider);

    // Check if user is premium (can view without unlock)
    final userProfile = userProfileAsync.value;
    final subscription =
        userProfile?.subscriptionStatus.toLowerCase() ?? 'free';
    final isPremium = subscription == 'premium';
    final treatAsUnlocked = isPremium || widget.assumeUnlocked;

    return savedRecipeAsync.when(
      // CRITICAL FIX: Loading state shows spinner only, not recipe content
      loading: () {
        if (treatAsUnlocked && widget.initialRecipe != null) {
          _maybeAutoScrollToDirections();
          return _buildScaffoldForRecipe(
            context,
            widget.initialRecipe,
            isLoading: true,
            openDirections: widget.openDirections,
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            title: Text(widget.initialRecipe?.title ?? 'Recipe'),
            centerTitle: true,
          ),
          body: const AppPageLoading(),
        );
      },
      error: (error, stack) => _buildError(context, error),
      data: (savedRecipe) {
        // CRITICAL FIX: Free users MUST have recipe in savedRecipes (unlocked via carrot)
        // Premium users can use initialRecipe as fallback
        final recipe = treatAsUnlocked
            ? (savedRecipe ?? widget.initialRecipe)
            : savedRecipe;

        if (recipe == null) {
          return Scaffold(
            backgroundColor: AppTheme.backgroundColor,
            appBar: AppBar(title: const Text('Recipe')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 56,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(height: AppTheme.spacingM),
                    const Text(
                      'Recipe Not Unlocked',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingS),
                    const Text(
                      'Swipe right on this recipe to unlock it using a carrot.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spacingL),
                    ElevatedButton.icon(
                      onPressed: () => context.go(AppRoutes.swipe),
                      icon: const Icon(Icons.swipe_rounded),
                      label: const Text('Swipe for Supper'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        _maybeAutoScrollToDirections();
        return _buildScaffoldForRecipe(
          context,
          recipe,
          openDirections: widget.openDirections,
        );
      },
    );
  }

  Scaffold _buildError(BuildContext context, Object error) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('Recipe')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: AppTheme.errorColor,
              ),
              const SizedBox(height: AppTheme.spacingM),
              const Text(
                'Couldn’t load recipe',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppTheme.spacingS),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: AppTheme.spacingL),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.recipes),
                child: const Text('Back to Recipes'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Scaffold _buildScaffoldForRecipe(
    BuildContext context,
    Recipe? recipe, {
    bool isLoading = false,
    bool openDirections = false,
  }) {
    if (openDirections) {
      _maybeAutoScrollToDirections();
    }

    final safeRecipe = recipe;
    final instructions = safeRecipe?.instructions ?? const <String>[];
    final currentStep = safeRecipe?.currentStep ?? 0;
    final totalSteps = instructions.length;
    final showGeneratingSkeleton =
        widget.isGenerating && (safeRecipe?.instructions.isEmpty ?? true);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(safeRecipe?.title ?? 'Recipe'),
        centerTitle: true,
      ),
      body: safeRecipe == null
          ? const AppPageLoading()
          : SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppTheme.spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image with error fallback
                  ClipRRect(
                    borderRadius: AppTheme.borderRadiusLarge,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: safeRecipe.imageUrl.startsWith('http')
                          ? Image.network(
                              safeRecipe.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: Colors.grey[200],
                                    child: const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.image_not_supported_outlined,
                                            size: 48,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Image unavailable',
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                            )
                          : Image.asset(
                              safeRecipe.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: Colors.grey[200],
                                    child: const Center(
                                      child: Icon(
                                        Icons.image_not_supported_outlined,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                            ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),

                  // Progress
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppTheme.spacingM),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: AppTheme.borderRadiusLarge,
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.playlist_add_check_rounded,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: AppTheme.spacingS),
                        Expanded(
                          child: Text(
                            totalSteps == 0
                                ? 'Directions coming soon'
                                : 'Step $currentStep of $totalSteps',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (isLoading || showGeneratingSkeleton)
                          const SizedBox(width: 16),
                        if (isLoading || showGeneratingSkeleton)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: AppInlineLoading(
                              size: 18,
                              baseColor: Color(0xFFE6E6E6),
                              highlightColor: Color(0xFFF7F7F7),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppTheme.spacingL),

                  // Ingredients
                  Text(
                    'Ingredients',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  ...safeRecipe.ingredients.map(
                    (ing) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '•  ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Expanded(child: Text(ing)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: AppTheme.spacingL),

                  // Directions
                  Text(
                    'Directions',
                    key: _directionsKey,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  if (instructions.isEmpty)
                    (isLoading || showGeneratingSkeleton)
                        ? const AppShimmer(
                            child: Column(
                              children: [
                                SkeletonListTile(showLeading: false),
                                SizedBox(height: 10),
                                SkeletonListTile(showLeading: false),
                                SizedBox(height: 10),
                                SkeletonListTile(showLeading: false),
                              ],
                            ),
                          )
                        : const Text(
                            'Directions are not available for this recipe yet.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          )
                  else
                    Column(
                      children: List.generate(instructions.length, (index) {
                        final stepNumber = index + 1;
                        final isCompleted = stepNumber <= currentStep;
                        final isNext = stepNumber == currentStep + 1;

                        return Container(
                          margin: const EdgeInsets.only(
                            bottom: AppTheme.spacingS,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor,
                            borderRadius: AppTheme.borderRadiusMedium,
                            boxShadow: AppTheme.softShadow,
                            border: Border.all(
                              color: isNext
                                  ? AppTheme.primaryColor.withValues(alpha: 0.6)
                                  : Colors.transparent,
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(
                              isCompleted
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: isCompleted
                                  ? AppTheme.successColor
                                  : (isNext
                                        ? AppTheme.primaryColor
                                        : AppTheme.textLight),
                            ),
                            title: Text(
                              'Step $stepNumber',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(instructions[index]),
                            onTap: (!isNext || _isUpdatingProgress)
                                ? null
                                : () => _markStepComplete(stepNumber),
                            trailing: isNext && !_isUpdatingProgress
                                ? const Icon(Icons.chevron_right_rounded)
                                : (_isUpdatingProgress && isNext)
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: AppInlineLoading(
                                      size: 18,
                                      baseColor: Color(0xFFE6E6E6),
                                      highlightColor: Color(0xFFF7F7F7),
                                    ),
                                  )
                                : null,
                          ),
                        );
                      }),
                    ),

                  // "Cook This Meal" Button
                  const SizedBox(height: AppTheme.spacingXL),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isCooking
                          ? null
                          : () => _cookThisMeal(safeRecipe),
                      icon: _isCooking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: AppInlineLoading(
                                size: 20,
                                baseColor: Color(0xFFEFEFEF),
                                highlightColor: Color(0xFFFFFFFF),
                              ),
                            )
                          : const Icon(Icons.restaurant_menu_rounded),
                      label: Text(
                        _isCooking ? 'Updating Pantry...' : 'I Made This!',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                ],
              ),
            ),
    );
  }

  bool _isCooking = false;

  /// Deducts ingredients from pantry when user cooks the recipe.
  Future<void> _cookThisMeal(Recipe recipe) async {
    final userId = ref.read(authProvider).user?.uid;
    if (userId == null) return;

    setState(() => _isCooking = true);

    try {
      // Get user's pantry to match ingredients
      final pantryItems = ref.read(pantryItemsProvider).value ?? [];

      // Build list of ingredients to consume
      final usedIngredients = <Map<String, dynamic>>[];

      for (final ingredientId in recipe.ingredientIds) {
        // Find matching pantry item (fuzzy match by normalized name)
        final normalizedId = ingredientId.toLowerCase().trim();
        final match = pantryItems.where((item) {
          final pantryName = item.normalizedName.toLowerCase();
          return pantryName.contains(normalizedId) ||
              normalizedId.contains(pantryName);
        }).firstOrNull;

        if (match != null) {
          usedIngredients.add({
            'pantryItemId': match.id,
            'quantity': 1, // Default to 1 unit consumed
          });
        }
      }

      if (usedIngredients.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No matching pantry items to deduct. 🥕'),
              backgroundColor: AppTheme.warningColor,
            ),
          );
        }
      } else {
        // Call DatabaseService to deduct ingredients
        await ref
            .read(databaseServiceProvider)
            .consumeIngredients(
              userId,
              recipe.id,
              recipe.title,
              usedIngredients,
            );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Pantry updated! ${usedIngredients.length} items deducted. 🍽️',
              ),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update pantry: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCooking = false);
    }
  }

  Future<void> _markStepComplete(int stepNumber) async {
    final userId = ref.read(authProvider).user?.uid;
    if (userId == null) return;

    setState(() => _isUpdatingProgress = true);
    try {
      await ref
          .read(recipeServiceProvider)
          .updateSavedRecipeProgress(
            userId: userId,
            recipeId: widget.recipeId,
            currentStep: stepNumber,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update progress: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingProgress = false);
    }
  }
}
