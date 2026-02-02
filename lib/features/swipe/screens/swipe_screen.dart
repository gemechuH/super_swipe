import 'dart:async';

import 'package:super_swipe/services/ai/ai_recipe_service.dart';

import 'package:appinio_swiper/appinio_swiper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/config/assumed_seasonings.dart';
import 'package:super_swipe/core/config/constants.dart' show AppAssets;
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/core/providers/app_state_provider.dart';
import 'package:super_swipe/core/providers/recipe_providers.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/shared/master_energy_slider.dart';
import 'package:super_swipe/core/widgets/dialogs/confirm_unlock_dialog.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/features/swipe/providers/pantry_first_swipe_deck_provider.dart';
import 'package:super_swipe/features/swipe/services/pantry_first_swipe_deck_service.dart';
import 'package:super_swipe/features/swipe/widgets/recipe_preview_card.dart';
import 'package:super_swipe/features/swipe/widgets/swipe_filters_panel.dart';
import 'package:super_swipe/services/database/database_provider.dart';

class SwipeScreen extends ConsumerStatefulWidget {
  const SwipeScreen({super.key});

  @override
  ConsumerState<SwipeScreen> createState() => _SwipeScreenState();
}

/// Swipe = browse global recipes.
/// - Reads from global `recipes` collection (paged by energy)
/// - No AI generation happens here
/// - No per-user swipe-state is stored (dismiss is session-only)
/// - Unlock saves recipe into `users/{uid}/savedRecipes/{recipeId}`
class _SwipeScreenState extends ConsumerState<SwipeScreen> {
  final AppinioSwiperController _swiperController = AppinioSwiperController();

  int _selectedEnergyLevel = 2;
  bool _unlockFlowInProgress = false;

  bool _deckLoading = false;
  bool _didInitialLoad = false;
  bool _usePantryFirstDeck = true;
  int _swiperRebuildToken = 0;
  final Set<String> _dismissedCardIds = <String>{};

  final Map<int, List<Recipe>> _recipesByEnergy = <int, List<Recipe>>{};
  final Map<int, DocumentSnapshot?> _lastDocByEnergy =
      <int, DocumentSnapshot?>{};
  final Set<int> _loadingMoreEnergy = <int>{};

  // Batch Replay State
  List<RecipePreview> _replayCache = [];
  bool _isReplaying = false;

  @override
  void dispose() {
    _swiperController.dispose();
    super.dispose();
  }

  void _scheduleInitialLoadIfNeeded() {
    if (_didInitialLoad) return;
    _didInitialLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshEnergy(energyLevel: _selectedEnergyLevel));
    });
  }

  void _refreshCurrentDeck() {
    if (_usePantryFirstDeck) {
      unawaited(
        ref
            .read(pantryFirstSwipeDeckProvider(_selectedEnergyLevel).notifier)
            .topUpNow(),
      );
      return;
    }
    unawaited(_refreshEnergy(energyLevel: _selectedEnergyLevel));
  }

  /// Show filters panel as a bottom sheet
  void _showFiltersPanel(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SwipeFiltersPanel(
          onFiltersChanged: () {
            // Reset UI state (same pattern as energy level changes)
            setState(() {
              _dismissedCardIds.clear();
              _swiperRebuildToken++;
            });
            
            // Invalidate the deck provider to trigger regeneration with new filters
            ref.invalidate(
              pantryFirstSwipeDeckProvider(_selectedEnergyLevel),
            );
            
            // Force immediate refill with new filters
            unawaited(
              ref
                  .read(
                    pantryFirstSwipeDeckProvider(_selectedEnergyLevel).notifier,
                  )
                  .forceRefillNow(),
            );
          },
        ),
      ),
    );
  }

  String _norm(String value) => value.toLowerCase().trim();

  List<Recipe> _deckForEnergy(int energyLevel) {
    return _recipesByEnergy[energyLevel] ?? const <Recipe>[];
  }

  Future<void> _ensureEnergyLoaded(int energyLevel) async {
    if (_deckForEnergy(energyLevel).isNotEmpty) return;
    await _refreshEnergy(energyLevel: energyLevel);
  }



  Future<void> _refreshEnergy({required int energyLevel}) async {
    if (_deckLoading) return;
    setState(() => _deckLoading = true);

    try {
      final page = await ref
          .read(recipeServiceProvider)
          .getRecipesPageByEnergyLevel(energyLevel: energyLevel, limit: 30);

      if (!mounted) return;
      setState(() {
        _recipesByEnergy[energyLevel] = page.recipes;
        _lastDocByEnergy[energyLevel] = page.lastDoc;
        _dismissedCardIds.clear();
        _swiperRebuildToken++;
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SwipeScreen global refresh failed: $e');
        debugPrint('$st');
      }
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text("Couldn't load recipes right now. Please try again."),
            backgroundColor: AppTheme.errorColor,
          ),
        );
    } finally {
      if (mounted) setState(() => _deckLoading = false);
    }
  }

  Future<void> _loadMoreForEnergy(int energyLevel) async {
    if (_loadingMoreEnergy.contains(energyLevel)) return;

    final cursor = _lastDocByEnergy[energyLevel];
    if (cursor == null) return;

    setState(() => _loadingMoreEnergy.add(energyLevel));
    try {
      final page = await ref
          .read(recipeServiceProvider)
          .getRecipesPageByEnergyLevel(
            energyLevel: energyLevel,
            limit: 30,
            startAfterDoc: cursor,
          );

      if (!mounted) return;

      if (page.recipes.isEmpty) {
        setState(() => _lastDocByEnergy[energyLevel] = null);
        return;
      }

      setState(() {
        _recipesByEnergy[energyLevel] = <Recipe>[
          ..._deckForEnergy(energyLevel),
          ...page.recipes,
        ];
        _lastDocByEnergy[energyLevel] = page.lastDoc;
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SwipeScreen global load-more failed: $e');
        debugPrint('$st');
      }
    } finally {
      if (mounted) setState(() => _loadingMoreEnergy.remove(energyLevel));
    }
  }

  Widget _buildGuestGate() {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Swipe'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 56,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Sign in to start swiping.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Guests can browse the app, but Swipe requires a full account.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.go(AppRoutes.login),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Go to Login'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPantryGate({required int nonSeasoningCount}) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Swipe'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.kitchen_outlined,
                  size: 56,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Add at least 3 ingredients to start',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You have $nonSeasoningCount so far. Seasonings like salt and pepper don\'t count.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.go(AppRoutes.pantry),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Go to Pantry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Set<String> _pantryKeySet(List<PantryItem> pantryItems) {
    return pantryItems
        .map((i) => _norm(i.normalizedName))
        .where((n) => n.isNotEmpty)
        .toSet();
  }

  bool _pantryHas(Set<String> pantry, String ingredientId) {
    final needle = _norm(ingredientId);
    if (needle.isEmpty) return true;
    if (pantry.contains(needle)) return true;
    for (final item in pantry) {
      if (item.contains(needle) || needle.contains(item)) return true;
    }
    return false;
  }

  void _onSwipeEnd(
    List<Recipe> deck,
    int previousIndex,
    int targetIndex,
    SwiperActivity activity,
  ) {
    if (activity is! Swipe) return;
    if (previousIndex >= deck.length) return;

    final swipedRecipe = deck[previousIndex];
    setState(() {
      _dismissedCardIds.add(swipedRecipe.id);
    });

    if (activity.direction == AxisDirection.right) {
      unawaited(_handleRightSwipe(swipedRecipe));
    }

    if (deck.length <= 1) {
      unawaited(_loadMoreForEnergy(_selectedEnergyLevel));
    }
  }

  void _onPreviewSwipeEnd(
    List<RecipePreview> deck,
    int previousIndex,
    int targetIndex,
    SwiperActivity activity,
  ) {
    if (activity is! Swipe) return;
    if (previousIndex >= deck.length) return;

    // Trigger refill based on remaining *after* this swipe removes a card.
    // When user has 5 or fewer cards remaining, generate +10 in background.
    // This provides buffer time for generation while user keeps swiping.
    final remainingAfterSwipe = (deck.length - 1).clamp(0, 1000000);

    final swiped = deck[previousIndex];
    setState(() {
      _dismissedCardIds.add(swiped.id);
    });

    if (kDebugMode) {
      debugPrint(
        '[SwipeScreen] Swipe ended: '
        'remaining=$remainingAfterSwipe, '
        'deckLength=${deck.length}, '
        'dismissedIds=${_dismissedCardIds.length}',
      );
    }

    // Trigger refill - use forceRefillNow if this was the last card
    if (remainingAfterSwipe == 0) {
      if (kDebugMode) {
        debugPrint('[SwipeScreen] Last card swiped! Forcing immediate refill.');
      }
      unawaited(
        ref
            .read(pantryFirstSwipeDeckProvider(_selectedEnergyLevel).notifier)
            .forceRefillNow(),
      );
    } else {
      unawaited(
        ref
            .read(pantryFirstSwipeDeckProvider(_selectedEnergyLevel).notifier)
            .maybeTriggerRefillForVisibleRemaining(remainingAfterSwipe),
      );
    }

    if (activity.direction == AxisDirection.left) {
      unawaited(_handlePreviewLeftSwipe(swiped));
    } else if (activity.direction == AxisDirection.right) {
      unawaited(_handlePreviewRightSwipe(swiped));
    }
  }

  Future<void> _handlePreviewLeftSwipe(RecipePreview preview) async {
    final user = ref.read(authProvider).user;
    if (user == null || user.isAnonymous == true) return;

    await ref
        .read(databaseServiceProvider)
        .markSwipeCardDisliked(user.uid, preview.id);
  }

  Recipe _placeholderRecipeFromPreview(RecipePreview preview) {
    final imageUrl = (preview.imageUrl?.isNotEmpty == true)
        ? preview.imageUrl!
        : AppAssets.placeholderRecipe;
    final ingredients = preview.ingredients.isNotEmpty
        ? preview.ingredients
        : preview.mainIngredients;

    return Recipe(
      id: preview.id,
      title: preview.title,
      imageUrl: imageUrl,
      description: preview.vibeDescription,
      ingredients: ingredients,
      instructions: const <String>[],
      ingredientIds: const <String>[],
      energyLevel: preview.energyLevel,
      timeMinutes: preview.estimatedTimeMinutes,
      calories: preview.calories,
      equipment: preview.equipmentIcons,
      mealType: preview.mealType,
      skillLevel: preview.skillLevel,
      cuisine: preview.cuisine,
      isPremium: false,
    );
  }

  Future<void> _handlePreviewRightSwipe(RecipePreview preview) async {
    final user = ref.read(authProvider).user;
    if (user == null || user.isAnonymous == true) return;

    Future<void> undoLastSwipeAndRestore() async {
      _dismissedCardIds.remove(preview.id);
      try {
        await _swiperController.unswipe();
      } catch (_) {
        // no-op
      }
    }

    if (_unlockFlowInProgress) return;
    setState(() => _unlockFlowInProgress = true);

    try {
      // If already unlocked (in My Recipes), just open it.
      final saved = ref.read(savedRecipesProvider).value;
      final alreadyUnlocked = saved?.any((r) => r.id == preview.id) == true;
      if (alreadyUnlocked) {
        unawaited(
          ref
              .read(databaseServiceProvider)
              .markSwipeCardConsumed(user.uid, preview.id),
        );
        if (mounted) {
          _openRecipeDetailById(preview.id, assumeUnlocked: true);
        }
        return;
      }

      final profile = ref.read(userProfileProvider).value;
      final subscription = profile?.subscriptionStatus.toLowerCase() ?? 'free';
      final isPremium = subscription == 'premium';

      final carrotsObj = profile?.carrots;
      final maxCarrots = carrotsObj?.max ?? 5;
      final currentCarrots = carrotsObj?.current ?? 0;

      if (!mounted) return;

      final hideUnlockReminder = ref.read(appStateProvider).skipUnlockReminder;

      bool shouldProceed;
      if (isPremium) {
        shouldProceed = true;
      } else if (hideUnlockReminder) {
        shouldProceed = await _showReducedUnlockDialog(
          preview: preview,
          currentCarrots: currentCarrots,
          maxCarrots: maxCarrots,
        );
      } else {
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return ConfirmUnlockDialog(
              preview: preview,
              currentCarrots: currentCarrots,
              maxCarrots: maxCarrots,
              initialDoNotShowAgain: hideUnlockReminder,
              onDoNotShowAgainChanged: (v) {
                unawaited(
                  ref.read(appStateProvider.notifier).setSkipUnlockReminder(v),
                );
              },
              onCancel: () => Navigator.of(dialogContext).pop(false),
              onUnlock: () => Navigator.of(dialogContext).pop(true),
            );
          },
        );
        shouldProceed = confirmed == true;
      }

      if (!shouldProceed || !mounted) {
        await undoLastSwipeAndRestore();
        return;
      }

      final notifier = ref.read(
        pantryFirstSwipeDeckProvider(_selectedEnergyLevel).notifier,
      );

      await notifier.reserveUnlockPreview(preview, unlockSource: 'swipe_right');

      if (!mounted) return;

      final placeholder = _placeholderRecipeFromPreview(preview);
      _openRecipeDetailById(
        preview.id,
        recipe: placeholder,
        assumeUnlocked: true,
        openDirections: true,
        isGenerating: true,
      );

      unawaited(
        notifier.generateAndFinalizeUnlockPreview(
          preview,
          unlockSource: 'swipe_right',
        ),
      );
    } on OutOfCarrotsException {
      if (mounted) _showOutOfCarrots();
      await undoLastSwipeAndRestore();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SwipeScreen preview unlock failed: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not unlock that recipe. Please try again.'),
          ),
        );
      }
      await undoLastSwipeAndRestore();
    } finally {
      if (mounted) setState(() => _unlockFlowInProgress = false);
    }
  }

  Future<void> _handlePreviewShowDirections(RecipePreview preview) async {
    final authUser = ref.read(authProvider).user;
    final userId = authUser?.uid;

    if (userId == null || authUser?.isAnonymous == true) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    // If already unlocked (in My Recipes), just open directions.
    final saved = ref.read(savedRecipesProvider).value;
    final alreadyUnlocked = saved?.any((r) => r.id == preview.id) == true;
    if (alreadyUnlocked) {
      unawaited(
        ref
            .read(databaseServiceProvider)
            .markSwipeCardConsumed(userId, preview.id),
      );
      if (mounted) {
        _dismissedCardIds.add(preview.id);
        _openRecipeDetailById(
          preview.id,
          assumeUnlocked: true,
          openDirections: true,
        );
      }
      return;
    }

    if (_unlockFlowInProgress) return;

    final profile = ref.read(userProfileProvider).value;
    final subscription = profile?.subscriptionStatus.toLowerCase() ?? 'free';
    final isPremium = subscription == 'premium';

    final carrotsObj = profile?.carrots;
    final maxCarrots = carrotsObj?.max ?? 5;
    final currentCarrots = carrotsObj?.current ?? 0;

    final hideUnlockReminder = ref.read(appStateProvider).skipUnlockReminder;

    bool shouldProceed;
    if (isPremium) {
      shouldProceed = true;
    } else if (hideUnlockReminder) {
      shouldProceed = await _showReducedUnlockDialog(
        preview: preview,
        currentCarrots: currentCarrots,
        maxCarrots: maxCarrots,
      );
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return ConfirmUnlockDialog(
            preview: preview,
            currentCarrots: currentCarrots,
            maxCarrots: maxCarrots,
            initialDoNotShowAgain: hideUnlockReminder,
            onDoNotShowAgainChanged: (v) {
              unawaited(
                ref.read(appStateProvider.notifier).setSkipUnlockReminder(v),
              );
            },
            onCancel: () => Navigator.of(dialogContext).pop(false),
            onUnlock: () => Navigator.of(dialogContext).pop(true),
          );
        },
      );
      shouldProceed = confirmed == true;
    }

    if (!shouldProceed || !mounted) return;

    setState(() => _unlockFlowInProgress = true);
    try {
      final notifier = ref.read(
        pantryFirstSwipeDeckProvider(_selectedEnergyLevel).notifier,
      );

      await notifier.reserveUnlockPreview(
        preview,
        unlockSource: 'show_directions',
      );

      if (!mounted) return;
      _dismissedCardIds.add(preview.id);

      final placeholder = _placeholderRecipeFromPreview(preview);
      _openRecipeDetailById(
        preview.id,
        recipe: placeholder,
        assumeUnlocked: true,
        openDirections: true,
        isGenerating: true,
      );

      unawaited(
        notifier.generateAndFinalizeUnlockPreview(
          preview,
          unlockSource: 'show_directions',
        ),
      );
    } on OutOfCarrotsException {
      if (mounted) _showOutOfCarrots();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SwipeScreen preview Show Directions unlock failed: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not unlock that recipe. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _unlockFlowInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authProvider).user;
    if (authUser != null && authUser.isAnonymous) {
      return _buildGuestGate();
    }

    final pantryAsync = ref.watch(pantryItemsProvider);
    final includeBasics = ref.watch(includeBasicsProvider);

    if (pantryAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('Swipe'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(
          child: AppInlineLoading(
            size: 28,
            baseColor: Color(0xFFE6E6E6),
            highlightColor: Color(0xFFF7F7F7),
          ),
        ),
      );
    }

    if (pantryAsync.hasError) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('Swipe'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Couldn\'t load your pantry right now.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        ),
      );
    }

    final nonSeasoningCount = countNonSeasoningPantryItems(
      pantryAsync.value ?? const <PantryItem>[],
      includeBasics: includeBasics,
    );

    if (nonSeasoningCount < 3) {
      return _buildPantryGate(nonSeasoningCount: nonSeasoningCount);
    }

    final isPremium = ref.watch(
      userProfileProvider.select((asyncProfile) {
        final profile = asyncProfile.asData?.value;
        final subscription = (profile?.subscriptionStatus ?? 'free')
            .toLowerCase();
        return subscription == 'premium';
      }),
    );

    final currentCarrots = ref.watch(
      userProfileProvider.select((asyncProfile) {
        final profile = asyncProfile.asData?.value;
        return profile?.carrots.current ?? 0;
      }),
    );
    final canUnlock = isPremium || currentCarrots > 0;

    final deckForEnergy = _deckForEnergy(_selectedEnergyLevel);
    final visibleLegacyDeck = deckForEnergy
        .where((r) => !_dismissedCardIds.contains(r.id))
        .toList(growable: false);

    final previewDeckAsync = ref.watch(
      pantryFirstSwipeDeckProvider(_selectedEnergyLevel),
    );
    final previewDeck = previewDeckAsync.value ?? const <RecipePreview>[];
    final visiblePreviewDeck = previewDeck
        .where((p) => !_dismissedCardIds.contains(p.id))
        .toList(growable: false);

    // Watch refilling state for background generation indicator
    final isRefilling = ref.watch(
      swipeDeckRefillingProvider(_selectedEnergyLevel),
    );

    final usingPreview = _usePantryFirstDeck;
    final activeDeckCount = usingPreview
        ? visiblePreviewDeck.length
        : visibleLegacyDeck.length;

    if (!usingPreview && deckForEnergy.isEmpty && !_deckLoading) {
      _scheduleInitialLoadIfNeeded();
    }

    // SAFETY: Clean up dismissed IDs that no longer exist in provider
    // This prevents stale dismissed IDs from blocking new cards
    if (previewDeck.isNotEmpty && _dismissedCardIds.isNotEmpty) {
      final providerIds = previewDeck.map((p) => p.id).toSet();
      final staleIds = _dismissedCardIds.difference(providerIds);
      if (staleIds.isNotEmpty && kDebugMode) {
        debugPrint(
          '[SwipeScreen] Cleaning ${staleIds.length} stale dismissed IDs',
        );
      }
      // Don't clear during build, but schedule for next frame
      if (staleIds.length == _dismissedCardIds.length) {
        // All dismissed IDs are stale - will be cleaned after refill
      }
    }

    // DEBUG: Log current state to trace empty deck issues
    if (kDebugMode) {
      debugPrint(
        '[SwipeScreen] Build state: '
        'previewDeck=${previewDeck.length}, '
        'visible=${visiblePreviewDeck.length}, '
        'dismissed=${_dismissedCardIds.length}, '
        'refilling=$isRefilling, '
        'loading=${previewDeckAsync.isLoading}',
      );
    }

    Widget deckWidget;
    if (usingPreview) {
      // 1. CACHE LOGIC - Always keep a copy of the current batch for restart functionality
      if (previewDeck.isNotEmpty && (_replayCache.isEmpty || previewDeck.first.id != _replayCache.first.id)) {
        // Cache the current batch (done in post-frame to avoid setState during build)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final currentPreview = ref.read(pantryFirstSwipeDeckProvider(_selectedEnergyLevel)).value ?? [];
          if (currentPreview.isEmpty) return;
          
          final shouldUpdate = _replayCache.isEmpty || currentPreview.first.id != _replayCache.first.id;
          if (shouldUpdate) {
            setState(() {
              _replayCache = List.of(currentPreview);
              if (_isReplaying) {
                _isReplaying = false;
                _dismissedCardIds.clear();
                _swiperRebuildToken++;
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Fresh ideas ready!'),
                    backgroundColor: AppTheme.primaryColor,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            });
          }
        });
      }

      // CRITICAL: Determine if we need to show empty/loading state
      final providerDeckEmpty = previewDeck.isEmpty;
      final visibleDeckEmpty = visiblePreviewDeck.isEmpty;
      final allCardsDismissed = previewDeck.isNotEmpty && visiblePreviewDeck.isEmpty;
      
      // If we are replaying, we are NOT empty in the UI sense
      final hasNoVisibleCards = (providerDeckEmpty || visibleDeckEmpty || allCardsDismissed) && !_isReplaying;

      // Determine active deck
      final currentDeck = _isReplaying ? _replayCache : visiblePreviewDeck;
      final currentCardCount = currentDeck.length;

      // NOTE: Auto-replay is disabled. Users must use explicit buttons to replay.
      // - Undo button: goes back to previous card
      // - Restart button: goes back to first card in batch

      if (previewDeckAsync.isLoading && previewDeck.isEmpty && !_isReplaying) {
        // ... (existing loading code)
        // ... (existing loading code)
        deckWidget = Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppInlineLoading(
                      size: 28,
                      baseColor: Color(0xFFE6E6E6),
                      highlightColor: Color(0xFFF7F7F7),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Creating your next ideas…',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'We’re generating 20 recipes to get you started.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => context.go(AppRoutes.pantry),
                        child: const Text('Go to Pantry'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => context.go(AppRoutes.aiGenerate),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Generate a recipe'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else if (previewDeckAsync.hasError &&
          previewDeckAsync.error is GeminiRateLimitException) {
        deckWidget = Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.traffic_rounded,
                      size: 56,
                      color: AppTheme.warningColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Chef is busy right now',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'High traffic in the kitchen. Upgrade to Pro for priority access or try again in a moment.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          // TODO: Route to upgrade screen
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Coming soon: Pro Plan!'),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Upgrade to Pro'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _refreshCurrentDeck,
                        child: const Text('Retry'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else if (previewDeckAsync.hasError) {
        deckWidget = Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 56,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Couldn\'t generate ideas right now',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tap retry, or try changing energy level / pantry items.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _refreshCurrentDeck,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => context.go(AppRoutes.pantry),
                        child: const Text('Go to Pantry'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else if (hasNoVisibleCards) {
        // CRITICAL: Deck is empty - MUST show feedback and trigger refill
        if (kDebugMode) {
          debugPrint(
            '[SwipeScreen] Empty deck detected! providerEmpty=$providerDeckEmpty, visibleEmpty=$visibleDeckEmpty, isRefilling=$isRefilling',
          );
        }

        // DO NOT clear dismissed IDs during build - causes race condition!
        // Instead, clear them in post-frame callback AFTER triggering refill
        if (!isRefilling) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (kDebugMode) {
              debugPrint(
                '[SwipeScreen] Triggering auto-refill and clearing dismissed IDs...',
              );
            }
            // Clear dismissed IDs BEFORE refill so new cards won't be filtered
            setState(() {
              _dismissedCardIds.clear();
              _swiperRebuildToken++; // Force swiper rebuild when cards arrive
            });
            unawaited(
              ref
                  .read(
                    pantryFirstSwipeDeckProvider(_selectedEnergyLevel).notifier,
                  )
                  .triggerRefillIfEmpty(),
            );
          });
        }

        // ALWAYS show the loading UI - this MUST be visible
        deckWidget = _buildEmptyDeckLoadingState(context, isRefilling);
      } else if (currentDeck.isNotEmpty) {
        // Show swiper ONLY when there are actually cards to show
        final cardCount = currentDeck.length;

        deckWidget = Stack(
          children: [
            if (_isReplaying)
              Positioned(
                 top: 60,
                 left: 0, 
                 right: 0,
                 child: Center(
                   child: Container(
                     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                     decoration: BoxDecoration(
                       color: Colors.amber.shade100,
                       borderRadius: BorderRadius.circular(20),
                       border: Border.all(color: Colors.amber.shade300),
                     ),
                     child: Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Icon(Icons.history_rounded, size: 16, color: Colors.amber.shade900),
                         const SizedBox(width: 8),
                         Text(
                           'Reviewing recent swipes while we cook...',
                           style: TextStyle(
                             color: Colors.amber.shade900, 
                             fontWeight: FontWeight.bold,
                             fontSize: 12,
                           ),
                         ),
                       ],
                     ),
                   ),
                 ),
              ),

            AppinioSwiper(
              key: ValueKey(
                'preview_${_selectedEnergyLevel}_${_swiperRebuildToken}_${_isReplaying}_$cardCount',
              ),
              controller: _swiperController,
              cardCount: cardCount,
              onSwipeEnd: (previousIndex, targetIndex, activity) {
                  // If reviewing history, we might want different logic?
                  // For now, re-swiping right on history behaves like a new "I Made This" intent
                  _onPreviewSwipeEnd(
                    currentDeck,
                    previousIndex,
                    targetIndex,
                    activity,
                  );
              },
              cardBuilder: (context, index) {
                if (index >= currentDeck.length) return const SizedBox.shrink();
                return RecipePreviewCard(
                  preview: currentDeck[index],
                  onShowDirections: () =>
                      _handlePreviewShowDirections(currentDeck[index]),
                );
              },
            ),
            // Subtle loading indicator when refilling in background
            if (isRefilling)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                       children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: AppInlineLoading(
                            size: 14,
                            baseColor: Color(0xFFE6E6E6),
                            highlightColor: Color(0xFFF7F7F7),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Creating fresh ideas…',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      } else {
        // FALLBACK: This should NEVER happen, but if it does, show clear feedback
        // This catches any edge case we might have missed
        if (kDebugMode) {
          debugPrint(
            '[SwipeScreen] FALLBACK triggered! '
            'currentDeck=${currentDeck.length}, ',
          );
        }

        // Trigger refill in post-frame callback (don't modify state during build)
        if (!isRefilling) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _dismissedCardIds.clear();
              _swiperRebuildToken++;
            });
            unawaited(
              ref
                  .read(
                    pantryFirstSwipeDeckProvider(_selectedEnergyLevel).notifier,
                  )
                  .forceRefillNow(),
            );
          });
        }
        // ALWAYS show loading state as fallback - never leave empty
        deckWidget = _buildEmptyDeckLoadingState(context, isRefilling);
      }
    } else {
      final showLoading =
          (_deckLoading && deckForEnergy.isEmpty) ||
          _loadingMoreEnergy.contains(_selectedEnergyLevel);

      if (showLoading) {
        deckWidget = _buildDeckLoading();
      } else if (visibleLegacyDeck.isEmpty) {
        deckWidget = Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              deckForEnergy.isEmpty
                  ? 'No recipes yet. Tap refresh to load.'
                  : 'No more recipes right now. Try another energy level.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        );
      } else {
        deckWidget = AppinioSwiper(
          key: ValueKey('legacy_${_selectedEnergyLevel}_$_swiperRebuildToken'),
          controller: _swiperController,
          cardCount: visibleLegacyDeck.length,
          onSwipeEnd: (previousIndex, targetIndex, activity) => _onSwipeEnd(
            visibleLegacyDeck,
            previousIndex,
            targetIndex,
            activity,
          ),
          cardBuilder: (context, index) =>
              _buildRecipeCard(visibleLegacyDeck[index]),
        );
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Swipe'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Filter button (only for pantry-first deck)
          if (_usePantryFirstDeck)
            IconButton(
              tooltip: 'Filters',
              onPressed: () => _showFiltersPanel(context),
              icon: const SwipeFilterBadge(),
            ),
          IconButton(
            tooltip: 'Refresh deck',
            onPressed: _deckLoading ? null : _refreshCurrentDeck,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: _usePantryFirstDeck
                ? 'Use global recipes'
                : 'Use swipe ideas',
            onPressed: () {
              setState(() {
                _usePantryFirstDeck = !_usePantryFirstDeck;
                _dismissedCardIds.clear();
                _swiperRebuildToken++;
              });
              _refreshCurrentDeck();
            },
            icon: Icon(
              _usePantryFirstDeck
                  ? Icons.public_rounded
                  : Icons.auto_awesome_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: MasterEnergySlider(
                    value: _selectedEnergyLevel,
                    onChanged: (next) {
                      if (next == _selectedEnergyLevel) return;
                      setState(() {
                        _selectedEnergyLevel = next;
                        _dismissedCardIds.clear();
                        _swiperRebuildToken++;
                      });
                      if (!_usePantryFirstDeck) {
                        unawaited(_ensureEnergyLoaded(next));
                      }
                    },
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 110),
                    child: deckWidget,
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildActionButton(
                          icon: Icons.close,
                          color: AppTheme.errorColor,
                          onPressed:
                              (_unlockFlowInProgress || activeDeckCount == 0)
                              ? null
                              : () => _swiperController.swipeLeft(),
                        ),
                        // UNDO BUTTON - Go back to previous swipe
                        Tooltip(
                          message: 'Undo last swipe',
                          child: _buildActionButton(
                            icon: Icons.rotate_left_rounded,
                            color: Colors.orange,
                            isSmall: true,
                            onPressed: _dismissedCardIds.isEmpty
                                ? null
                                : () => _swiperController.unswipe(),
                          ),
                        ),
                        // RESTART BATCH BUTTON - Go back to first card in batch
                        Tooltip(
                          message: 'Start over from first card',
                          child: _buildActionButton(
                            icon: Icons.skip_previous_rounded,
                            color: Colors.teal,
                            isSmall: true,
                            onPressed: _dismissedCardIds.isEmpty
                                ? null
                                : () {
                                    setState(() {
                                      _dismissedCardIds.clear();
                                      _swiperRebuildToken++;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Back to first card!'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                          ),
                        ),
                        _buildActionButton(
                          icon: Icons.info_outline_rounded,
                          color: Colors.blueGrey,
                          isSmall: true,
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Tip: Left = dislike, right = keep moving.',
                                ),
                              ),
                            );
                          },
                        ),
                        if (!_usePantryFirstDeck)
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: canUnlock ? 1.0 : 0.5,
                            child: _buildActionButton(
                              icon: Icons.arrow_forward_rounded,
                              color: AppTheme.primaryColor,
                              onPressed:
                                  (_unlockFlowInProgress ||
                                      activeDeckCount == 0)
                                  ? null
                                  : () {
                                      final authUser = ref
                                          .read(authProvider)
                                          .user;
                                      if (authUser == null ||
                                          authUser.isAnonymous) {
                                        context.go(AppRoutes.login);
                                        return;
                                      }

                                      if (canUnlock) {
                                        _swiperController.swipeRight();
                                      } else {
                                        _showOutOfCarrots();
                                      }
                                    },
                            ),
                          )
                        else
                          _buildActionButton(
                            icon: Icons.arrow_forward_rounded,
                            color: AppTheme.primaryColor,
                            onPressed:
                                (_unlockFlowInProgress || activeDeckCount == 0)
                                ? null
                                : () => _swiperController.swipeRight(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRecipeDetail(
    Recipe recipe, {
    bool assumeUnlocked = false,
    bool openDirections = false,
    bool isGenerating = false,
  }) {
    context.push(
      '${AppRoutes.recipes}/${recipe.id}',
      extra: {
        'recipe': recipe,
        'assumeUnlocked': assumeUnlocked,
        'openDirections': openDirections,
        'isGenerating': isGenerating,
      },
    );
  }

  void _openRecipeDetailById(
    String recipeId, {
    Recipe? recipe,
    bool assumeUnlocked = false,
    bool openDirections = false,
    bool isGenerating = false,
  }) {
    context.push(
      '${AppRoutes.recipes}/$recipeId',
      extra: {
        if (recipe != null) 'recipe': recipe,
        'assumeUnlocked': assumeUnlocked,
        'openDirections': openDirections,
        'isGenerating': isGenerating,
      },
    );
  }

  Future<void> _handleRightSwipe(Recipe recipe) async {
    if (_unlockFlowInProgress) return;
    setState(() => _unlockFlowInProgress = true);

    Future<void> undoLastSwipeAndRestore() async {
      _dismissedCardIds.remove(recipe.id);
      try {
        await _swiperController.unswipe();
      } catch (_) {
        // no-op
      }
    }

    try {
      final authUser = ref.read(authProvider).user;
      final userId = authUser?.uid;

      if (userId == null || authUser?.isAnonymous == true) {
        if (mounted) context.go(AppRoutes.login);
        await undoLastSwipeAndRestore();
        return;
      }

      final alreadySaved = await ref
          .read(recipeServiceProvider)
          .isRecipeSaved(userId, recipe.id);
      if (alreadySaved) {
        if (mounted) {
          _openRecipeDetail(recipe, assumeUnlocked: true, openDirections: true);
        }
        return;
      }

      final profile = ref.read(userProfileProvider).value;
      final subscription = profile?.subscriptionStatus.toLowerCase() ?? 'free';
      final isPremium = subscription == 'premium';

      final hideUnlockReminder = ref.read(appStateProvider).skipUnlockReminder;

      final preview = RecipePreview(
        id: recipe.id,
        title: recipe.title,
        vibeDescription: recipe.description,
        mainIngredients: recipe.ingredientIds.isNotEmpty
            ? recipe.ingredientIds.take(4).toList()
            : recipe.ingredients.take(4).toList(),
        imageUrl: recipe.imageUrl,
        estimatedTimeMinutes: recipe.timeMinutes,
        mealType: recipe.mealType,
        energyLevel: recipe.energyLevel,
      );

      final carrotsObj = profile?.carrots;
      final maxCarrots = carrotsObj?.max ?? 5;
      final currentCarrots = carrotsObj?.current ?? 0;
      final availableCarrots = currentCarrots;

      if (!mounted) return;

      bool shouldProceed;
      if (isPremium) {
        shouldProceed = true;
      } else if (hideUnlockReminder) {
        shouldProceed = await _showReducedUnlockDialog(
          preview: preview,
          currentCarrots: availableCarrots,
          maxCarrots: maxCarrots,
        );
      } else {
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return ConfirmUnlockDialog(
              preview: preview,
              currentCarrots: availableCarrots,
              maxCarrots: maxCarrots,
              initialDoNotShowAgain: hideUnlockReminder,
              onDoNotShowAgainChanged: (v) {
                unawaited(
                  ref.read(appStateProvider.notifier).setSkipUnlockReminder(v),
                );
              },
              onCancel: () => Navigator.of(dialogContext).pop(false),
              onUnlock: () => Navigator.of(dialogContext).pop(true),
            );
          },
        );
        shouldProceed = confirmed == true;
      }

      if (!shouldProceed || !mounted) {
        await undoLastSwipeAndRestore();
        return;
      }

      if (!isPremium) {
        final success = await ref
            .read(databaseServiceProvider)
            .deductCarrot(userId);
        if (!success) {
          if (!mounted) return;
          _showOutOfCarrots();
          await undoLastSwipeAndRestore();
          return;
        }
      }

      final global = await ref
          .read(recipeServiceProvider)
          .getRecipeById(recipe.id);
      if (global == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recipe is unavailable right now.')),
          );
        }
        await undoLastSwipeAndRestore();
        return;
      }

      await ref.read(recipeServiceProvider).saveRecipe(userId, global);
      if (mounted) _openRecipeDetail(global, assumeUnlocked: true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SwipeScreen unlock failed: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not unlock that recipe. Please try again.'),
          ),
        );
      }
      await undoLastSwipeAndRestore();
    } finally {
      if (mounted) setState(() => _unlockFlowInProgress = false);
    }
  }

  void _showOutOfCarrots() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Out of Carrots! 🥕'),
        backgroundColor: AppTheme.errorColor,
      ),
    );
  }

  Widget _buildDeckLoading() {
    Widget skeletonLine({double width = double.infinity, double height = 14}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
      );
    }

    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 420,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppTheme.mediumShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.grey.shade100),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              skeletonLine(width: 90, height: 18),
                              const SizedBox(width: 10),
                              skeletonLine(width: 70, height: 18),
                              const SizedBox(width: 10),
                              skeletonLine(width: 80, height: 18),
                            ],
                          ),
                          const SizedBox(height: 14),
                          skeletonLine(width: 240, height: 22),
                          const SizedBox(height: 10),
                          skeletonLine(width: 320, height: 14),
                          const SizedBox(height: 8),
                          skeletonLine(width: 280, height: 14),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: AppInlineLoading(
                                  size: 18,
                                  baseColor: Color(0xFFE6E6E6),
                                  highlightColor: Color(0xFFF7F7F7),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Loading recipes…',
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a prominent loading state when deck is empty and generating more.
  /// This ensures users always see feedback instead of a blank screen.
  /// CRITICAL: This widget MUST always render visibly - no collapse allowed.
  Widget _buildEmptyDeckLoadingState(BuildContext context, bool isRefilling) {
    if (kDebugMode) {
      debugPrint(
        '[SwipeScreen] Building empty deck loading state (isRefilling=$isRefilling)',
      );
    }

    return Container(
      // CRITICAL: Force minimum height to prevent collapse
      constraints: const BoxConstraints(minHeight: 400),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppTheme.mediumShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated loading indicator - ALWAYS visible
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Clear status message
              Text(
                isRefilling
                    ? 'Creating more ideas…'
                    : 'Getting fresh recipes ready…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isRefilling
                    ? 'Hold tight! New recipes tailored to your pantry are on the way.'
                    : 'Our AI is cooking up personalized ideas just for you.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              // Additional helper text
              Text(
                'This usually takes a few seconds.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 24),
              // ALWAYS show button - use force refill to bypass cooldown
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isRefilling
                      ? null // Disable when already refilling
                      : () {
                          if (kDebugMode) {
                            debugPrint(
                              '[SwipeScreen] User tapped Generate more ideas',
                            );
                          }
                          // Use force refill to bypass cooldown
                          unawaited(
                            ref
                                .read(
                                  pantryFirstSwipeDeckProvider(
                                    _selectedEnergyLevel,
                                  ).notifier,
                                )
                                .forceRefillNow(),
                          );
                        },
                  icon: isRefilling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white70,
                            ),
                          ),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    isRefilling ? 'Generating…' : 'Generate more ideas',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.go(AppRoutes.pantry),
                  icon: const Icon(Icons.kitchen_outlined, size: 18),
                  label: const Text('Update Pantry'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _buildRecipeCard(Recipe recipe) {
    final pantryItems =
        ref.watch(pantryItemsProvider).value ?? const <PantryItem>[];
    final pantry = _pantryKeySet(pantryItems);

    final ingredientCount = recipe.ingredientIds.isNotEmpty
        ? recipe.ingredientIds.length
        : recipe.ingredients.length;
    final equipment = recipe.equipment
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.mediumShadow,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (recipe.imageUrl.startsWith('http'))
                  CachedNetworkImage(
                    imageUrl: recipe.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: AppInlineLoading(
                          size: 28,
                          baseColor: Color(0xFFE6E6E6),
                          highlightColor: Color(0xFFF7F7F7),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(
                        Icons.broken_image,
                        size: 80,
                        color: Colors.grey,
                      ),
                    ),
                  )
                else
                  Image.network(
                    'https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?q=80&w=1200&auto=format&fit=crop',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(
                        Icons.broken_image,
                        size: 80,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                        stops: const [0.55, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Stat pills (time / items / calories)
          Positioned(
            left: 16,
            right: 16,
            bottom: 230,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statPill(Icons.timer_outlined, '${recipe.timeMinutes} min'),
                _statPill(
                  Icons.format_list_bulleted_rounded,
                  '$ingredientCount items',
                ),
                _statPill(
                  Icons.local_fire_department_outlined,
                  '${recipe.calories} cal',
                ),
              ],
            ),
          ),

          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  recipe.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                if (equipment.isNotEmpty) ...[
                  _equipmentPill(equipment[0]),
                  if (equipment.length > 1) ...[
                    const SizedBox(height: 10),
                    _equipmentPill(equipment[1]),
                  ],
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        builder: (_) => _buildIngredientsModal(recipe, pantry),
                      );
                    },
                    child: const Text(
                      'View Ingredients',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _handleShowDirections(recipe),
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: const Text(
                      'Show Directions',
                      style: TextStyle(fontWeight: FontWeight.w800),
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

  Widget _statPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _equipmentPill(String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          const Icon(Icons.kitchen_outlined, size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showReducedUnlockDialog({
    required RecipePreview preview,
    required int currentCarrots,
    required int maxCarrots,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Unlock Recipe?'),
          content: Text(
            'Unlock full instructions for 1 carrot?\n\n'
            'Carrots: $currentCarrots / $maxCarrots',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Unlock'),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
    bool isSmall = false,
  }) {
    final size = isSmall ? 50.0 : 64.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: AppTheme.softShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Center(
            child: Icon(icon, color: color, size: size * 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildIngredientsModal(Recipe recipe, Set<String> pantry) {
    final ids = recipe.ingredientIds.isNotEmpty
        ? recipe.ingredientIds
        : recipe.ingredients.map(_norm).toList();

    String pretty(String raw) {
      final parts = raw.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
      return parts
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }

    String stripQuantity(String value) {
      final v = value.trim();
      final stripped = v.replaceFirst(
        RegExp(r'^(?:\d+(?:\.\d+)?|\d+\/\d+)\s+[^A-Za-z]*'),
        '',
      );
      return stripped.isEmpty ? v : stripped.trim();
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ingredients Needed',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Preview only — this does not use a carrot.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          ...List.generate(recipe.ingredients.length, (index) {
            final rawKey = (index < ids.length)
                ? ids[index]
                : _norm(recipe.ingredients[index]);
            final display = (index < ids.length)
                ? pretty(ids[index])
                : pretty(stripQuantity(recipe.ingredients[index]));
            final hasIt = _pantryHas(pantry, rawKey);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: hasIt
                      ? AppTheme.successColor.withValues(alpha: 0.06)
                      : AppTheme.errorColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasIt ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: hasIt
                          ? AppTheme.successColor
                          : AppTheme.errorColor,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        display,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: hasIt
                              ? AppTheme.textPrimary
                              : AppTheme.errorColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasIt ? 'Have' : 'Missing',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: hasIt
                            ? AppTheme.successColor
                            : AppTheme.errorColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _handleShowDirections(Recipe recipe) async {
    final authUser = ref.read(authProvider).user;
    final userId = authUser?.uid;

    if (userId == null || authUser?.isAnonymous == true) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    final alreadySaved = await ref
        .read(recipeServiceProvider)
        .isRecipeSaved(userId, recipe.id);
    if (alreadySaved) {
      if (mounted) {
        _openRecipeDetail(recipe, assumeUnlocked: true, openDirections: true);
      }
      return;
    }

    if (!mounted) return;

    final profile = ref.read(userProfileProvider).value;
    final subscription = profile?.subscriptionStatus.toLowerCase() ?? 'free';
    final isPremium = subscription == 'premium';
    final hideUnlockReminder = ref.read(appStateProvider).skipUnlockReminder;

    final preview = RecipePreview(
      id: recipe.id,
      title: recipe.title,
      vibeDescription: recipe.description,
      ingredients: recipe.ingredients,
      mainIngredients: recipe.ingredients.take(5).toList(),
      imageUrl: recipe.imageUrl,
      estimatedTimeMinutes: recipe.timeMinutes,
      calories: recipe.calories,
      equipmentIcons: recipe.equipment,
      mealType: recipe.mealType,
      energyLevel: recipe.energyLevel,
      cuisine: recipe.cuisine,
      skillLevel: recipe.skillLevel,
    );

    final carrotsObj = profile?.carrots;
    final maxCarrots = carrotsObj?.max ?? 5;
    final currentCarrots = carrotsObj?.current ?? 0;
    final availableCarrots = currentCarrots;

    bool shouldProceed;
    if (isPremium) {
      shouldProceed = true;
    } else if (hideUnlockReminder) {
      shouldProceed = await _showReducedUnlockDialog(
        preview: preview,
        currentCarrots: availableCarrots,
        maxCarrots: maxCarrots,
      );
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return ConfirmUnlockDialog(
            preview: preview,
            currentCarrots: availableCarrots,
            maxCarrots: maxCarrots,
            initialDoNotShowAgain: hideUnlockReminder,
            onDoNotShowAgainChanged: (v) {
              unawaited(
                ref.read(appStateProvider.notifier).setSkipUnlockReminder(v),
              );
            },
            onCancel: () => Navigator.of(dialogContext).pop(false),
            onUnlock: () => Navigator.of(dialogContext).pop(true),
          );
        },
      );
      shouldProceed = confirmed == true;
    }

    if (!shouldProceed || !mounted) return;

    if (!isPremium) {
      final success = await ref
          .read(databaseServiceProvider)
          .deductCarrot(userId);
      if (!success) {
        if (!mounted) return;
        _showOutOfCarrots();
        return;
      }
    }

    final global = await ref
        .read(recipeServiceProvider)
        .getRecipeById(recipe.id);
    if (global == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipe is unavailable right now.')),
      );
      return;
    }

    await ref.read(recipeServiceProvider).saveRecipe(userId, global);
    if (mounted) {
      _openRecipeDetail(global, assumeUnlocked: true, openDirections: true);
    }
  }
}
