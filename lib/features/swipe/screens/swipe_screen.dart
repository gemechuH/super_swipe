import 'dart:async';

import 'package:appinio_swiper/appinio_swiper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/providers/app_state_provider.dart';
import 'package:super_swipe/core/providers/recipe_providers.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';

import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/core/widgets/dialogs/confirm_unlock_dialog.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/services/database/database_provider.dart';
import 'package:super_swipe/services/ai/ai_recipe_service.dart';
import 'package:super_swipe/services/image/image_search_service.dart';

class SwipeScreen extends ConsumerStatefulWidget {
  const SwipeScreen({super.key});

  @override
  ConsumerState<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends ConsumerState<SwipeScreen> {
  final AppinioSwiperController _swiperController = AppinioSwiperController();
  int _selectedEnergyLevel = 2; // Default to 'Okay'
  bool _unlockFlowInProgress = false;

  bool _deckLoading = false;
  int _deckRequestToken = 0;
  DateTime? _lastChefStatusAt;
  List<Recipe> _aiDeck = const <Recipe>[];
  final Set<String> _consumedCardIds = <String>{};
  final Set<int> _loadingMoreEnergy = <int>{};
  final Map<int, List<Recipe>> _dbBufferByEnergy = <int, List<Recipe>>{};
  late final AiRecipeService _ai;
  final ImageSearchService _imageService = ImageSearchService();
  static final Map<String, List<Recipe>> _deckCache = <String, List<Recipe>>{};

  ({
    List<String> pantryNames,
    List<String> allergies,
    List<String> dietary,
    String inspiration,
    List<String> preferredCuisines,
    String? mealType,
    String cravings,
  })?
  _activeDeckQuery;

  // Filter Panel state (PDF spec)
  final TextEditingController _customPreferenceController =
      TextEditingController();
  // Filters are intentionally disabled for now per request.

  @override
  void dispose() {
    _swiperController.dispose();
    _customPreferenceController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _ai = AiRecipeService(onStatus: _handleChefStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshDeck());
    });
  }

  void _handleChefStatus(String message) {
    if (!mounted) return;
    final now = DateTime.now();
    final last = _lastChefStatusAt;
    if (last != null && now.difference(last).inSeconds < 2) return;
    _lastChefStatusAt = now;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _buildDeckKey({
    required List<String> pantryNames,
    required List<String> allergies,
    required List<String> dietary,
    required List<String> preferredCuisines,
    required String? mealType,
    required String cravings,
  }) {
    final p = [...pantryNames]..sort();
    final a = [...allergies]..sort();
    final d = [...dietary]..sort();
    final pc = [...preferredCuisines]..sort();
    return <String>[
      'p=${p.join(",")}',
      'a=${a.join(",")}',
      'd=${d.join(",")}',
      'pc=${pc.join(",")}',
      'm=${mealType ?? ""}',
      'cr=${cravings.trim().toLowerCase()}',
    ].join('|');
  }

  // Mock Recipes with real Unsplash images
  // (Kept for reference; Swipe deck is AI-driven now.)
  // ignore: unused_field
  final List<Recipe> _recipes = [
    Recipe(
      id: '1',
      title: 'Creamy Mushroom Pasta',
      imageUrl:
          'https://images.unsplash.com/photo-1621996346565-e3dbc646d9a9?w=800&q=80',
      description:
          'A rich and creamy pasta dish with fresh mushrooms and herbs.',
      ingredients: [
        '8 oz pasta',
        '2 cups sliced mushrooms',
        '1/2 cup cream',
        '2 cloves garlic',
        '1 tbsp parsley',
      ],
      instructions: [
        'Boil pasta in salted water until al dente. Reserve a splash of pasta water.',
        'Sauté sliced mushrooms in a pan until browned. Add minced garlic for 30 seconds.',
        'Add cream and a splash of pasta water, then toss in pasta until glossy.',
        'Finish with parsley, season to taste, and serve warm.',
      ],
      ingredientIds: const ['pasta', 'mushrooms', 'cream', 'garlic', 'parsley'],
      energyLevel: 2,
      timeMinutes: 25,
      calories: 520,
      equipment: ['Stovetop', 'Pot'],
      mealType: 'dinner',
      skillLevel: 'moderate',
      cuisine: 'italian',
      dietaryTags: const ['vegetarian'],
      flavorProfiles: const ['savory', 'comfort food'],
      prepTags: const ['minimal prep'],
    ),
    Recipe(
      id: '2',
      title: 'Avocado Toast',
      imageUrl:
          'https://images.unsplash.com/photo-1541519227354-08fa5d50c44d?w=800&q=80',
      description: 'Simple, healthy, and delicious avocado toast.',
      ingredients: [
        '2 slices bread',
        '1 ripe avocado',
        'Pinch of salt',
        'Pinch of pepper',
        '1/2 lemon',
      ],
      instructions: [
        'Toast the bread to your preferred crispness.',
        'Mash avocado with salt, pepper, and a squeeze of lemon.',
        'Spread on toast and serve immediately.',
      ],
      ingredientIds: const ['bread', 'avocado', 'lemon'],
      energyLevel: 1,
      timeMinutes: 8,
      calories: 320,
      equipment: ['Toaster', 'Knife'],
      mealType: 'breakfast',
      skillLevel: 'beginner',
      cuisine: 'american',
      dietaryTags: const ['vegetarian'],
      flavorProfiles: const ['savory', 'fresh and light'],
      prepTags: const ['minimal prep', 'no bake'],
    ),
    Recipe(
      id: '3',
      title: 'Spicy Chicken Curry',
      imageUrl:
          'https://images.unsplash.com/photo-1565557623262-b51c2513a641?w=800&q=80',
      description: 'Warming chicken curry with aromatic spices.',
      ingredients: [
        '1 lb chicken',
        '2 tbsp curry paste',
        '1 can coconut milk',
        '1 cup rice',
      ],
      instructions: [
        'Brown chicken pieces in a pan. Remove and set aside.',
        'Cook curry paste briefly until fragrant, then add coconut milk.',
        'Simmer chicken in sauce until cooked through. Serve with rice.',
      ],
      ingredientIds: const ['chicken', 'curry paste', 'coconut milk', 'rice'],
      energyLevel: 3,
      timeMinutes: 40,
      calories: 640,
      equipment: ['Stovetop', 'Pan'],
      mealType: 'dinner',
      skillLevel: 'advanced',
      cuisine: 'indian',
      dietaryTags: const ['gluten free', 'dairy free'],
      flavorProfiles: const ['spicy', 'savory', 'comfort food'],
      prepTags: const ['one pan'],
    ),
    Recipe(
      id: '4',
      title: 'Greek Salad',
      imageUrl:
          'https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=800&q=80',
      description: 'Fresh and crisp greek salad with feta cheese.',
      ingredients: [
        '1 cucumber',
        '2 tomatoes',
        '1/2 cup feta',
        '1/4 cup olives',
        '1 tsp oregano',
      ],
      instructions: [
        'Chop cucumber and tomato and add to a bowl.',
        'Add olives and crumbled feta.',
        'Season with oregano and toss gently.',
      ],
      ingredientIds: const ['cucumber', 'tomato', 'feta', 'olives', 'oregano'],
      energyLevel: 0,
      timeMinutes: 12,
      calories: 260,
      equipment: ['Bowl', 'Knife'],
      mealType: 'lunch',
      skillLevel: 'beginner',
      cuisine: 'mediterranean',
      dietaryTags: const ['vegetarian', 'gluten free'],
      flavorProfiles: const ['fresh and light', 'savory'],
      prepTags: const ['no bake'],
    ),
    Recipe(
      id: '5',
      title: 'Berry Smoothie',
      imageUrl:
          'https://images.unsplash.com/photo-1505252585461-04db1eb84625?w=800&q=80',
      description: 'Refreshing mixed berry smoothie.',
      ingredients: [
        '1 cup mixed berries',
        '1/2 cup yogurt',
        '1 tbsp honey',
        '1/2 cup milk',
      ],
      instructions: [
        'Add berries, yogurt, honey, and milk to a blender.',
        'Blend until smooth. Add more milk to thin if needed.',
        'Pour into a glass and enjoy.',
      ],
      ingredientIds: const ['berries', 'yogurt', 'honey', 'milk'],
      energyLevel: 1,
      timeMinutes: 6,
      calories: 220,
      equipment: ['Blender'],
      mealType: 'drinks',
      skillLevel: 'beginner',
      cuisine: 'american',
      dietaryTags: const ['vegetarian', 'gluten free'],
      flavorProfiles: const ['sweet', 'fresh and light'],
      prepTags: const ['minimal prep', 'no bake'],
    ),
    Recipe(
      id: '6',
      title: 'One-Pan Veggie Stir Fry',
      imageUrl:
          'https://images.unsplash.com/photo-1512058564366-18510be2db19?w=800&q=80',
      description: 'Colorful veggies tossed in a tangy sauce.',
      ingredients: [
        '2 cups broccoli florets',
        '1 bell pepper',
        '2 tbsp soy sauce',
        '8 oz noodles',
      ],
      instructions: [
        'Stir-fry broccoli and peppers in a hot pan until crisp-tender.',
        'Add cooked noodles and soy sauce, then toss to coat.',
        'Serve immediately while hot.',
      ],
      ingredientIds: const ['broccoli', 'peppers', 'soy sauce', 'noodles'],
      energyLevel: 2,
      timeMinutes: 18,
      calories: 410,
      equipment: ['Stovetop', 'Pan'],
      mealType: 'dinner',
      skillLevel: 'moderate',
      cuisine: 'chinese',
      dietaryTags: const ['vegetarian'],
      flavorProfiles: const ['savory', 'umami'],
      prepTags: const ['one pan'],
    ),
  ];

  String _norm(String value) => value.toLowerCase().trim();

  String? _persistedUserIdOrNull() {
    final authUser = ref.read(authProvider).user;
    final isGuest = ref.read(appStateProvider).isGuest;
    if (authUser == null) return null;
    if (isGuest || authUser.isAnonymous == true) return null;
    return authUser.uid;
  }

  int _remainingForEnergy(int energyLevel) {
    var count = 0;
    for (final r in _aiDeck) {
      if (r.energyLevel != energyLevel) continue;
      if (_consumedCardIds.contains(r.id)) continue;
      count++;
    }
    return count;
  }

  void _markCardConsumed(Recipe recipe) {
    if (!_consumedCardIds.add(recipe.id)) return;
    final userId = _persistedUserIdOrNull();
    if (userId == null) return;
    unawaited(
      ref
          .read(databaseServiceProvider)
          .markSwipeCardConsumed(userId, recipe.id),
    );
  }

  Recipe _recipeFromPreview(RecipePreview p) {
    final ing = p.ingredients.isNotEmpty ? p.ingredients : p.mainIngredients;
    return Recipe(
      id: p.id,
      title: p.title,
      imageUrl: p.imageUrl ?? ImageSearchService.getFallbackImage(p.mealType),
      description: p.vibeDescription,
      ingredients: ing,
      instructions: const <String>[],
      ingredientIds: ing.map((e) => _norm(e)).toList(),
      energyLevel: p.energyLevel,
      timeMinutes: p.estimatedTimeMinutes,
      calories: p.calories,
      equipment: p.equipmentIcons,
      mealType: p.mealType,
      cuisine: p.cuisine,
      skillLevel: p.skillLevel,
      dietaryTags: const <String>[],
    );
  }

  Map<int, List<Recipe>> _partitionByEnergy(List<Recipe> recipes) {
    final map = <int, List<Recipe>>{
      0: <Recipe>[],
      1: <Recipe>[],
      2: <Recipe>[],
      3: <Recipe>[],
    };
    for (final r in recipes) {
      final e = (r.energyLevel).clamp(0, 3);
      map.putIfAbsent(e, () => <Recipe>[]).add(r);
    }
    return map;
  }

  void _seedDeckFromDbRecipes({
    required List<Recipe> recipes,
    required ({
      List<String> pantryNames,
      List<String> allergies,
      List<String> dietary,
      String inspiration,
      List<String> preferredCuisines,
      String? mealType,
      String cravings,
    })
    query,
    required String deckKey,
  }) {
    final byEnergy = _partitionByEnergy(recipes);
    final visible = <Recipe>[];
    final buffer = <int, List<Recipe>>{};

    for (final energy in const [0, 1, 2, 3]) {
      final list = byEnergy[energy] ?? const <Recipe>[];
      final head = list.take(3).toList(growable: false);
      final tail = list.length > 3 ? list.sublist(3) : const <Recipe>[];
      visible.addAll(head);
      buffer[energy] = List<Recipe>.from(tail);
    }

    setState(() {
      _activeDeckQuery = query;
      _consumedCardIds.clear();
      _aiDeck = visible;
      _dbBufferByEnergy
        ..clear()
        ..addAll(buffer);
    });

    _deckCache[deckKey] = List<Recipe>.from(visible);
  }

  Future<
    ({
      List<String> pantryNames,
      List<String> allergies,
      List<String> dietary,
      String inspiration,
      List<String> preferredCuisines,
      String? mealType,
      String cravings,
    })
  >
  _computeDeckQuery() async {
    final pantryItems =
        ref.read(pantryItemsProvider).value ?? const <PantryItem>[];
    final profile = ref.read(userProfileProvider).value;

    final pantryNames = pantryItems
        .map((p) => p.normalizedName)
        .where((e) => e.trim().isNotEmpty)
        .toList();

    final isZeroPantry = pantryNames.isEmpty;
    final mealType = profile?.preferences.defaultMealType;

    final cravings = _customPreferenceController.text.trim();
    final inspiration = isZeroPantry
        ? (cravings.isNotEmpty
              ? cravings
              : 'Inspiration: popular, highly-rated meals that match my preferences')
        : cravings;

    final allergies = profile?.preferences.allergies ?? const <String>[];
    final dietary =
        profile?.preferences.dietaryRestrictions ?? const <String>[];
    final preferredCuisines =
        profile?.preferences.preferredCuisines ?? const <String>[];

    return (
      pantryNames: pantryNames,
      allergies: allergies,
      dietary: dietary,
      inspiration: inspiration,
      preferredCuisines: preferredCuisines,
      mealType: mealType,
      cravings: cravings,
    );
  }

  Future<void> _loadMoreForEnergy(int energyLevel) async {
    if (_loadingMoreEnergy.contains(energyLevel)) return;
    if (_remainingForEnergy(energyLevel) > 0) return;

    final buffered = _dbBufferByEnergy[energyLevel] ?? const <Recipe>[];
    if (buffered.isNotEmpty) {
      final take = buffered.length >= 3 ? 3 : buffered.length;
      final next = buffered.take(take).toList(growable: false);
      final rest = buffered.skip(take).toList(growable: false);
      setState(() {
        _aiDeck = [..._aiDeck, ...next];
        _dbBufferByEnergy[energyLevel] = List<Recipe>.from(rest);
      });
      return;
    }

    final userId = _persistedUserIdOrNull();
    final requestToken = _deckRequestToken;

    setState(() => _loadingMoreEnergy.add(energyLevel));
    try {
      final query = _activeDeckQuery ?? await _computeDeckQuery();
      _activeDeckQuery ??= query;

      final shownIds = <String>{};
      for (final r in _aiDeck) {
        shownIds.add(r.id);
      }

      // 1) Signed-in users: pull next 3 from DB first (until depleted).
      if (userId != null) {
        final previews = await ref
            .read(databaseServiceProvider)
            .getUnconsumedSwipeCards(userId);
        if (!mounted || requestToken != _deckRequestToken) return;

        final candidates = previews
            .where(
              (p) =>
                  !_consumedCardIds.contains(p.id) && !shownIds.contains(p.id),
            )
            .map(_recipeFromPreview)
            .toList(growable: false);

        if (candidates.isNotEmpty) {
          final byEnergy = _partitionByEnergy(candidates);
          final newBuffers = <int, List<Recipe>>{};
          for (final energy in const [0, 1, 2, 3]) {
            newBuffers[energy] = List<Recipe>.from(
              byEnergy[energy] ?? const <Recipe>[],
            );
          }

          final list = newBuffers[energyLevel] ?? const <Recipe>[];
          final take = list.length >= 3 ? 3 : list.length;
          final next = list.take(take).toList(growable: false);
          newBuffers[energyLevel] = list.skip(take).toList(growable: false);

          setState(() {
            _aiDeck = [..._aiDeck, ...next];
            _dbBufferByEnergy
              ..clear()
              ..addAll(newBuffers);
          });

          if (next.isNotEmpty) return;
        }
      }

      final seenTitles = <String>{};
      for (final r in _aiDeck) {
        if (_consumedCardIds.contains(r.id)) continue;
        seenTitles.add(_norm(r.title));
      }

      final previews = await _ai.generateRecipePreviewsBatch(
        count: 3,
        pantryItems: query.pantryNames,
        allergies: query.allergies,
        dietaryRestrictions: query.dietary,
        cravings: query.inspiration,
        energyLevel: energyLevel,
        preferredCuisines: query.preferredCuisines,
        mealType: query.mealType,
        strictPantryMatch: false,
      );

      if (!mounted || requestToken != _deckRequestToken) return;

      final persisted = <RecipePreview>[];
      final added = <Recipe>[];
      for (final p in previews) {
        if (!mounted || requestToken != _deckRequestToken) return;
        final titleKey = _norm(p.title);
        if (!seenTitles.add(titleKey)) continue;

        final img = await _imageService.searchRecipeImage(
          recipeTitle: p.title,
          ingredients: p.ingredients.isNotEmpty
              ? p.ingredients
              : p.mainIngredients,
        );
        final imageUrl =
            img?.imageUrl ??
            p.imageUrl ??
            ImageSearchService.getFallbackImage(p.mealType);
        final persistedPreview = p.copyWith(imageUrl: imageUrl);
        persisted.add(persistedPreview);
        added.add(_recipeFromPreview(persistedPreview));
      }

      if (added.isNotEmpty && mounted && requestToken == _deckRequestToken) {
        setState(() => _aiDeck = [..._aiDeck, ...added]);
      }

      if (userId != null && persisted.isNotEmpty) {
        unawaited(
          ref.read(databaseServiceProvider).upsertSwipeCards(userId, persisted),
        );
      }
    } catch (_) {
      // Best-effort; avoid interrupting swipe UX.
    } finally {
      if (mounted) setState(() => _loadingMoreEnergy.remove(energyLevel));
    }
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

    // Fuzzy contains match (helps “tomato” vs “cherry tomato”)
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
    if (activity is Swipe) {
      if (previousIndex < deck.length) {
        final swipedRecipe = deck[previousIndex];
        if (activity.direction == AxisDirection.right) {
          unawaited(_handleRightSwipe(swipedRecipe));
        } else {
          // Left swipe - dismiss & consume.
          _markCardConsumed(swipedRecipe);
          if (_remainingForEnergy(swipedRecipe.energyLevel) == 0) {
            unawaited(_loadMoreForEnergy(swipedRecipe.energyLevel));
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final subscription = profile?.subscriptionStatus.toLowerCase() ?? 'free';
    final isPremium = subscription == 'premium' || subscription == 'pro';

    final carrotsObj = profile?.carrots;
    final maxCarrots = carrotsObj?.max ?? 5;
    final currentCarrots = carrotsObj?.current ?? 0;
    final lastResetAt = carrotsObj?.lastResetAt;
    final needsReset =
        lastResetAt == null ||
        DateTime.now().difference(lastResetAt).inDays >= 7;
    final availableCarrots = needsReset ? maxCarrots : currentCarrots;

    final canUnlock = isPremium || availableCarrots > 0;
    final visibleDeck = _aiDeck
        .where(
          (r) =>
              r.energyLevel == _selectedEnergyLevel &&
              !_consumedCardIds.contains(r.id),
        )
        .toList(growable: false);

    final showLoading =
        (_deckLoading && _aiDeck.isEmpty) ||
        _loadingMoreEnergy.contains(_selectedEnergyLevel);

    Widget deckWidget;
    if (showLoading) {
      deckWidget = _buildDeckLoading();
    } else if (visibleDeck.isEmpty) {
      deckWidget = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _aiDeck.isEmpty
                ? 'No recipes yet. Tap refresh to generate.'
                : 'No recipes for this energy level. Try another level.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
          ),
        ),
      );
    } else {
      deckWidget = AppinioSwiper(
        controller: _swiperController,
        cardCount: visibleDeck.length,
        onSwipeEnd: (previousIndex, targetIndex, activity) =>
            _onSwipeEnd(visibleDeck, previousIndex, targetIndex, activity),
        cardBuilder: (context, index) => _buildRecipeCard(visibleDeck[index]),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Swipe'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh deck',
            onPressed: _deckLoading
                ? null
                : () => unawaited(_refreshDeck(forceRegenerate: true)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildEnergySlider(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: deckWidget,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildActionButton(
                    icon: Icons.close,
                    color: AppTheme.errorColor,
                    onPressed: (_unlockFlowInProgress || visibleDeck.isEmpty)
                        ? null
                        : () => _swiperController.swipeLeft(),
                  ),
                  const SizedBox(width: AppTheme.spacingXL),
                  _buildActionButton(
                    icon: Icons.info_outline_rounded,
                    color: Colors.blueGrey,
                    isSmall: true,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Tip: Tap “Show Ingredients Needed” to preview without unlocking.',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: AppTheme.spacingXL),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: canUnlock ? 1.0 : 0.5,
                    child: _buildActionButton(
                      icon: Icons.arrow_forward_rounded,
                      color: AppTheme.primaryColor,
                      onPressed: (_unlockFlowInProgress || visibleDeck.isEmpty)
                          ? null
                          : () {
                              final authUser = ref.read(authProvider).user;
                              if (authUser == null) {
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRecipeDetail(Recipe recipe) {
    context.push('${AppRoutes.recipes}/${recipe.id}', extra: recipe);
  }

  Future<void> _handleRightSwipe(Recipe recipe) async {
    if (_unlockFlowInProgress) return;
    setState(() => _unlockFlowInProgress = true);

    Future<void> undoLastSwipe() async {
      try {
        await _swiperController.unswipe();
      } catch (_) {
        // If there's no swipe history yet, unswipe is a no-op.
      }
    }

    try {
      final authUser = ref.read(authProvider).user;
      final userId = authUser?.uid;
      final isGuest = ref.read(appStateProvider).isGuest;

      if (userId == null) {
        if (mounted) context.go(AppRoutes.login);
        await undoLastSwipe();
        return;
      }

      // Guests can swipe, but cannot unlock (must authenticate).
      if (isGuest || authUser?.isAnonymous == true) {
        if (mounted) context.go(AppRoutes.login);
        await undoLastSwipe();
        return;
      }

      // If already saved/unlocked, just open.
      final alreadySaved = await ref
          .read(recipeServiceProvider)
          .isRecipeSaved(userId, recipe.id);
      if (alreadySaved) {
        _markCardConsumed(recipe);
        if (_remainingForEnergy(recipe.energyLevel) == 0) {
          unawaited(_loadMoreForEnergy(recipe.energyLevel));
        }
        if (mounted) _openRecipeDetail(recipe);
        return;
      }

      final profile = ref.read(userProfileProvider).value;
      final subscription = profile?.subscriptionStatus.toLowerCase() ?? 'free';
      final isPremium = subscription == 'premium' || subscription == 'pro';

      // Persisted via SharedPreferences; requirement calls this hideUnlockReminder.
      final hideUnlockReminder = ref.read(appStateProvider).skipUnlockReminder;

      // Build RecipePreview from existing recipe for dialog
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
      final lastResetAt = carrotsObj?.lastResetAt;
      final needsReset =
          lastResetAt == null ||
          DateTime.now().difference(lastResetAt).inDays >= 7;
      final availableCarrots = needsReset ? maxCarrots : currentCarrots;

      if (!mounted) return;

      // Show ConfirmUnlockDialog immediately on swipe right
      bool shouldProceed;
      if (isPremium) {
        // Premium users bypass modal and cost.
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

      if (!shouldProceed) {
        await undoLastSwipe();
        return;
      }

      // Atomic spend (free users only) AFTER confirmation.
      if (!isPremium) {
        final db = ref.read(databaseServiceProvider);
        final success = await db.deductCarrot(userId);
        if (!success) {
          if (!mounted) return;
          _showOutOfCarrots();
          await undoLastSwipe();
          return;
        }
      }

      // Generate full recipe ONLY after spend/premium bypass.
      final pantryItems =
          ref.read(pantryItemsProvider).value ?? const <PantryItem>[];
      final pantryNames = pantryItems.map((p) => p.normalizedName).toList();

      final full = await _ai.generateFullRecipe(
        preview: preview.copyWith(
          calories: preview.calories,
          equipmentIcons: preview.equipmentIcons,
          ingredients: preview.ingredients.isNotEmpty
              ? preview.ingredients
              : preview.mainIngredients,
        ),
        pantryItems: pantryNames,
        allergies: profile?.preferences.allergies ?? const <String>[],
        dietaryRestrictions:
            profile?.preferences.dietaryRestrictions ?? const <String>[],
        showCalories: true,
        strictPantryMatch: false,
      );

      final fullWithMeta = full.copyWith(
        id: recipe.id,
        imageUrl: recipe.imageUrl,
        calories: full.calories > 0 ? full.calories : recipe.calories,
        timeMinutes: full.timeMinutes > 0
            ? full.timeMinutes
            : recipe.timeMinutes,
        equipment: full.equipment.isNotEmpty
            ? full.equipment
            : recipe.equipment,
        mealType: recipe.mealType,
        cuisine: recipe.cuisine,
        skillLevel: recipe.skillLevel,
        ingredientIds: recipe.ingredientIds,
      );

      await ref.read(recipeServiceProvider).saveRecipe(userId, fullWithMeta);

      if (mounted) {
        _markCardConsumed(recipe);
        if (_remainingForEnergy(recipe.energyLevel) == 0) {
          unawaited(_loadMoreForEnergy(recipe.energyLevel));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPremium
                  ? 'Recipe Unlocked & Saved!'
                  : 'Recipe Unlocked & Saved! -1 Carrot',
            ),
            backgroundColor: AppTheme.primaryColor,
            duration: const Duration(seconds: 2),
          ),
        );
        _openRecipeDetail(fullWithMeta);
      }
    } catch (e) {
      await undoLastSwipe();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to unlock: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _unlockFlowInProgress = false);
      }
    }
  }

  Future<void> _refreshDeck({bool forceRegenerate = false}) async {
    if (_deckLoading) return;
    final requestToken = ++_deckRequestToken;
    setState(() => _deckLoading = true);

    try {
      final query = await _computeDeckQuery();
      final deckKey = _buildDeckKey(
        pantryNames: query.pantryNames,
        allergies: query.allergies,
        dietary: query.dietary,
        preferredCuisines: query.preferredCuisines,
        mealType: query.mealType,
        cravings: query.cravings,
      );

      final userId = _persistedUserIdOrNull();

      if (userId != null && forceRegenerate) {
        await ref.read(databaseServiceProvider).clearSwipeDeck(userId);
        _deckCache.remove(deckKey);
        if (mounted && requestToken == _deckRequestToken) {
          setState(() => _dbBufferByEnergy.clear());
        }
      }

      // Prefer persisted deck for signed-in users.
      if (userId != null && !forceRegenerate) {
        final previews = await ref
            .read(databaseServiceProvider)
            .getUnconsumedSwipeCards(userId);
        if (!mounted || requestToken != _deckRequestToken) return;

        if (previews.isNotEmpty) {
          final loaded = previews
              .map(_recipeFromPreview)
              .toList(growable: false);
          _seedDeckFromDbRecipes(
            recipes: loaded,
            query: query,
            deckKey: deckKey,
          );
          return;
        }
      }

      // Local caching: if we already generated a deck for this pantry+filters,
      // reuse it (no re-generation on back/return).
      if (!forceRegenerate) {
        final cached = _deckCache[deckKey];
        if (cached != null && cached.isNotEmpty) {
          if (mounted && requestToken == _deckRequestToken) {
            setState(() {
              _activeDeckQuery = (
                pantryNames: query.pantryNames,
                allergies: query.allergies,
                dietary: query.dietary,
                inspiration: query.inspiration,
                preferredCuisines: query.preferredCuisines,
                mealType: query.mealType,
                cravings: query.cravings,
              );
              _consumedCardIds.clear();
              _aiDeck = cached;
            });
          }
          return;
        }
      }

      if (mounted && requestToken == _deckRequestToken) {
        setState(() {
          _activeDeckQuery = (
            pantryNames: query.pantryNames,
            allergies: query.allergies,
            dietary: query.dietary,
            inspiration: query.inspiration,
            preferredCuisines: query.preferredCuisines,
            mealType: query.mealType,
            cravings: query.cravings,
          );
          _consumedCardIds.clear();
          _aiDeck = const <Recipe>[];
          _dbBufferByEnergy.clear();
        });
      }

      // Generate 3 cards for each energy level (0..3) => 12 total.
      await _generateDeckAllEnergyLevels(
        requestToken: requestToken,
        deckKey: deckKey,
        query: _activeDeckQuery!,
      );
    } catch (e) {
      // If AI fails, keep existing deck (or empty).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load AI deck: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deckLoading = false);
    }
  }

  Future<void> _generateDeckAllEnergyLevels({
    required int requestToken,
    required String deckKey,
    required ({
      List<String> pantryNames,
      List<String> allergies,
      List<String> dietary,
      String inspiration,
      List<String> preferredCuisines,
      String? mealType,
      String cravings,
    })
    query,
  }) async {
    final all = <Recipe>[];
    final seen = <String>{};
    final persisted = <RecipePreview>[];
    final userId = _persistedUserIdOrNull();

    for (final energy in const [0, 1, 2, 3]) {
      if (!mounted || requestToken != _deckRequestToken) return;

      final previews = await _ai.generateRecipePreviewsBatch(
        count: 3,
        pantryItems: query.pantryNames,
        allergies: query.allergies,
        dietaryRestrictions: query.dietary,
        cravings: query.inspiration,
        energyLevel: energy,
        preferredCuisines: query.preferredCuisines,
        mealType: query.mealType,
        strictPantryMatch: false,
      );

      for (final p in previews) {
        if (!mounted || requestToken != _deckRequestToken) return;
        final titleKey = _norm(p.title);
        if (!seen.add(titleKey)) continue;

        final img = await _imageService.searchRecipeImage(
          recipeTitle: p.title,
          ingredients: p.ingredients.isNotEmpty
              ? p.ingredients
              : p.mainIngredients,
        );

        final imageUrl =
            img?.imageUrl ??
            p.imageUrl ??
            ImageSearchService.getFallbackImage(p.mealType);

        final persistedPreview = p.copyWith(imageUrl: imageUrl);
        persisted.add(persistedPreview);

        final ing = persistedPreview.ingredients.isNotEmpty
            ? persistedPreview.ingredients
            : persistedPreview.mainIngredients;
        all.add(
          Recipe(
            id: persistedPreview.id,
            title: persistedPreview.title,
            imageUrl: imageUrl,
            description: persistedPreview.vibeDescription,
            ingredients: ing,
            instructions: const <String>[],
            ingredientIds: ing.map((e) => _norm(e)).toList(),
            energyLevel: energy,
            timeMinutes: persistedPreview.estimatedTimeMinutes,
            calories: persistedPreview.calories,
            equipment: persistedPreview.equipmentIcons,
            mealType: persistedPreview.mealType,
            cuisine: persistedPreview.cuisine,
            skillLevel: persistedPreview.skillLevel,
            dietaryTags: query.dietary,
          ),
        );
      }

      if (mounted && requestToken == _deckRequestToken) {
        setState(() => _aiDeck = List<Recipe>.from(all));
      }
    }

    if (mounted && requestToken == _deckRequestToken) {
      _deckCache[deckKey] = List<Recipe>.from(all);
    }

    if (userId != null && persisted.isNotEmpty) {
      unawaited(
        ref.read(databaseServiceProvider).upsertSwipeCards(userId, persisted),
      );
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Cooking up ideas… just a few seconds',
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
            const SizedBox(height: 18),
            Text(
              'Generating 3 meals for each energy level.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergySlider() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Energy Level',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: AppTheme.textSecondary),
              ),
              Text(
                _getEnergyLabel(_selectedEnergyLevel),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: AppTheme.primaryColor,
            inactiveTrackColor: Colors.grey.shade200,
            thumbColor: AppTheme.primaryColor,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
          ),
          child: Slider(
            value: _selectedEnergyLevel.toDouble(),
            min: 0,
            max: 3,
            divisions: 3,
            onChanged: (value) =>
                setState(() => _selectedEnergyLevel = value.round()),
          ),
        ),
      ],
    );
  }

  String _getEnergyLabel(int level) {
    switch (level) {
      case 0:
        return 'Sleepy 💤';
      case 1:
        return 'Low 🔋';
      case 2:
        return 'Okay ⚡';
      case 3:
        return 'High 🔥';
      default:
        return '';
    }
  }

  Widget _buildRecipeCard(Recipe recipe) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.mediumShadow,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
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
                      child: const Center(child: CircularProgressIndicator()),
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
                    // Fallback to an Unsplash-hosted image to avoid local placeholders.
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
                // Gradient Overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.8),
                        ],
                        stops: const [0.6, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildTag(
                          '${recipe.timeMinutes} min',
                          Icons.access_time,
                        ),
                        const SizedBox(width: 8),
                        _buildTag(
                          '${recipe.ingredients.length} items',
                          Icons.list,
                        ),
                        const SizedBox(width: 8),
                        _buildTag(
                          '${recipe.calories} cal',
                          Icons.local_fire_department,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    recipe.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    recipe.description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  if (recipe.equipment.isNotEmpty)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: recipe.equipment.map((label) {
                        return Tooltip(
                          message: label,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Icon(
                              _equipmentIcon(label),
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final pantryItems =
                            ref.read(pantryItemsProvider).value ??
                            const <PantryItem>[];
                        final pantry = _pantryKeySet(pantryItems);
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          builder: (context) =>
                              _buildIngredientsModal(recipe, pantry),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Show Ingredients Needed'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _handleShowDirections(recipe),
                      icon: const Icon(
                        Icons.menu_book_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Show Directions',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  IconData _equipmentIcon(String raw) {
    final v = _norm(raw);
    if (v.contains('microwave')) return Icons.microwave_outlined;
    if (v.contains('oven')) return Icons.kitchen_outlined;
    if (v.contains('air fryer') || v.contains('airfryer')) {
      return Icons.local_fire_department_outlined;
    }
    if (v.contains('stove') || v.contains('stovetop') || v.contains('burner')) {
      return Icons.local_fire_department_outlined;
    }
    if (v.contains('grill')) return Icons.outdoor_grill_outlined;
    if (v.contains('pot') || v.contains('pan') || v.contains('skillet')) {
      return Icons.soup_kitchen_outlined;
    }
    if (v.contains('knife') || v.contains('cutting')) {
      return Icons.restaurant_outlined;
    }
    if (v.contains('blender') || v.contains('food processor')) {
      return Icons.blender_outlined;
    }
    if (v.contains('bowl')) return Icons.ramen_dining_outlined;
    if (v.contains('toaster')) return Icons.breakfast_dining_outlined;
    return Icons.kitchen_outlined;
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
      final parts = raw.split(RegExp(r'\\s+')).where((p) => p.isNotEmpty);
      return parts
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }

    String stripQuantity(String value) {
      final v = value.trim();
      final stripped = v.replaceFirst(
        RegExp(r'^(?:\\d+(?:\\.\\d+)?|\\d+\\/\\d+)\\s+[^A-Za-z]*'),
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
            final key = rawKey;
            final hasIt = _pantryHas(pantry, key);
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
    final isGuest = ref.read(appStateProvider).isGuest;

    if (userId == null) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    // Guests must authenticate before unlocking directions (spec)
    if (isGuest || authUser?.isAnonymous == true) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    // If already saved/unlocked, open immediately.
    final alreadySaved = await ref
        .read(recipeServiceProvider)
        .isRecipeSaved(userId, recipe.id);
    if (alreadySaved) {
      if (mounted) _openRecipeDetail(recipe);
      return;
    }

    if (!mounted) return;

    final profile = ref.read(userProfileProvider).value;
    final subscription = profile?.subscriptionStatus.toLowerCase() ?? 'free';
    final isPremium = subscription == 'premium' || subscription == 'pro';

    // Persisted via SharedPreferences; requirement calls this hideUnlockReminder.
    final hideUnlockReminder = ref.read(appStateProvider).skipUnlockReminder;

    // Build preview for AI full generation.
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

    bool shouldProceed;
    if (isPremium) {
      shouldProceed = true;
    } else if (hideUnlockReminder) {
      final carrotsObj = profile?.carrots;
      final maxCarrots = carrotsObj?.max ?? 5;
      final currentCarrots = carrotsObj?.current ?? 0;
      final lastResetAt = carrotsObj?.lastResetAt;
      final needsReset =
          lastResetAt == null ||
          DateTime.now().difference(lastResetAt).inDays >= 7;
      final availableCarrots = needsReset ? maxCarrots : currentCarrots;

      shouldProceed = await _showReducedUnlockDialog(
        preview: preview,
        currentCarrots: availableCarrots,
        maxCarrots: maxCarrots,
      );
    } else {
      final carrotsObj = profile?.carrots;
      final maxCarrots = carrotsObj?.max ?? 5;
      final currentCarrots = carrotsObj?.current ?? 0;
      final lastResetAt = carrotsObj?.lastResetAt;
      final needsReset =
          lastResetAt == null ||
          DateTime.now().difference(lastResetAt).inDays >= 7;
      final availableCarrots = needsReset ? maxCarrots : currentCarrots;

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

    // Atomic spend (free users only) AFTER confirmation.
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

    final pantryItems =
        ref.read(pantryItemsProvider).value ?? const <PantryItem>[];
    final pantryNames = pantryItems.map((p) => p.normalizedName).toList();

    final full = await _ai.generateFullRecipe(
      preview: preview,
      pantryItems: pantryNames,
      allergies: profile?.preferences.allergies ?? const <String>[],
      dietaryRestrictions:
          profile?.preferences.dietaryRestrictions ?? const <String>[],
      showCalories: true,
      strictPantryMatch: false,
    );

    final fullWithMeta = full.copyWith(
      id: recipe.id,
      imageUrl: recipe.imageUrl,
      mealType: recipe.mealType,
      cuisine: recipe.cuisine,
      skillLevel: recipe.skillLevel,
      ingredientIds: recipe.ingredientIds,
      calories: full.calories > 0 ? full.calories : recipe.calories,
      timeMinutes: full.timeMinutes > 0 ? full.timeMinutes : recipe.timeMinutes,
      equipment: full.equipment.isNotEmpty ? full.equipment : recipe.equipment,
    );

    await ref.read(recipeServiceProvider).saveRecipe(userId, fullWithMeta);
    if (mounted) _openRecipeDetail(fullWithMeta);
  }
}
