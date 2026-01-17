import 'package:flutter_test/flutter_test.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/features/swipe/services/pantry_first_swipe_deck_service.dart';
import 'package:super_swipe/services/ai/ai_recipe_service.dart';

class _FakeSwipeDeckPersistence implements SwipeDeckPersistence {
  int reserveCalls = 0;
  int finalizeCalls = 0;

  @override
  Future<List<RecipePreview>> getUnconsumedSwipeCards(String userId) async =>
      const <RecipePreview>[];

  @override
  Future<bool> hasDeckSignatureMismatch(
    String userId, {
    required int energyLevel,
    required String inputsSignature,
  }) async => false;

  @override
  Future<void> clearSwipeDeck(String userId) async {}

  @override
  Future<void> upsertSwipeCards(
    String userId,
    List<RecipePreview> cards, {
    String? inputsSignature,
    String? promptVersion,
  }) async {}

  @override
  Future<bool> hasIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String ideaKey,
  }) async => false;

  @override
  Future<void> writeIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String ideaKey,
    String? title,
    List<String>? ingredients,
  }) async {}

  @override
  Future<bool> unlockPreviewAtomically(
    String userId, {
    required Recipe fullRecipe,
    required bool isPremium,
    required String unlockSource,
  }) async {
    // Legacy path not used.
    return true;
  }

  @override
  Future<bool> reserveUnlockPreviewAtomically(
    String userId, {
    required RecipePreview preview,
    required bool isPremium,
    required String unlockSource,
  }) async {
    reserveCalls++;
    return true;
  }

  @override
  Future<void> upsertUnlockedSavedRecipe(
    String userId, {
    required Recipe recipe,
    required String unlockSource,
  }) async {
    finalizeCalls++;
  }
}

class _FailingAiRecipeService extends AiRecipeService {
  @override
  Future<Recipe> generateFullRecipe({
    required RecipePreview preview,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required bool showCalories,
    bool strictPantryMatch = true,
  }) {
    throw Exception('AI failed');
  }
}

void main() {
  test(
    'Unlock reserves first; does not finalize if AI generation fails',
    () async {
      final persistence = _FakeSwipeDeckPersistence();
      final svc = PantryFirstSwipeDeckService(
        persistence: persistence,
        aiRecipeService: _FailingAiRecipeService(),
      );

      const preview = RecipePreview(
        id: 'idea_1',
        title: 'Test Preview',
        vibeDescription: 'Quick',
        mainIngredients: ['chicken'],
        ingredients: ['chicken', 'rice'],
        estimatedTimeMinutes: 20,
        calories: 400,
        energyLevel: 2,
        cuisine: 'other',
        skillLevel: 'beginner',
      );

      await expectLater(
        () => svc.unlockPreview(
          userId: 'u1',
          preview: preview,
          pantryItems: const ['chicken', 'rice', 'tomato'],
          allergies: const [],
          dietaryRestrictions: const [],
          showCalories: true,
          strictPantryMatch: true,
          isPremium: false,
          unlockSource: 'show_directions',
        ),
        throwsA(isA<Exception>()),
      );

      expect(persistence.reserveCalls, 1);
      expect(persistence.finalizeCalls, 0);
    },
  );
}
