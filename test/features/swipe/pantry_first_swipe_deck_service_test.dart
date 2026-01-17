import 'package:flutter_test/flutter_test.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/features/swipe/services/pantry_first_swipe_deck_service.dart';
import 'package:super_swipe/features/swipe/services/swipe_inputs_signature.dart';
import 'package:super_swipe/services/ai/ai_recipe_service.dart';

class _FakePersistence implements SwipeDeckPersistence {
  final Map<String, List<RecipePreview>> _cardsByUser = {};
  final Set<String> _history = {};
  final Map<String, String> _signatureByUserEnergy = {};

  @override
  Future<List<RecipePreview>> getUnconsumedSwipeCards(String userId) async {
    return List<RecipePreview>.from(_cardsByUser[userId] ?? const []);
  }

  @override
  Future<bool> hasDeckSignatureMismatch(
    String userId, {
    required int energyLevel,
    required String inputsSignature,
  }) async {
    final cards = _cardsByUser[userId] ?? const <RecipePreview>[];
    final hasAny = cards.any((c) => c.energyLevel == energyLevel);
    if (!hasAny) return false;

    final key = '$userId:$energyLevel';
    final existing = _signatureByUserEnergy[key] ?? '';
    return existing != inputsSignature;
  }

  @override
  Future<void> clearSwipeDeck(String userId) async {
    _cardsByUser.remove(userId);
    _signatureByUserEnergy.removeWhere((k, _) => k.startsWith('$userId:'));
  }

  @override
  Future<void> upsertSwipeCards(
    String userId,
    List<RecipePreview> cards, {
    String? inputsSignature,
    String? promptVersion,
  }) async {
    final existing = _cardsByUser[userId] ?? <RecipePreview>[];
    final byId = {for (final c in existing) c.id: c};
    for (final c in cards) {
      byId[c.id] = c;
      final key = '$userId:${c.energyLevel}';
      _signatureByUserEnergy[key] = inputsSignature ?? '';
    }
    _cardsByUser[userId] = byId.values.toList(growable: false);
  }

  @override
  Future<bool> hasIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String ideaKey,
  }) async {
    return _history.contains('$userId:$energyLevel:$ideaKey');
  }

  @override
  Future<void> writeIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String ideaKey,
    String? title,
    List<String>? ingredients,
  }) async {
    _history.add('$userId:$energyLevel:$ideaKey');
  }

  @override
  Future<bool> unlockPreviewAtomically(
    String userId, {
    required Recipe fullRecipe,
    required bool isPremium,
    required String unlockSource,
  }) async {
    return true;
  }

  @override
  Future<bool> reserveUnlockPreviewAtomically(
    String userId, {
    required RecipePreview preview,
    required bool isPremium,
    required String unlockSource,
  }) async {
    return true;
  }

  @override
  Future<void> upsertUnlockedSavedRecipe(
    String userId, {
    required Recipe recipe,
    required String unlockSource,
  }) async {
    // no-op
  }
}

class _FakeAi extends AiRecipeService {
  int _counter = 0;

  @override
  Future<List<RecipePreview>> generateRecipePreviewsBatch({
    required int count,
    required List<String> pantryItems,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
    required String cravings,
    required int energyLevel,
    List<String> preferredCuisines = const [],
    String? mealType,
    bool strictPantryMatch = true,
  }) async {
    final results = <RecipePreview>[];
    for (var i = 0; i < count; i++) {
      _counter++;
      results.add(
        RecipePreview(
          id: 'tmp_$_counter',
          title: 'Recipe $_counter',
          vibeDescription: 'Test',
          ingredients: ['chicken', 'rice', 'item$_counter'],
          mainIngredients: const ['chicken', 'rice'],
          estimatedTimeMinutes: 20,
          calories: 400,
          equipmentIcons: const [],
          mealType: mealType ?? 'dinner',
          energyLevel: energyLevel,
          cuisine: 'other',
          skillLevel: 'beginner',
        ),
      );
    }
    return results;
  }
}

void main() {
  test('ensureInitialDeck generates 10 previews when empty', () async {
    final persistence = _FakePersistence();
    final ai = _FakeAi();
    final service = PantryFirstSwipeDeckService(
      persistence: persistence,
      aiRecipeService: ai,
    );

    final sig = buildSwipeInputsSignature(
      pantryIngredientNames: const ['chicken', 'rice', 'tomato'],
      includeBasics: true,
      willingToShop: false,
    );

    await service.ensureInitialDeck(
      userId: 'u1',
      energyLevel: 2,
      pantryItems: const ['chicken', 'rice', 'tomato'],
      allergies: const [],
      dietaryRestrictions: const [],
      preferredCuisines: const [],
      mealType: 'dinner',
      includeBasics: true,
      willingToShop: false,
      inputsSignature: sig,
    );

    final deck = await service.getDeck(userId: 'u1', energyLevel: 2);
    expect(deck.length, equals(10));
  });

  test(
    'ensureInitialDeck generates 10 previews per energy level (0–4)',
    () async {
      final persistence = _FakePersistence();
      final ai = _FakeAi();
      final service = PantryFirstSwipeDeckService(
        persistence: persistence,
        aiRecipeService: ai,
      );

      final sig = buildSwipeInputsSignature(
        pantryIngredientNames: const ['chicken', 'rice', 'tomato'],
        includeBasics: true,
        willingToShop: false,
      );

      for (var energy = 0; energy <= 4; energy++) {
        await service.ensureInitialDeck(
          userId: 'u1',
          energyLevel: energy,
          pantryItems: const ['chicken', 'rice', 'tomato'],
          allergies: const [],
          dietaryRestrictions: const [],
          preferredCuisines: const [],
          mealType: 'dinner',
          includeBasics: true,
          willingToShop: false,
          inputsSignature: sig,
        );

        final deck = await service.getDeck(userId: 'u1', energyLevel: energy);
        expect(deck.length, equals(10), reason: 'energy=$energy');
      }
    },
  );

  test('maybeTriggerRefill triggers when remaining <= 5 (adds 10)', () async {
    final persistence = _FakePersistence();
    final ai = _FakeAi();
    final service = PantryFirstSwipeDeckService(
      persistence: persistence,
      aiRecipeService: ai,
    );

    final sig = buildSwipeInputsSignature(
      pantryIngredientNames: const ['chicken', 'rice', 'tomato'],
      includeBasics: true,
      willingToShop: false,
    );

    await service.ensureInitialDeck(
      userId: 'u1',
      energyLevel: 2,
      pantryItems: const ['chicken', 'rice', 'tomato'],
      allergies: const [],
      dietaryRestrictions: const [],
      preferredCuisines: const [],
      mealType: 'dinner',
      includeBasics: true,
      willingToShop: false,
      inputsSignature: sig,
    );

    final did = await service.maybeTriggerRefill(
      userId: 'u1',
      energyLevel: 2,
      remaining: 5,
      pantryItems: const ['chicken', 'rice', 'tomato'],
      allergies: const [],
      dietaryRestrictions: const [],
      preferredCuisines: const [],
      mealType: 'dinner',
      includeBasics: true,
      willingToShop: false,
      inputsSignature: sig,
    );

    expect(did, isTrue);

    final deck = await service.getDeck(userId: 'u1', energyLevel: 2);
    expect(deck.length, equals(20));
  });
}
