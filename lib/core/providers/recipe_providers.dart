import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/providers/firestore_providers.dart';
import 'package:super_swipe/core/services/recipe_service.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';

/// Recipe Service Provider
final recipeServiceProvider = Provider<RecipeService>((ref) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return RecipeService(firestoreService);
});

/// Stream of User's Saved Recipes
final savedRecipesProvider = StreamProvider<List<Recipe>>((ref) {
  final user = ref.watch(authProvider).user;
  if (user == null) return Stream.value([]);

  final recipeService = ref.watch(recipeServiceProvider);
  return recipeService.watchSavedRecipes(user.uid);
});

/// Single Saved Recipe Provider (Family)
final savedRecipeProvider = StreamProvider.family<Recipe?, String>((
  ref,
  recipeId,
) {
  final user = ref.watch(authProvider).user;
  if (user == null) return Stream.value(null);

  // We can optimize this by watching the specific doc, but since RecipeService
  // exposes watchSavedRecipes (list), we might need a specific method for single doc stream
  // or just filter the list.
  // For now, let's assume we can watch the list and find it, OR add a method to service.
  // However, RecipeService.watchSavedRecipes returns a Stream<List<Recipe>>.
  // A better approach for a single doc stream is accessing Firestore directly or adding a method.
  // Given the constraints and current service methods, we'll return a Future via Stream
  // or implement a basic polling/watching mechanism if likely needed.
  // Actually, let's look at the usage. It's used in RecipeDetailScreen.
  // Just returning a FutureProvider might be safer if we don't have a single-doc stream method yet.
  // But wait, the error says 'watch(savedRecipeProvider(id))', implying it expects updates.
  // Let's use the list stream and map it to find the specific recipe for now.

  // NOTE: This is slightly inefficient but safe.
  final savedRecipes = ref.watch(savedRecipesProvider);
  return savedRecipes.when(
    data: (recipes) {
      try {
        final recipe = recipes.firstWhere(
          (r) => r.id == recipeId,
          orElse: () => throw Exception('Not found'),
        );
        return Stream.value(recipe);
      } catch (e) {
        return Stream.value(null);
      }
    },
    loading: () => const Stream.empty(),
    error: (error, stackTrace) => Stream.value(null),
  );
});
