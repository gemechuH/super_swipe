import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/core/models/user_profile.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/features/swipe/providers/pantry_first_swipe_deck_provider.dart';
import 'package:super_swipe/features/swipe/services/pantry_first_swipe_deck_service.dart';

class _FakeUser extends Fake implements User {
  @override
  final String uid;

  @override
  final bool isAnonymous;

  _FakeUser({required this.uid, required this.isAnonymous});
}

class _FakeAuthNotifier extends AuthNotifier {
  final User? _user;

  _FakeAuthNotifier(this._user);

  @override
  AuthState build() => AuthState(user: _user);
}

PantryItem _item(String name) {
  final now = DateTime(2026, 1, 1);
  return PantryItem(
    id: name,
    userId: 'u1',
    name: name,
    normalizedName: name.toLowerCase().trim(),
    category: 'other',
    quantity: 1,
    addedAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

UserProfile _profile({required int carrots}) {
  return UserProfile(
    uid: 'u1',
    email: 'u1@example.com',
    displayName: 'User',
    isAnonymous: false,
    carrots: Carrots(current: carrots, max: 5),
    preferences: const UserPreferences(),
    appState: const AppState(),
    stats: const UserStats(),
  );
}

class _CountingDeckService implements PantryFirstSwipeDeckService {
  int ensureInitialDeckCalls = 0;

  @override
  Future<List<RecipePreview>> getDeck({
    required String userId,
    required int energyLevel,
  }) async {
    return <RecipePreview>[
      RecipePreview(
        id: 'p1',
        title: 'Preview',
        vibeDescription: 'Vibe',
        ingredients: const ['a', 'b'],
        mainIngredients: const ['a'],
        imageUrl: null,
        estimatedTimeMinutes: 10,
        calories: 100,
        equipmentIcons: const ['pot'],
        mealType: 'dinner',
        cuisine: 'any',
        skillLevel: 'easy',
        energyLevel: energyLevel,
      ),
    ];
  }

  @override
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
    ensureInitialDeckCalls++;
  }

  @override
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
  }) async => false;

  @override
  Future<bool> reserveUnlockPreview({
    required String userId,
    required RecipePreview preview,
    required bool isPremium,
    required String unlockSource,
  }) async => true;

  @override
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
    throw UnimplementedError();
  }

  @override
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
    // no-op
  }

  @override
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
  }) {
    throw UnimplementedError();
  }
}

void main() {
  test(
    'PantryFirstSwipeDeckProvider rebuilds when carrots update externally',
    () async {
      final profileController = StreamController<UserProfile?>.broadcast();
      final fakeDeckService = _CountingDeckService();

      addTearDown(() async {
        await profileController.close();
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _FakeAuthNotifier(_FakeUser(uid: 'u1', isAnonymous: false)),
          ),
          userProfileProvider.overrideWith((ref) => profileController.stream),
          pantryItemsProvider.overrideWith(
            (ref) =>
                Stream.value(<PantryItem>[_item('chicken'), _item('rice')]),
          ),
          pantryFirstSwipeDeckServiceProvider.overrideWithValue(
            fakeDeckService,
          ),
        ],
      );

      addTearDown(container.dispose);

      // Keep the family provider alive for the test duration.
      final sub = container.listen(
        pantryFirstSwipeDeckProvider(0),
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      profileController.add(_profile(carrots: 0));

      await container.read(userProfileProvider.future);
      await container.read(pantryItemsProvider.future);
      await container.read(pantryFirstSwipeDeckProvider(0).future);

      final initialCalls = fakeDeckService.ensureInitialDeckCalls;
      expect(initialCalls, greaterThan(0));

      // Simulate an external weekly reset (0 -> 5) coming in via the live profile stream.
      profileController.add(_profile(carrots: 5));

      await pumpUntil(
        () => fakeDeckService.ensureInitialDeckCalls > initialCalls,
      );

      expect(fakeDeckService.ensureInitialDeckCalls, greaterThan(initialCalls));
    },
  );
}

Future<void> pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('pumpUntil timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
