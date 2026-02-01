import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/features/swipe/providers/swipe_filters_provider.dart';
import 'package:super_swipe/features/swipe/services/pantry_first_swipe_deck_service.dart';
import 'package:super_swipe/features/swipe/services/swipe_inputs_signature.dart';
import 'package:super_swipe/services/ai/ai_recipe_service.dart';
import 'package:super_swipe/services/database/database_provider.dart';
import 'package:super_swipe/services/database/database_service.dart';

void _logProvider(String message) {
  if (kDebugMode) {
    developer.log(message, name: 'SwipeDeckProvider');
    debugPrint('[SwipeDeckProvider] $message');
  }
}

final pantryFirstSwipeDeckServiceProvider =
    Provider<PantryFirstSwipeDeckService>((ref) {
      final db = ref.watch(databaseServiceProvider);
      final persistence = DatabaseSwipeDeckPersistence(db);
      final ai = AiRecipeService();
      return PantryFirstSwipeDeckService(
        persistence: persistence,
        aiRecipeService: ai,
      );
    });

/// Tracks whether a background refill is in progress for each energy level.
/// Key: energyLevel, Value: isRefilling
final swipeDeckRefillingProvider = StateProvider.family<bool, int>(
  (ref, energyLevel) => false,
);

/// Tracks the last time a refill was attempted (to prevent rapid retries).
/// Key: energyLevel, Value: DateTime of last attempt
final _swipeDeckLastRefillAttemptProvider =
    StateProvider.family<DateTime?, int>((ref, energyLevel) => null);

final pantryFirstSwipeDeckProvider =
    AutoDisposeAsyncNotifierProviderFamily<
      PantryFirstSwipeDeckController,
      List<RecipePreview>,
      int
    >(PantryFirstSwipeDeckController.new);

class PantryFirstSwipeDeckController
    extends AutoDisposeFamilyAsyncNotifier<List<RecipePreview>, int> {
  @override
  Future<List<RecipePreview>> build(int energyLevel) async {
    final user = ref.watch(authProvider).user;
    if (user == null || user.isAnonymous == true) return <RecipePreview>[];

    final profile = ref.watch(userProfileProvider).value;
    final pantryAsync = ref.watch(pantryItemsProvider);
    
    // Watch swipe filters - this is the key integration!
    final swipeFilters = ref.watch(swipeFiltersProvider);

    final pantryItems = pantryAsync.maybeWhen(
      data: (items) => items,
      orElse: () => null,
    );

    if (profile == null || pantryItems == null) return <RecipePreview>[];

    final includeBasics = profile.preferences.pantryDiscovery.includeBasics;
    final willingToShop = profile.preferences.pantryDiscovery.willingToShop;
    
    // Include swipe filters in signature so deck regenerates when filters change
    final signature = buildSwipeInputsSignature(
      pantryIngredientNames: pantryItems.map((p) => p.normalizedName),
      includeBasics: includeBasics,
      willingToShop: willingToShop,
      allergies: profile.preferences.allergies,
      dietaryRestrictions: profile.preferences.dietaryRestrictions,
      preferredCuisines: profile.preferences.preferredCuisines,
      mealType: profile.preferences.defaultMealType,
      swipeFilters: swipeFilters,
    );
    
    if (kDebugMode) {
      _logProvider('Build with filters: $swipeFilters, signature: ${signature.substring(0, 16)}');
    }

    var isDisposed = false;
    ref.onDispose(() => isDisposed = true);

    final svc = ref.watch(pantryFirstSwipeDeckServiceProvider);

    await svc.ensureInitialDeck(
      userId: user.uid,
      energyLevel: energyLevel,
      pantryItems: pantryItems.map((p) => p.normalizedName).toList(),
      allergies: profile.preferences.allergies,
      dietaryRestrictions: profile.preferences.dietaryRestrictions,
      preferredCuisines: profile.preferences.preferredCuisines,
      mealType: profile.preferences.defaultMealType,
      includeBasics: includeBasics,
      willingToShop: willingToShop,
      inputsSignature: signature,
      swipeFilters: swipeFilters,
    );

    final deck = await svc.getDeck(
      userId: user.uid,
      energyLevel: energyLevel,
      inputsSignature: signature,
    );

    if (isDisposed) return deck;

    return deck;
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<RecipePreview>>().copyWithPrevious(state);
    state = await AsyncValue.guard(() => build(arg));
  }

  Future<void> maybeTriggerRefillForVisibleRemaining(int remaining) async {
    // Trigger when the user remains with 5 or fewer un-swiped cards.
    // This gives enough buffer for generation to complete before running out.
    if (remaining > 5) return;

    await _doRefill(force: false);
  }

  /// Triggers refill when UI has no visible cards - called from UI as a failsafe.
  /// Note: UI may have dismissed cards locally that provider doesn't know about,
  /// so we don't check provider deck state here - just trust the UI.
  Future<void> triggerRefillIfEmpty() async {
    final isAlreadyRefilling = ref.read(swipeDeckRefillingProvider(arg));
    if (isAlreadyRefilling) {
      // Even if refilling, ensure we refresh UI after it completes
      return;
    }

    // Check cooldown to prevent rapid retries (3 second cooldown - reduced from 5)
    final lastAttempt = ref.read(_swipeDeckLastRefillAttemptProvider(arg));
    if (lastAttempt != null) {
      final elapsed = DateTime.now().difference(lastAttempt);
      if (elapsed.inSeconds < 3) {
        // Cooldown active - but still try to refresh state
        // This ensures UI updates even if generation was recent
        await refresh();
        return;
      }
    }

    await _doRefill(force: true);
  }

  /// Forces a refill immediately, bypassing cooldown. Use for user-initiated actions.
  Future<void> forceRefillNow() async {
    final isAlreadyRefilling = ref.read(swipeDeckRefillingProvider(arg));
    if (isAlreadyRefilling) return;

    // Clear cooldown to allow immediate generation
    ref.read(_swipeDeckLastRefillAttemptProvider(arg).notifier).state = null;
    await _doRefill(force: true);
  }

  Future<void> _doRefill({required bool force}) async {
    _logProvider('_doRefill called (energy=$arg, force=$force)');

    final user = ref.read(authProvider).user;
    if (user == null || user.isAnonymous == true) {
      _logProvider('_doRefill aborted: no valid user');
      return;
    }

    final profile = ref.read(userProfileProvider).value;
    final pantryItems = ref.read(pantryItemsProvider).value;
    final swipeFilters = ref.read(swipeFiltersProvider);
    
    if (profile == null || pantryItems == null) {
      _logProvider('_doRefill aborted: missing profile or pantry');
      return;
    }

    // Check if already refilling
    final isAlreadyRefilling = ref.read(swipeDeckRefillingProvider(arg));
    if (isAlreadyRefilling) {
      _logProvider('_doRefill aborted: already refilling');
      return;
    }

    final includeBasics = profile.preferences.pantryDiscovery.includeBasics;
    final willingToShop = profile.preferences.pantryDiscovery.willingToShop;
    final signature = buildSwipeInputsSignature(
      pantryIngredientNames: pantryItems.map((p) => p.normalizedName),
      includeBasics: includeBasics,
      willingToShop: willingToShop,
      allergies: profile.preferences.allergies,
      dietaryRestrictions: profile.preferences.dietaryRestrictions,
      preferredCuisines: profile.preferences.preferredCuisines,
      mealType: profile.preferences.defaultMealType,
      swipeFilters: swipeFilters,
    );

    // Set refilling state to true and record attempt time
    _logProvider('Starting refill (energy=$arg) with filters: $swipeFilters');
    ref.read(swipeDeckRefillingProvider(arg).notifier).state = true;
    ref.read(_swipeDeckLastRefillAttemptProvider(arg).notifier).state =
        DateTime.now();

    try {
      final svc = ref.read(pantryFirstSwipeDeckServiceProvider);
      final result = await svc.maybeTriggerRefill(
        userId: user.uid,
        energyLevel: arg,
        remaining: 0, // Always pass 0 to ensure generation happens
        pantryItems: pantryItems.map((p) => p.normalizedName).toList(),
        allergies: profile.preferences.allergies,
        dietaryRestrictions: profile.preferences.dietaryRestrictions,
        preferredCuisines: profile.preferences.preferredCuisines,
        mealType: profile.preferences.defaultMealType,
        includeBasics: includeBasics,
        willingToShop: willingToShop,
        inputsSignature: signature,
        force: force,
        swipeFilters: swipeFilters,
      );

      _logProvider('Refill service returned: $result (energy=$arg)');

      // Always refresh after generation attempt to pick up any new cards
      _logProvider('Refreshing deck state (energy=$arg)');
      await refresh();

      // Log final deck state
      final finalDeck = state.value ?? [];
      _logProvider(
        'After refresh: deck has ${finalDeck.length} cards (energy=$arg)',
      );
    } catch (e, st) {
      _logProvider('Refill failed: $e');
      if (kDebugMode) {
        debugPrint('Refill stacktrace: $st');
      }
    } finally {
      // Always reset refilling state
      _logProvider('Refill complete, resetting isRefilling (energy=$arg)');
      ref.read(swipeDeckRefillingProvider(arg).notifier).state = false;
    }
  }

  Future<void> topUpNow() async {
    // Force a refill regardless of current deck state
    await _doRefill(force: true);
  }

  Future<void> hardRefresh() async {
    // Back-compat: treat hard-refresh as a top-up (do not clear history).
    await topUpNow();
  }

  Future<void> reserveUnlockPreview(
    RecipePreview preview, {
    required String unlockSource,
  }) async {
    final user = ref.read(authProvider).user;
    if (user == null || user.isAnonymous == true) {
      throw Exception('Sign in required');
    }

    final profile = ref.read(userProfileProvider).value;
    if (profile == null) {
      throw Exception('Missing user profile');
    }

    final subscription = profile.subscriptionStatus.toLowerCase();
    final isPremium = subscription == 'premium';

    final svc = ref.read(pantryFirstSwipeDeckServiceProvider);
    final ok = await svc.reserveUnlockPreview(
      userId: user.uid,
      preview: preview,
      isPremium: isPremium,
      unlockSource: unlockSource,
    );

    if (!ok) {
      throw const OutOfCarrotsException();
    }
  }

  Future<void> generateAndFinalizeUnlockPreview(
    RecipePreview preview, {
    required String unlockSource,
  }) async {
    final user = ref.read(authProvider).user;
    if (user == null || user.isAnonymous == true) return;

    final profile = ref.read(userProfileProvider).value;
    final pantryItems = ref.read(pantryItemsProvider).value;
    if (profile == null || pantryItems == null) return;

    final subscription = profile.subscriptionStatus.toLowerCase();
    final isPremium = subscription == 'premium';
    final willingToShop = profile.preferences.pantryDiscovery.willingToShop;

    final svc = ref.read(pantryFirstSwipeDeckServiceProvider);
    await svc.generateAndFinalizeUnlockedPreview(
      userId: user.uid,
      preview: preview,
      pantryItems: pantryItems.map((p) => p.normalizedName).toList(),
      allergies: profile.preferences.allergies,
      dietaryRestrictions: profile.preferences.dietaryRestrictions,
      showCalories: true,
      strictPantryMatch: !willingToShop,
      isPremium: isPremium,
      unlockSource: unlockSource,
    );
    unawaited(refresh());
  }

  Future<Recipe> unlockPreview(
    RecipePreview preview, {
    required String unlockSource,
  }) async {
    final user = ref.read(authProvider).user;
    if (user == null || user.isAnonymous == true) {
      throw Exception('Sign in required');
    }

    final profile = ref.read(userProfileProvider).value;
    final pantryItems = ref.read(pantryItemsProvider).value;

    if (profile == null || pantryItems == null) {
      throw Exception('Missing user profile or pantry');
    }

    final subscription = profile.subscriptionStatus.toLowerCase();
    final isPremium = subscription == 'premium';
    final willingToShop = profile.preferences.pantryDiscovery.willingToShop;

    await reserveUnlockPreview(preview, unlockSource: unlockSource);

    final svc = ref.read(pantryFirstSwipeDeckServiceProvider);
    final recipe = await svc.generateFullRecipeAndPersist(
      userId: user.uid,
      preview: preview,
      pantryItems: pantryItems.map((p) => p.normalizedName).toList(),
      allergies: profile.preferences.allergies,
      dietaryRestrictions: profile.preferences.dietaryRestrictions,
      showCalories: true,
      strictPantryMatch: !willingToShop,
      isPremium: isPremium,
      unlockSource: unlockSource,
    );

    unawaited(refresh());
    return recipe;
  }
}

class DatabaseSwipeDeckPersistence implements SwipeDeckPersistence {
  final DatabaseService _db;

  DatabaseSwipeDeckPersistence(this._db);

  @override
  Future<List<RecipePreview>> getUnconsumedSwipeCards(String userId) {
    return _db.getUnconsumedSwipeCards(userId);
  }

  @override
  Future<bool> hasDeckSignatureMismatch(
    String userId, {
    required int energyLevel,
    required String inputsSignature,
  }) {
    return _db.hasSwipeDeckSignatureMismatch(
      userId,
      energyLevel: energyLevel,
      inputsSignature: inputsSignature,
    );
  }

  @override
  Future<void> clearSwipeDeck(String userId) {
    return _db.clearSwipeDeck(userId);
  }

  @override
  Future<void> upsertSwipeCards(
    String userId,
    List<RecipePreview> cards, {
    String? inputsSignature,
    String? promptVersion,
  }) {
    return _db.upsertSwipeCards(
      userId,
      cards,
      inputsSignature: inputsSignature,
      promptVersion: promptVersion,
    );
  }

  @override
  Future<bool> hasIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String inputsSignature,
    required String ideaKey,
  }) {
    return _db.hasIdeaKeyHistory(
      userId,
      energyLevel: energyLevel,
      inputsSignature: inputsSignature,
      ideaKey: ideaKey,
    );
  }

  @override
  Future<void> writeIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String inputsSignature,
    required String ideaKey,
    String? title,
    List<String>? ingredients,
  }) {
    return _db.writeIdeaKeyHistory(
      userId,
      energyLevel: energyLevel,
      inputsSignature: inputsSignature,
      ideaKey: ideaKey,
      title: title,
      ingredients: ingredients,
    );
  }

  @override
  Future<bool> unlockPreviewAtomically(
    String userId, {
    required Recipe fullRecipe,
    required bool isPremium,
    required String unlockSource,
  }) {
    return _db.unlockSwipePreview(
      userId: userId,
      recipe: fullRecipe,
      isPremium: isPremium,
      unlockSource: unlockSource,
    );
  }

  @override
  Future<bool> reserveUnlockPreviewAtomically(
    String userId, {
    required RecipePreview preview,
    required bool isPremium,
    required String unlockSource,
  }) {
    return _db.reserveSwipePreviewUnlock(
      userId: userId,
      preview: preview,
      isPremium: isPremium,
      unlockSource: unlockSource,
    );
  }

  @override
  Future<void> upsertUnlockedSavedRecipe(
    String userId, {
    required Recipe recipe,
    required String unlockSource,
  }) {
    return _db.upsertUnlockedSavedRecipeForSwipePreview(
      userId: userId,
      recipe: recipe,
      unlockSource: unlockSource,
    );
  }

  @override
  Future<void> updateRecipeInstructions(
    String userId, {
    required String recipeId,
    required List<String> instructions,
    required bool isComplete,
  }) {
    return _db.updateSavedRecipeInstructions(
      userId: userId,
      recipeId: recipeId,
      instructions: instructions,
    );
  }
}
