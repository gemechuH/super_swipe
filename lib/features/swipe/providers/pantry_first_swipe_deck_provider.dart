import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/features/swipe/services/pantry_first_swipe_deck_service.dart';
import 'package:super_swipe/features/swipe/services/swipe_inputs_signature.dart';
import 'package:super_swipe/services/ai/ai_recipe_service.dart';
import 'package:super_swipe/services/database/database_provider.dart';
import 'package:super_swipe/services/database/database_service.dart';

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

    final pantryItems = pantryAsync.maybeWhen(
      data: (items) => items,
      orElse: () => null,
    );

    if (profile == null || pantryItems == null) return <RecipePreview>[];

    final includeBasics = profile.preferences.pantryDiscovery.includeBasics;
    final willingToShop = profile.preferences.pantryDiscovery.willingToShop;
    final signature = buildSwipeInputsSignature(
      pantryIngredientNames: pantryItems.map((p) => p.normalizedName),
      includeBasics: includeBasics,
      willingToShop: willingToShop,
    );

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
    );

    final deck = await svc.getDeck(userId: user.uid, energyLevel: energyLevel);

    unawaited(
      svc
          .maybeTriggerRefill(
            userId: user.uid,
            energyLevel: energyLevel,
            remaining: deck.length,
            pantryItems: pantryItems.map((p) => p.normalizedName).toList(),
            allergies: profile.preferences.allergies,
            dietaryRestrictions: profile.preferences.dietaryRestrictions,
            preferredCuisines: profile.preferences.preferredCuisines,
            mealType: profile.preferences.defaultMealType,
            includeBasics: includeBasics,
            willingToShop: willingToShop,
            inputsSignature: signature,
          )
          .then((didRefill) async {
            if (!didRefill) return;
            if (!ref.mounted) return;
            await refresh();
          }),
    );

    return deck;
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<RecipePreview>>().copyWithPrevious(state);
    state = await AsyncValue.guard(() => build(arg));
  }

  Future<void> maybeTriggerRefillForVisibleRemaining(int remaining) async {
    final user = ref.read(authProvider).user;
    if (user == null || user.isAnonymous == true) return;

    final profile = ref.read(userProfileProvider).value;
    final pantryItems = ref.read(pantryItemsProvider).value;

    if (profile == null || pantryItems == null) return;

    final includeBasics = profile.preferences.pantryDiscovery.includeBasics;
    final willingToShop = profile.preferences.pantryDiscovery.willingToShop;
    final signature = buildSwipeInputsSignature(
      pantryIngredientNames: pantryItems.map((p) => p.normalizedName),
      includeBasics: includeBasics,
      willingToShop: willingToShop,
    );

    final svc = ref.read(pantryFirstSwipeDeckServiceProvider);
    final didRefill = await svc.maybeTriggerRefill(
      userId: user.uid,
      energyLevel: arg,
      remaining: remaining,
      pantryItems: pantryItems.map((p) => p.normalizedName).toList(),
      allergies: profile.preferences.allergies,
      dietaryRestrictions: profile.preferences.dietaryRestrictions,
      preferredCuisines: profile.preferences.preferredCuisines,
      mealType: profile.preferences.defaultMealType,
      includeBasics: includeBasics,
      willingToShop: willingToShop,
      inputsSignature: signature,
    );

    if (!didRefill) return;
    await refresh();
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
    required String ideaKey,
  }) {
    return _db.hasIdeaKeyHistory(
      userId,
      energyLevel: energyLevel,
      ideaKey: ideaKey,
    );
  }

  @override
  Future<void> writeIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String ideaKey,
    String? title,
    List<String>? ingredients,
  }) {
    return _db.writeIdeaKeyHistory(
      userId,
      energyLevel: energyLevel,
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
}
