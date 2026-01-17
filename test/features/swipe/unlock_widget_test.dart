import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:appinio_swiper/appinio_swiper.dart';
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/core/models/user_profile.dart';
import 'package:super_swipe/core/providers/app_state_provider.dart'
  as local_app_state;
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/features/recipes/screens/recipe_detail_screen.dart';
import 'package:super_swipe/features/swipe/providers/pantry_first_swipe_deck_provider.dart';
import 'package:super_swipe/features/swipe/screens/swipe_screen.dart';
import 'package:super_swipe/features/swipe/services/pantry_first_swipe_deck_service.dart';
import 'package:super_swipe/core/providers/recipe_providers.dart';
import 'package:super_swipe/core/widgets/loading/skeleton.dart';

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

class _FakeAppStateNotifier extends local_app_state.AppStateNotifier {
  @override
  local_app_state.AppState build() {
    return const local_app_state.AppState(
      carrotCount: 5,
      unlockedRecipes: <Recipe>[],
      pantryItems: <PantryItem>[],
      isGuest: false,
      hasSeenWelcome: false,
      filterExpanded: false,
      skipUnlockReminder: false,
    );
  }

  @override
  Future<void> setSkipUnlockReminder(bool skip) async {
    state = state.copyWith(skipUnlockReminder: skip);
  }
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

UserProfile _profile({int carrots = 5}) {
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

class _FakeDeckService implements PantryFirstSwipeDeckService {
  final RecipePreview preview;
  final Recipe fullRecipe;
  int reserveCalls = 0;
  int finalizeCalls = 0;

  _FakeDeckService({required this.preview, required this.fullRecipe});

  @override
  Future<List<RecipePreview>> getDeck({
    required String userId,
    required int energyLevel,
  }) async {
    return <RecipePreview>[preview];
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
  }) async {
    reserveCalls++;
    return true;
  }

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
    finalizeCalls++;
    return fullRecipe;
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
    finalizeCalls++;
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
    await reserveUnlockPreview(
      userId: userId,
      preview: preview,
      isPremium: isPremium,
      unlockSource: unlockSource,
    );
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
}

void main() {
  testWidgets('Right swipe unlocks a preview (happy path)', (tester) async {
    final preview = const RecipePreview(
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
    );

    final fullRecipe = Recipe(
      id: 'idea_1',
      title: 'Preview One',
      imageUrl: '',
      description: 'Cozy and quick',
      ingredients: const ['chicken', 'rice', 'tomato'],
      instructions: const ['Step 1', 'Step 2'],
      ingredientIds: const ['chicken', 'rice', 'tomato'],
      energyLevel: 2,
      timeMinutes: 20,
      calories: 450,
      equipment: const ['pan'],
    );

    final fakeDeckService = _FakeDeckService(
      preview: preview,
      fullRecipe: fullRecipe,
    );

    final router = GoRouter(
      initialLocation: '/swipe',
      routes: [
        GoRoute(
          path: '/swipe',
          builder: (context, state) => const SwipeScreen(),
        ),
        GoRoute(
          path: '/recipes/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            final extra = (state.extra as Map?)?.cast<String, dynamic>();
            return RecipeDetailScreen(
              recipeId: id,
              initialRecipe: extra?['recipe'] as Recipe?,
              assumeUnlocked: extra?['assumeUnlocked'] == true,
              openDirections: extra?['openDirections'] == true,
              isGenerating: extra?['isGenerating'] == true,
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            () => _FakeAuthNotifier(_FakeUser(uid: 'u1', isAnonymous: false)),
          ),
          local_app_state.appStateProvider.overrideWith(_FakeAppStateNotifier.new),
          userProfileProvider.overrideWith((ref) => Stream.value(_profile())),
          pantryItemsProvider.overrideWith((ref) {
            return Stream.value(<PantryItem>[
              _item('chicken'),
              _item('rice'),
              _item('tomato'),
            ]);
          }),
          savedRecipesProvider.overrideWith((ref) => Stream.value(<Recipe>[])),
          pantryFirstSwipeDeckServiceProvider.overrideWithValue(
            fakeDeckService,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Preview One'), findsOneWidget);

    await tester.fling(find.byType(AppinioSwiper), const Offset(600, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Unlock Recipe'), findsOneWidget);
    await tester.tap(find.text('Unlock'));
    // The destination screen shows shimmer placeholders that continuously
    // animate, so `pumpAndSettle` would never complete.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fakeDeckService.reserveCalls, 1);
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    // New behavior: navigates immediately and shows skeleton while generating.
    expect(find.byType(SkeletonListTile), findsWidgets);
  });
}
