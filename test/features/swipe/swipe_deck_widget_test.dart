import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/core/models/user_profile.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/features/swipe/providers/pantry_first_swipe_deck_provider.dart';
import 'package:super_swipe/features/swipe/screens/swipe_screen.dart';
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

UserProfile _profile() {
  return UserProfile(
    uid: 'u1',
    email: 'u1@example.com',
    displayName: 'User',
    isAnonymous: false,
    carrots: const Carrots(current: 5, max: 5),
    preferences: const UserPreferences(),
    appState: const AppState(),
    stats: const UserStats(),
  );
}

class _FakeDeckService implements PantryFirstSwipeDeckService {
  final List<RecipePreview> _cards;

  _FakeDeckService(this._cards);

  @override
  Future<List<RecipePreview>> getDeck({
    required String userId,
    required int energyLevel,
  }) async {
    return _cards
        .where((c) => c.energyLevel == energyLevel)
        .toList(growable: false);
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
    // no-op
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
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('Swipe renders AI previews deck (not global recipes)', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/swipe',
      routes: [
        GoRoute(
          path: '/swipe',
          builder: (context, state) => const SwipeScreen(),
        ),
      ],
    );

    final fakeDeck = <RecipePreview>[
      const RecipePreview(
        id: 'idea_1',
        title: 'Preview One',
        vibeDescription: 'Cozy and quick',
        mainIngredients: ['chicken', 'rice'],
        ingredients: ['chicken', 'rice', 'tomato'],
        imageUrl: 'assets/images/onboarding_1.png',
        estimatedTimeMinutes: 20,
        calories: 450,
        energyLevel: 2,
        cuisine: 'other',
        skillLevel: 'beginner',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            () => _FakeAuthNotifier(_FakeUser(uid: 'u1', isAnonymous: false)),
          ),
          userProfileProvider.overrideWith((ref) => Stream.value(_profile())),
          pantryItemsProvider.overrideWith((ref) {
            return Stream.value(<PantryItem>[
              _item('chicken'),
              _item('rice'),
              _item('tomato'),
            ]);
          }),
          pantryFirstSwipeDeckServiceProvider.overrideWithValue(
            _FakeDeckService(fakeDeck),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Preview One'), findsOneWidget);
    expect(find.text('Cozy and quick'), findsOneWidget);
  });
}
