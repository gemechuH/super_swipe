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

  static const int _initialDeckTarget = 20;
  static const int _refillBatchSize = 10;

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

  String _lockKey(String userId, int energyLevel, String inputsSignature) =>
      '$userId:$energyLevel:$inputsSignature';

  Future<List<RecipePreview>> getDeck({
    required String userId,
    required int energyLevel,
    required String inputsSignature,
  }) async {
    final all = await _persistence.getUnconsumedSwipeCards(userId);
    return all
        .where((c) => c.energyLevel == energyLevel)
        .where((c) => c.inputsSignature == inputsSignature)
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
    // Gemini can return fewer unique previews than requested.
    // Keep trying (within a small cap) until we actually reach the target.
    var existing = await getDeck(
      userId: userId,
      energyLevel: energyLevel,
      inputsSignature: inputsSignature,
    );

    const maxTopUpRounds = 3;
    for (var round = 0; round < maxTopUpRounds; round++) {
      final missing = (_initialDeckTarget - existing.length).clamp(
        0,
        _initialDeckTarget,
      );
      if (missing == 0) return;

      _logInfo(
        'Ensuring initial deck (energy=$energyLevel, existing=${existing.length}, missing=$missing, round=${round + 1}/$maxTopUpRounds)',
      );

      final createdCount = await _generateAndPersist(
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

      if (createdCount <= 0) return;

      existing = await getDeck(
        userId: userId,
        energyLevel: energyLevel,
        inputsSignature: inputsSignature,
      );
    }
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
    bool force = false,
  }) async {
    // Endless deck behavior: when the user reaches 5 or fewer remaining cards,
    // generate 10 more in the background. This gives enough buffer to keep
    // swiping while generation happens.
    if (!force && remaining > 5) return false;

    final lockKey = _lockKey(userId, energyLevel, inputsSignature);
    if (_generationLocks.contains(lockKey)) {
      _logInfo('Refill skipped (already in progress) (energy=$energyLevel)');
      return false;
    }

    _logInfo('Triggering refill (energy=$energyLevel, remaining=$remaining)');

    final existing = await getDeck(
      userId: userId,
      energyLevel: energyLevel,
      inputsSignature: inputsSignature,
    );

    final createdCount = await _generateAndPersist(
      userId: userId,
      energyLevel: energyLevel,
      count: _refillBatchSize,
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

    return createdCount > 0;
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

  /// Generate full recipe with PROGRESSIVE loading (step by step)
  /// This provides much faster UX - user sees first steps within seconds.
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
    void Function(List<String> steps)? onProgressiveSteps,
  }) async {
    try {
      // Use progressive generation for faster UX
      final fullRecipe = await _aiRecipeService.generateFullRecipeProgressive(
        preview: preview,
        pantryItems: pantryItems,
        allergies: allergies,
        dietaryRestrictions: dietaryRestrictions,
        showCalories: showCalories,
        strictPantryMatch: strictPantryMatch,
        onStepsUpdate: (steps, isComplete) async {
          // Save partial steps to database as they arrive
          if (steps.isNotEmpty) {
            _logInfo(
              'Progressive update: ${steps.length} steps (complete=$isComplete)',
            );
            
            // Notify UI callback if provided
            onProgressiveSteps?.call(steps);
            
            // Persist partial progress
            await _persistence.updateRecipeInstructions(
              userId,
              recipeId: preview.id,
              instructions: steps,
              isComplete: isComplete,
            );
          }
        },
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

  Future<int> _generateAndPersist({
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
    if (count <= 0) return 0;

    final lockKey = _lockKey(userId, energyLevel, inputsSignature);
    if (_generationLocks.contains(lockKey)) {
      _logInfo(
        'Generation skipped (already in progress) (energy=$energyLevel)',
      );
      return 0;
    }
    _generationLocks.add(lockKey);

    try {
      _logInfo('Generation started (energy=$energyLevel, target=$count)');

      final created = <RecipePreview>[];
      final seenIdeaKeys = <String>{...existingCardIds};
      var remaining = count;
      const maxAttempts = 6;

      for (var attempt = 0; attempt < maxAttempts && remaining > 0; attempt++) {
        _logInfo(
          'Generation attempt ${attempt + 1}/$maxAttempts (energy=$energyLevel, remaining=$remaining)',
        );

        // Gemini can return fewer previews than requested or repeat ideas.
        // After the first attempt, request a small buffer to increase the
        // likelihood we can still reach the target unique count.
        final requestCount = (attempt == 0)
            ? remaining
            : (remaining + 3).clamp(1, count);

        final previews = await _aiRecipeService.generateRecipePreviewsBatch(
          count: requestCount,
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
            inputsSignature: inputsSignature,
            ideaKey: ideaKey,
          );
          if (exists) continue;

          created.add(
            p.copyWith(
              id: ideaKey,
              energyLevel: energyLevel,
              inputsSignature: inputsSignature,
            ),
          );
          remaining--;
          if (remaining <= 0) break;
        }
      }

      if (created.isEmpty) {
        _logWarn('Generation produced 0 unique cards (energy=$energyLevel)');
        return 0;
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
          inputsSignature: inputsSignature,
          ideaKey: card.id,
          title: card.title,
          ingredients: card.ingredients,
        );
      }

      return created.length;
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
    required String inputsSignature,
    required String ideaKey,
  });

  Future<void> writeIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String inputsSignature,
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

  /// Update instructions progressively (for streaming generation)
  Future<void> updateRecipeInstructions(
    String userId, {
    required String recipeId,
    required List<String> instructions,
    required bool isComplete,
  });
}
