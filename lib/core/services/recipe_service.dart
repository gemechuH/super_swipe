import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/services/firestore_service.dart';

/// Service for managing recipe operations in Firestore
class RecipeService {
  final FirestoreService _firestoreService;

  RecipeService(this._firestoreService);

  /// Save a recipe to user's saved recipes
  Future<void> saveRecipe(String userId, Recipe recipe) async {
    await _firestoreService
        .userSavedRecipes(userId)
        .doc(recipe.id)
        .set(recipe.toSavedRecipeFirestore());
  }

  /// Get all saved recipes for a user (one-time fetch)
  Future<List<Recipe>> getSavedRecipes(String userId) async {
    final snapshot = await _firestoreService
        .userSavedRecipes(userId)
        .orderBy('savedAt', descending: true)
        .get();

    return snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList();
  }

  /// Stream saved recipes (real-time updates)
  Stream<List<Recipe>> watchSavedRecipes(String userId) {
    return _firestoreService
        .userSavedRecipes(userId)
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList();
        });
  }

  /// Remove a recipe from saved recipes
  Future<void> unsaveRecipe(String userId, String recipeId) async {
    await _firestoreService.userSavedRecipes(userId).doc(recipeId).delete();
  }

  /// Check if a recipe is saved
  Future<bool> isRecipeSaved(String userId, String recipeId) async {
    final doc = await _firestoreService
        .userSavedRecipes(userId)
        .doc(recipeId)
        .get();
    return doc.exists;
  }

  /// Update saved-recipe step progress (step number last reached).
  Future<void> updateSavedRecipeProgress({
    required String userId,
    required String recipeId,
    required int currentStep,
  }) async {
    await _firestoreService.userSavedRecipes(userId).doc(recipeId).update({
      'currentStep': currentStep,
      'lastStepAt': FieldValue.serverTimestamp(),
    });
  }

  /// Add recipe to history
  Future<void> addToHistory(String userId, String recipeId) async {
    await _firestoreService.userRecipeHistory(userId).add({
      'recipeId': recipeId,
      'viewedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get recipe history
  Future<List<Map<String, dynamic>>> getRecipeHistory(String userId) async {
    final snapshot = await _firestoreService
        .userRecipeHistory(userId)
        .orderBy('viewedAt', descending: true)
        .limit(20)
        .get();

    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
        .toList();
  }

  /// Delete all saved recipes for a user
  /// Fix #7: Handle 500+ recipes with chunked batches
  Future<void> clearSavedRecipes(String userId) async {
    const batchSize = 500;
    final snapshot = await _firestoreService.userSavedRecipes(userId).get();

    // Process in chunks of 500
    for (var i = 0; i < snapshot.docs.length; i += batchSize) {
      final batch = _firestoreService.instance.batch();
      final end = (i + batchSize < snapshot.docs.length)
          ? i + batchSize
          : snapshot.docs.length;

      for (var j = i; j < end; j++) {
        batch.delete(snapshot.docs[j].reference);
      }

      await batch.commit();
    }
  }

  /// Toggle favorite/like status for a saved recipe
  /// This does NOT remove the recipe - just changes isFavorite flag
  Future<void> toggleRecipeFavorite(String userId, String recipeId) async {
    final docRef = _firestoreService.userSavedRecipes(userId).doc(recipeId);
    final doc = await docRef.get();

    if (!doc.exists) return;

    final currentFavorite =
        (doc.data() as Map<String, dynamic>?)?['isFavorite'] ?? false;

    await docRef.update({
      'isFavorite': !currentFavorite,
      'favoriteChangedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // RECIPE DISCOVERY & PAGINATION
  // ============================================

  /// Get recipes by energy level with pagination
  /// Fix #6: Pagination state passed as parameter
  Future<List<Recipe>> getRecipesByEnergyLevel({
    required int energyLevel,
    int limit = 10,
    DocumentSnapshot? startAfterDoc,
  }) async {
    Query query = _firestoreService.recipes
        .where('isActive', isEqualTo: true)
        .where('energyLevel', isEqualTo: energyLevel)
        .orderBy('stats.popularityScore', descending: true)
        .limit(limit);

    // If loading more, start after provided document
    if (startAfterDoc != null) {
      query = query.startAfterDocument(startAfterDoc);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList();
  }

  /// Get recipes by energy level along with pagination cursor.
  ///
  /// Keeps the existing `getRecipesByEnergyLevel` API intact while allowing
  /// callers (like Swipe) to efficiently paginate.
  Future<({List<Recipe> recipes, DocumentSnapshot? lastDoc})>
  getRecipesPageByEnergyLevel({
    required int energyLevel,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  }) async {
    Query query = _firestoreService.recipes
        .where('isActive', isEqualTo: true)
        .where('energyLevel', isEqualTo: energyLevel)
        .orderBy('stats.popularityScore', descending: true)
        .limit(limit);

    if (startAfterDoc != null) {
      query = query.startAfterDocument(startAfterDoc);
    }

    final snapshot = await query.get();
    return (
      recipes: snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList(),
      lastDoc: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
    );
  }

  /// Stream recipes by energy level (real-time, first page only)
  Stream<List<Recipe>> watchRecipesByEnergyLevel({
    required int energyLevel,
    int limit = 10,
  }) {
    return _firestoreService.recipes
        .where('isActive', isEqualTo: true)
        .where('energyLevel', isEqualTo: energyLevel)
        .orderBy('stats.popularityScore', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList();
        });
  }

  /// Get all recipes (for admin/seeding purposes)
  Future<List<Recipe>> getAllRecipes() async {
    final snapshot = await _firestoreService.recipes
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList();
  }

  /// Search recipes by title or ingredients
  Future<List<Recipe>> searchRecipes(String query) async {
    final normalizedQuery = query.toLowerCase().trim();

    final snapshot = await _firestoreService.recipes
        .where('isActive', isEqualTo: true)
        .orderBy('titleLowercase')
        .startAt([normalizedQuery])
        .endAt(['$normalizedQuery\uf8ff'])
        .limit(20)
        .get();

    return snapshot.docs.map((doc) => Recipe.fromFirestore(doc)).toList();
  }

  /// Get recipe by ID
  Future<Recipe?> getRecipeById(String recipeId) async {
    final doc = await _firestoreService.recipes.doc(recipeId).get();
    if (doc.exists) {
      return Recipe.fromFirestore(doc);
    }
    return null;
  }
}
