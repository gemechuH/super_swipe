import 'dart:async';
import 'dart:developer' as developer;

import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/features/swipe/services/idea_key.dart';
import 'package:super_swipe/features/swipe/services/swipe_inputs_signature.dart';
import 'package:super_swipe/services/ai/ai_recipe_service.dart';

class OutOfCarrotsException implements Exception {
  final String message;

  const OutOfCarrotsException([this.message = 'Out of carrots']);

  @override
  String toString() => 'OutOfCarrotsException: $message';
}

class PantryFirstSwipeDeckService {
  final SwipeDeckPersistence _persistence;
  final AiRecipeService _aiRecipeService;

  static final Set<String> _generationLocks = <String>{};

  const PantryFirstSwipeDeckService({
    required SwipeDeckPersistence persistence,
    required AiRecipeService aiRecipeService,
  }) : _persistence = persistence,
       _aiRecipeService = aiRecipeService;

  void _logInfo(String message) {
    developer.log(message, name: 'PantryFirstSwipeDeckService');
  }

  void _logWarn(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'PantryFirstSwipeDeckService',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _logError(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'PantryFirstSwipeDeckService',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }

  String _lockKey(String userId, int energyLevel) => '$userId:$energyLevel';

  Future<List<RecipePreview>> getDeck({
    required String userId,
    required int energyLevel,
  }) async {
    final all = await _persistence.getUnconsumedSwipeCards(userId);
    return all
        .where((c) => c.energyLevel == energyLevel)
        .toList(growable: false);
  }

  Future<void> ensureInitialDeck({
    required String userId,
    required int energyLevel,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required List<String> preferredCuisines,
    required String mealType,
    required bool includeBasics,
    required bool willingToShop,
    required String inputsSignature,
  }) async {
    final mismatch = await _persistence.hasDeckSignatureMismatch(
      userId,
      energyLevel: energyLevel,
      inputsSignature: inputsSignature,
    );
    if (mismatch) {
      _logInfo('Deck signature mismatch; clearing deck (energy=$energyLevel)');
      await _persistence.clearSwipeDeck(userId);
    }

    final existing = await getDeck(userId: userId, energyLevel: energyLevel);
    if (existing.isNotEmpty) return;

    const missing = 6;

    _logInfo(
      'Ensuring initial deck (energy=$energyLevel, existing=${existing.length}, missing=$missing)',
    );

    await _generateAndPersist(
      userId: userId,
      energyLevel: energyLevel,
      count: missing,
      pantryItems: pantryItems,
      allergies: allergies,
      dietaryRestrictions: dietaryRestrictions,
      preferredCuisines: preferredCuisines,
      mealType: mealType,
      includeBasics: includeBasics,
      willingToShop: willingToShop,
      inputsSignature: inputsSignature,
      existingCardIds: existing.map((e) => e.id).toSet(),
    );
  }

  Future<bool> maybeTriggerRefill({
    required String userId,
    required int energyLevel,
    required int remaining,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required List<String> preferredCuisines,
    required String mealType,
    required bool includeBasics,
    required bool willingToShop,
    required String inputsSignature,
  }) async {
    if (remaining > 3) return false;

    final lockKey = _lockKey(userId, energyLevel);
    if (_generationLocks.contains(lockKey)) {
      _logInfo('Refill skipped (already in progress) (energy=$energyLevel)');
      return false;
    }

    _logInfo('Triggering refill (energy=$energyLevel, remaining=$remaining)');

    final existing = await getDeck(userId: userId, energyLevel: energyLevel);

    await _generateAndPersist(
      userId: userId,
      energyLevel: energyLevel,
      count: 5,
      pantryItems: pantryItems,
      allergies: allergies,
      dietaryRestrictions: dietaryRestrictions,
      preferredCuisines: preferredCuisines,
      mealType: mealType,
      includeBasics: includeBasics,
      willingToShop: willingToShop,
      inputsSignature: inputsSignature,
      existingCardIds: existing.map((e) => e.id).toSet(),
    );

    return true;
  }

  Future<Recipe> unlockPreview({
    required String userId,
    required RecipePreview preview,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required bool showCalories,
    required bool strictPantryMatch,
    required bool isPremium,
    required String unlockSource,
  }) async {
    // Back-compat: reserve first, then generate and persist.
    final ok = await reserveUnlockPreview(
      userId: userId,
      preview: preview,
      isPremium: isPremium,
      unlockSource: unlockSource,
    );

    if (!ok) {
      _logWarn(
        'Unlock rejected (out of carrots) (energy=${preview.energyLevel})',
      );
      throw const OutOfCarrotsException();
    }

    return generateFullRecipeAndPersist(
      userId: userId,
      preview: preview,
      pantryItems: pantryItems,
      allergies: allergies,
      dietaryRestrictions: dietaryRestrictions,
      showCalories: showCalories,
      strictPantryMatch: strictPantryMatch,
      isPremium: isPremium,
      unlockSource: unlockSource,
    );
  }

  Future<bool> reserveUnlockPreview({
    required String userId,
    required RecipePreview preview,
    required bool isPremium,
    required String unlockSource,
  }) async {
    try {
      final ok = await _persistence.reserveUnlockPreviewAtomically(
        userId,
        preview: preview,
        isPremium: isPremium,
        unlockSource: unlockSource,
      );

      if (!ok) {
        _logWarn(
          'Reserve rejected (out of carrots) (energy=${preview.energyLevel})',
        );
        return false;
      }

      _logInfo('Reserve succeeded (energy=${preview.energyLevel})');
      return true;
    } catch (e, st) {
      _logError(
        'Reserve failed (energy=${preview.energyLevel})',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<Recipe> generateFullRecipeAndPersist({
    required String userId,
    required RecipePreview preview,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required bool showCalories,
    required bool strictPantryMatch,
    required bool isPremium,
    required String unlockSource,
  }) async {
    try {
      final fullRecipe = await _aiRecipeService.generateFullRecipe(
        preview: preview,
        pantryItems: pantryItems,
        allergies: allergies,
        dietaryRestrictions: dietaryRestrictions,
        showCalories: showCalories,
        strictPantryMatch: strictPantryMatch,
      );

      await _persistence.upsertUnlockedSavedRecipe(
        userId,
        recipe: fullRecipe,
        unlockSource: unlockSource,
      );

      _logInfo('Recipe generation persisted (energy=${preview.energyLevel})');
      return fullRecipe;
    } catch (e, st) {
      _logError(
        'Recipe generation failed (energy=${preview.energyLevel})',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<void> generateAndFinalizeUnlockedPreview({
    required String userId,
    required RecipePreview preview,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required bool showCalories,
    required bool strictPantryMatch,
    required bool isPremium,
    required String unlockSource,
  }) async {
    await generateFullRecipeAndPersist(
      userId: userId,
      preview: preview,
      pantryItems: pantryItems,
      allergies: allergies,
      dietaryRestrictions: dietaryRestrictions,
      showCalories: showCalories,
      strictPantryMatch: strictPantryMatch,
      isPremium: isPremium,
      unlockSource: unlockSource,
    );
  }

  Future<void> _generateAndPersist({
    required String userId,
    required int energyLevel,
    required int count,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required List<String> preferredCuisines,
    required String mealType,
    required bool includeBasics,
    required bool willingToShop,
    required String inputsSignature,
    required Set<String> existingCardIds,
  }) async {
    if (count <= 0) return;

    final lockKey = _lockKey(userId, energyLevel);
    if (_generationLocks.contains(lockKey)) {
      _logInfo(
        'Generation skipped (already in progress) (energy=$energyLevel)',
      );
      return;
    }
    _generationLocks.add(lockKey);

    try {
      _logInfo('Generation started (energy=$energyLevel, target=$count)');

      final created = <RecipePreview>[];
      final seenIdeaKeys = <String>{...existingCardIds};
      var remaining = count;
      const maxAttempts = 3;

      for (var attempt = 0; attempt < maxAttempts && remaining > 0; attempt++) {
        _logInfo(
          'Generation attempt ${attempt + 1}/$maxAttempts (energy=$energyLevel, remaining=$remaining)',
        );
        final previews = await _aiRecipeService.generateRecipePreviewsBatch(
          count: remaining,
          pantryItems: pantryItems,
          allergies: allergies,
          dietaryRestrictions: dietaryRestrictions,
          cravings: '',
          energyLevel: energyLevel,
          preferredCuisines: preferredCuisines,
          mealType: mealType,
          strictPantryMatch: !willingToShop,
        );

        for (final p in previews) {
          final ideaKey = buildIdeaKey(
            energyLevel: energyLevel,
            title: p.title,
            ingredients: p.ingredients,
          );

          if (seenIdeaKeys.contains(ideaKey)) continue;
          seenIdeaKeys.add(ideaKey);

          final exists = await _persistence.hasIdeaKeyHistory(
            userId,
            energyLevel: energyLevel,
            ideaKey: ideaKey,
          );
          if (exists) continue;

          created.add(p.copyWith(id: ideaKey, energyLevel: energyLevel));
          remaining--;
          if (remaining <= 0) break;
        }
      }

      if (created.isEmpty) {
        _logWarn('Generation produced 0 unique cards (energy=$energyLevel)');
        return;
      }

      await _persistence.upsertSwipeCards(
        userId,
        created,
        inputsSignature: inputsSignature,
        promptVersion: kPantryFirstSwipePromptVersion,
      );

      _logInfo(
        'Generation persisted (energy=$energyLevel, created=${created.length})',
      );

      for (final card in created) {
        await _persistence.writeIdeaKeyHistory(
          userId,
          energyLevel: energyLevel,
          ideaKey: card.id,
          title: card.title,
          ingredients: card.ingredients,
        );
      }
    } finally {
      _generationLocks.remove(lockKey);
    }
  }
}

abstract class SwipeDeckPersistence {
  Future<List<RecipePreview>> getUnconsumedSwipeCards(String userId);

  Future<bool> hasDeckSignatureMismatch(
    String userId, {
    required int energyLevel,
    required String inputsSignature,
  });

  Future<void> clearSwipeDeck(String userId);

  Future<void> upsertSwipeCards(
    String userId,
    List<RecipePreview> cards, {
    String? inputsSignature,
    String? promptVersion,
  });

  Future<bool> hasIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String ideaKey,
  });

  Future<void> writeIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String ideaKey,
    String? title,
    List<String>? ingredients,
  });

  Future<bool> unlockPreviewAtomically(
    String userId, {
    required Recipe fullRecipe,
    required bool isPremium,
    required String unlockSource,
  });

  Future<bool> reserveUnlockPreviewAtomically(
    String userId, {
    required RecipePreview preview,
    required bool isPremium,
    required String unlockSource,
  });

  Future<void> upsertUnlockedSavedRecipe(
    String userId, {
    required Recipe recipe,
    required String unlockSource,
  });
}
