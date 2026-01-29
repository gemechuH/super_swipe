import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/providers/firestore_providers.dart';
import 'package:super_swipe/core/services/recipe_service.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/services/database/database_provider.dart';

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

  final recipeService = ref.watch(recipeServiceProvider);
  return recipeService.watchSavedRecipe(user.uid, recipeId);
});

final recipeSecretsProvider = FutureProvider.family<List<String>, String>((
  ref,
  recipeId,
) async {
  final user = ref.watch(authProvider).user;
  if (user == null) return const <String>[];
  final db = ref.watch(databaseServiceProvider);
  return db.getRecipeSecrets(recipeId);
});
