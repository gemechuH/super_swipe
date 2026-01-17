import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:super_swipe/core/config/constants.dart';
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/core/models/user_profile.dart';

/// Production-grade Database Service implementing:
/// - Carrot Economy with Lazy Reset
/// - Secure Recipe Unlock (Split Collection Pattern)
/// - Pantry Sync with Audit Logging
/// - Guest-to-User Data Migration
class DatabaseService {
  // Singleton pattern
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ============================================================
  // COLLECTION REFERENCES
  // ============================================================

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _recipes =>
      _firestore.collection('recipes');

  CollectionReference<Map<String, dynamic>> get _recipeSecrets =>
      _firestore.collection('recipe_secrets');

  CollectionReference<Map<String, dynamic>> _userPantry(String userId) =>
      _users.doc(userId).collection('pantry');

  CollectionReference<Map<String, dynamic>> _savedRecipes(String userId) =>
      _users.doc(userId).collection('savedRecipes');

  CollectionReference<Map<String, dynamic>> _transactions(String userId) =>
      _users.doc(userId).collection('transactions');

  CollectionReference<Map<String, dynamic>> _pantryLogs(String userId) =>
      _users.doc(userId).collection('pantry_logs');

  CollectionReference<Map<String, dynamic>> _swipeDeck(String userId) =>
      _users.doc(userId).collection('swipeDeck');

  CollectionReference<Map<String, dynamic>> _ideaKeyHistory(String userId) =>
      _users.doc(userId).collection('ideaKeyHistory');

  // ============================================================
  // 1. CARROT ECONOMY
  // ============================================================

  // ============================================================
  // 1.1 ATOMIC CARROT DEDUCTION (for two-step unlock flow)
  // ============================================================

  /// Deducts 1 carrot atomically. Returns false if insufficient balance.
  /// Used by swipe-right flow before calling generateFullRecipe.
  /// Does NOT save recipe - that happens after successful generation.
  Future<bool> deductCarrot(String userId) async {
    final userRef = _users.doc(userId);
    final txRef = _transactions(userId).doc();

    return await _firestore.runTransaction<bool>((transaction) async {
      final userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception('User not found');

      final data = userSnap.data()!;
      final subscriptionStatus =
          data['subscriptionStatus'] as String? ?? 'free';
      final isPremium = subscriptionStatus == 'premium';

      final carrots = data['carrots'] as Map<String, dynamic>? ?? {};
      final currentCarrots = (carrots['current'] as num?)?.toInt() ?? 0;

      // Premium users don't spend carrots
      if (isPremium) return true;

      // Check balance
      if (currentCarrots < 1) return false;

      // Deduct carrot
      transaction.update(userRef, {
        'carrots.current': currentCarrots - 1,
        'stats.totalCarrotsSpent': FieldValue.increment(1),
        'stats.recipesUnlocked': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Log transaction
      transaction.set(txRef, {
        'type': 'spend',
        'amount': -1,
        'balanceAfter': currentCarrots - 1,
        'description': 'Recipe unlock (swipe)',
        'timestamp': FieldValue.serverTimestamp(),
      });

      return true;
    });
  }

  // ============================================================
  // 2. UNLOCK RECIPE (ATOMIC TRANSACTION)
  // ============================================================

  /// Unlocks a recipe for the user:
  /// 1. Checks/applies lazy carrot reset
  /// 2. Deducts 1 carrot (free users only)
  /// 3. Creates savedRecipe entry
  /// 4. Logs transaction
  /// 5. Fetches & caches recipe_secrets for offline
  ///
  /// Returns true if successful, false if insufficient carrots.
  Future<bool> unlockRecipe(String userId, Recipe recipe) async {
    final userRef = _users.doc(userId);
    final savedRef = _savedRecipes(userId).doc(recipe.id);
    final txRef = _transactions(userId).doc();

    return await _firestore.runTransaction<bool>((transaction) async {
      // Check if already unlocked
      final savedSnap = await transaction.get(savedRef);
      if (savedSnap.exists && savedSnap.data()?['isUnlocked'] == true) {
        return true; // Already unlocked
      }

      // Get user data and apply lazy reset
      final userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception('User not found');

      final userData = userSnap.data()!;
      final subscriptionStatus =
          userData['subscriptionStatus'] as String? ?? 'free';
      final isPremium = subscriptionStatus == 'premium';

      final carrots = userData['carrots'] as Map<String, dynamic>? ?? {};
      final currentCarrots = (carrots['current'] as num?)?.toInt() ?? 0;

      // Check balance (free users need >= 1 carrot)
      if (!isPremium && currentCarrots < 1) {
        return false; // Not enough carrots
      }

      // Deduct carrot (free users only)
      if (!isPremium) {
        transaction.update(userRef, {
          'carrots.current': currentCarrots - 1,
          'stats.totalCarrotsSpent': FieldValue.increment(1),
          'stats.recipesUnlocked': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Log transaction
        transaction.set(txRef, {
          'type': 'spend',
          'amount': -1,
          'balanceAfter': currentCarrots - 1,
          'recipeId': recipe.id,
          'description': 'Unlocked: ${recipe.title}',
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        // Premium users still log for analytics
        transaction.update(userRef, {
          'stats.recipesUnlocked': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Create saved recipe entry with public data
      transaction.set(savedRef, {
        'recipeId': recipe.id,
        'isUnlocked': true,
        'unlockedAt': FieldValue.serverTimestamp(),
        'title': recipe.title,
        'imageUrl': recipe.imageUrl,
        'description': recipe.description,
        'ingredients': recipe.ingredients,
        'ingredientIds': recipe.ingredientIds,
        'energyLevel': recipe.energyLevel,
        'timeMinutes': recipe.timeMinutes,
        'calories': recipe.calories,
        'equipment': recipe.equipment,
        'dietaryTags': recipe.dietaryTags,
        'mealType': recipe.mealType,
        'skillLevel': recipe.skillLevel,
        'currentStep': 0,
        'savedAt': FieldValue.serverTimestamp(),
      });

      return true;
    });
  }

  /// Unlocks an AI preview (pantry-first swipe) in a single transaction.
  ///
  /// IMPORTANT: This should only be called after full recipe generation
  /// succeeds so free users are never charged for failed AI.
  ///
  /// Returns false if the user is non-premium and has insufficient carrots.
  Future<bool> unlockSwipePreview({
    required String userId,
    required Recipe recipe,
    required bool isPremium,
    required String unlockSource,
  }) async {
    final userRef = _users.doc(userId);
    final savedRef = _savedRecipes(userId).doc(recipe.id);
    final txRef = _transactions(userId).doc(recipe.id);
    final deckRef = _swipeDeck(userId).doc(recipe.id);

    return _firestore.runTransaction<bool>((transaction) async {
      final savedSnap = await transaction.get(savedRef);
      if (savedSnap.exists && savedSnap.data()?['isUnlocked'] == true) {
        transaction.set(deckRef, {
          'isConsumed': true,
          'consumedAt': FieldValue.serverTimestamp(),
          'lastSwipeDirection': 'right',
          'lastSwipedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return true;
      }

      final userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception('User not found');

      final userData = userSnap.data()!;
      final carrots = userData['carrots'] as Map<String, dynamic>? ?? {};
      final currentCarrots = (carrots['current'] as num?)?.toInt() ?? 0;

      if (!isPremium && currentCarrots < 1) {
        return false;
      }

      if (!isPremium) {
        transaction.update(userRef, {
          'carrots.current': currentCarrots - 1,
          'stats.totalCarrotsSpent': FieldValue.increment(1),
          'stats.recipesUnlocked': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        transaction.set(txRef, {
          'type': 'spend',
          'amount': -1,
          'balanceAfter': currentCarrots - 1,
          'recipeId': recipe.id,
          'source': unlockSource,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.update(userRef, {
          'stats.recipesUnlocked': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.set(savedRef, {
        ...recipe.toSavedRecipeFirestore(),
        'isUnlocked': true,
        'unlockedAt': FieldValue.serverTimestamp(),
        'unlockTxId': recipe.id,
        'unlockSource': unlockSource,
      }, SetOptions(merge: true));

      transaction.set(deckRef, {
        'isConsumed': true,
        'consumedAt': FieldValue.serverTimestamp(),
        'lastSwipeDirection': 'right',
        'lastSwipedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    });
  }

  /// Reserves an AI preview unlock immediately:
  /// - For free users: decrements carrots + writes deterministic ledger `transactions/{recipeId}`
  /// - Creates a placeholder `savedRecipes/{recipeId}` (instructions empty)
  /// - Marks the swipe card consumed
  ///
  /// This allows the app to navigate to the recipe page instantly and show
  /// a skeleton UI while full recipe generation runs.
  Future<bool> reserveSwipePreviewUnlock({
    required String userId,
    required RecipePreview preview,
    required bool isPremium,
    required String unlockSource,
  }) async {
    final userRef = _users.doc(userId);
    final savedRef = _savedRecipes(userId).doc(preview.id);
    final txRef = _transactions(userId).doc(preview.id);
    final deckRef = _swipeDeck(userId).doc(preview.id);

    return _firestore.runTransaction<bool>((transaction) async {
      final savedSnap = await transaction.get(savedRef);
      if (savedSnap.exists && savedSnap.data()?['isUnlocked'] == true) {
        transaction.set(deckRef, {
          'isConsumed': true,
          'consumedAt': FieldValue.serverTimestamp(),
          'lastSwipeDirection': 'right',
          'lastSwipedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return true;
      }

      final userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception('User not found');

      final userData = userSnap.data()!;
      final carrots = userData['carrots'] as Map<String, dynamic>? ?? {};
      final currentCarrots = (carrots['current'] as num?)?.toInt() ?? 0;

      if (!isPremium && currentCarrots < 1) {
        return false;
      }

      if (!isPremium) {
        transaction.update(userRef, {
          'carrots.current': currentCarrots - 1,
          'stats.totalCarrotsSpent': FieldValue.increment(1),
          'stats.recipesUnlocked': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        transaction.set(txRef, {
          'type': 'spend',
          'amount': -1,
          'balanceAfter': currentCarrots - 1,
          'recipeId': preview.id,
          'source': unlockSource,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.update(userRef, {
          'stats.recipesUnlocked': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      final imageUrl = (preview.imageUrl?.isNotEmpty == true)
          ? preview.imageUrl!
          : AppAssets.placeholderRecipe;

      transaction.set(savedRef, {
        'recipeId': preview.id,
        'title': preview.title,
        'titleLowercase': preview.title.toLowerCase(),
        'imageUrl': imageUrl,
        'description': preview.vibeDescription,
        'ingredients': preview.ingredients,
        'instructions': const <String>[],
        'ingredientIds': const <String>[],
        'energyLevel': preview.energyLevel,
        'timeMinutes': preview.estimatedTimeMinutes,
        'calories': preview.calories,
        'equipment': preview.equipmentIcons,
        'mealType': preview.mealType,
        'skillLevel': preview.skillLevel,
        'cuisine': preview.cuisine,
        'isPremium': isPremium,
        'isUnlocked': true,
        'unlockedAt': FieldValue.serverTimestamp(),
        'unlockTxId': preview.id,
        'unlockSource': unlockSource,
        'generationStatus': 'pending',
        'currentStep': 0,
        'savedAt': FieldValue.serverTimestamp(),
        'lastStepAt': FieldValue.serverTimestamp(),
        'isFavorite': false,
      }, SetOptions(merge: true));

      transaction.set(deckRef, {
        'isConsumed': true,
        'consumedAt': FieldValue.serverTimestamp(),
        'lastSwipeDirection': 'right',
        'lastSwipedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    });
  }

  /// Merges the finalized full recipe into `savedRecipes/{recipeId}` after
  /// a successful reserve.
  Future<void> upsertUnlockedSavedRecipeForSwipePreview({
    required String userId,
    required Recipe recipe,
    required String unlockSource,
  }) async {
    final savedRef = _savedRecipes(userId).doc(recipe.id);
    final deckRef = _swipeDeck(userId).doc(recipe.id);

    await savedRef.set({
      ...recipe.toSavedRecipeFirestore(),
      'isUnlocked': true,
      'unlockSource': unlockSource,
      'generationStatus': 'ready',
    }, SetOptions(merge: true));

    // Best-effort: ensure the swipe card stays consumed.
    await deckRef.set({
      'isConsumed': true,
      'consumedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Fetches recipe secrets (instructions) after unlock.
  /// Security rules ensure only unlocked/premium users can read.
  Future<List<String>> getRecipeSecrets(String recipeId) async {
    try {
      final doc = await _recipeSecrets.doc(recipeId).get();
      if (!doc.exists) return [];

      final data = doc.data();
      return List<String>.from(data?['instructions'] ?? []);
    } catch (e) {
      // Security rule will deny if not unlocked
      return [];
    }
  }

  // ============================================================
  // 3. PANTRY SYNC
  // ============================================================

  // ============================================================
  // 4. SWIPE DECK PERSISTENCE (per-user)
  // ============================================================

  /// Returns unconsumed swipe cards for the user.
  ///
  /// Note: We avoid composite indexes by querying only on `isConsumed`
  /// and sorting client-side if needed.
  Future<List<RecipePreview>> getUnconsumedSwipeCards(
    String userId, {
    int limit = 200,
  }) async {
    final snap = await _swipeDeck(
      userId,
    ).where('isConsumed', isEqualTo: false).limit(limit).get();

    final docs = snap.docs
        .where((d) => (d.data()['isDisliked'] as bool?) != true)
        .toList(growable: false);
    if (docs.isEmpty) return const <RecipePreview>[];

    // Sort by createdAt if present (stable-ish ordering).
    docs.sort((a, b) {
      final aTs = a.data()['createdAt'];
      final bTs = b.data()['createdAt'];
      final aDt = (aTs is Timestamp) ? aTs.toDate() : null;
      final bDt = (bTs is Timestamp) ? bTs.toDate() : null;
      if (aDt == null && bDt == null) return 0;
      if (aDt == null) return 1;
      if (bDt == null) return -1;
      return aDt.compareTo(bDt);
    });

    return docs.map(RecipePreview.fromFirestore).toList(growable: false);
  }

  /// Returns true if any unconsumed, non-disliked card in the given energy deck
  /// has an inputsSignature different from [inputsSignature].
  ///
  /// This is used for cache invalidation when pantry/toggles change.
  ///
  /// Note: We avoid composite indexes by querying only on `isConsumed` and
  /// filtering client-side.
  Future<bool> hasSwipeDeckSignatureMismatch(
    String userId, {
    required int energyLevel,
    required String inputsSignature,
    int limit = 200,
  }) async {
    final snap = await _swipeDeck(
      userId,
    ).where('isConsumed', isEqualTo: false).limit(limit).get();

    for (final doc in snap.docs) {
      final data = doc.data();
      if ((data['isDisliked'] as bool?) == true) continue;

      final e = (data['energyLevel'] as num?)?.toInt();
      if (e != energyLevel) continue;

      final sig = (data['inputsSignature'] as String?) ?? '';
      if (sig != inputsSignature) return true;
    }

    return false;
  }

  /// Persists new swipe cards (idempotent per card id).
  Future<void> upsertSwipeCards(
    String userId,
    List<RecipePreview> cards, {
    String? inputsSignature,
    String? promptVersion,
  }) async {
    if (cards.isEmpty) return;

    final batch = _firestore.batch();
    for (final card in cards) {
      final ref = _swipeDeck(userId).doc(card.id);
      batch.set(ref, {
        ...card.toFirestore(),
        'ideaKey': card.id,
        'isConsumed': false,
        if (inputsSignature != null) 'inputsSignature': inputsSignature,
        if (promptVersion != null) 'promptVersion': promptVersion,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<bool> hasIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String ideaKey,
  }) async {
    final docId = 'e${energyLevel}_$ideaKey';
    final snap = await _ideaKeyHistory(userId).doc(docId).get();
    return snap.exists;
  }

  Future<void> writeIdeaKeyHistory(
    String userId, {
    required int energyLevel,
    required String ideaKey,
    String? title,
    List<String>? ingredients,
  }) async {
    final docId = 'e${energyLevel}_$ideaKey';
    await _ideaKeyHistory(userId).doc(docId).set({
      'ideaKey': ideaKey,
      'energyLevel': energyLevel,
      'firstSeenAt': FieldValue.serverTimestamp(),
      if (title != null) 'title': title,
      if (ingredients != null) 'ingredients': ingredients,
    }, SetOptions(merge: true));
  }

  /// Marks a swipe card as consumed so it won't show again.
  Future<void> markSwipeCardConsumed(String userId, String cardId) async {
    try {
      await _swipeDeck(userId).doc(cardId).set({
        'isConsumed': true,
        'consumedAt': FieldValue.serverTimestamp(),
        'lastSwipeDirection': 'right',
        'lastSwipedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort; don't block UX.
    }
  }

  /// Marks a swipe card as disliked (left swipe) but keeps it unconsumed.
  ///
  /// This allows the user to see the card again on a future visit.
  Future<void> markSwipeCardDisliked(String userId, String cardId) async {
    try {
      await _swipeDeck(userId).doc(cardId).set({
        'isConsumed': false,
        'isDisliked': true,
        'lastSwipeDirection': 'left',
        'lastSwipedAt': FieldValue.serverTimestamp(),
        'dislikedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort; don't block UX.
    }
  }

  /// Clears the user's swipe deck (used for manual refresh).
  Future<void> clearSwipeDeck(String userId) async {
    const pageSize = 400;
    while (true) {
      final snap = await _swipeDeck(userId).limit(pageSize).get();
      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  /// Adds or updates pantry items.
  /// Used for manual additions and guest-to-user migration.
  Future<void> syncPantry(String userId, List<PantryItem> items) async {
    if (items.isEmpty) return;

    const batchSize = 500;

    for (var i = 0; i < items.length; i += batchSize) {
      final batch = _firestore.batch();
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;

      for (var j = i; j < end; j++) {
        final item = items[j];
        final docRef = _userPantry(
          userId,
        ).doc(item.id.isEmpty ? null : item.id);

        batch.set(docRef, item.toFirestore(), SetOptions(merge: true));
      }

      await batch.commit();
    }
  }

  /// Adds a single pantry item (for UI convenience).
  Future<String> addPantryItem(String userId, PantryItem item) async {
    final docRef = _userPantry(userId).doc();
    final newItem = PantryItem(
      id: docRef.id,
      userId: userId,
      name: item.name,
      normalizedName: item.name.toLowerCase().trim(),
      category: item.category,
      quantity: item.quantity,
      unit: item.unit,
      source: item.source,
      detectionConfidence: item.detectionConfidence,
      expiresAt: item.expiresAt,
      addedAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await docRef.set(newItem.toFirestore());
    return docRef.id;
  }

  /// Gets all pantry items for a user.
  Stream<List<PantryItem>> watchPantry(String userId) {
    return _userPantry(userId)
        .orderBy('name')
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => PantryItem.fromFirestore(d)).toList(),
        );
  }

  // ============================================================
  // 4. CONSUME INGREDIENTS (Kitchen Sync)
  // ============================================================

  /// Deducts ingredients from pantry after cooking a recipe.
  /// Creates audit log for traceability.
  Future<void> consumeIngredients(
    String userId,
    String recipeId,
    String recipeTitle,
    List<Map<String, dynamic>> usedIngredients,
  ) async {
    if (usedIngredients.isEmpty) return;

    await _firestore.runTransaction((transaction) async {
      final consumedItems = <Map<String, dynamic>>[];

      for (final used in usedIngredients) {
        final pantryItemId = used['pantryItemId'] as String?;
        final quantityUsed = (used['quantity'] as num?)?.toInt() ?? 1;

        if (pantryItemId == null) continue;

        final pantryRef = _userPantry(userId).doc(pantryItemId);
        final pantrySnap = await transaction.get(pantryRef);

        if (!pantrySnap.exists) continue;

        final currentQty =
            (pantrySnap.data()?['quantity'] as num?)?.toInt() ?? 0;
        final newQty = (currentQty - quantityUsed).clamp(0, 9999);

        if (newQty <= 0) {
          // Delete if depleted
          transaction.delete(pantryRef);
        } else {
          // Update quantity
          transaction.update(pantryRef, {
            'quantity': newQty,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        consumedItems.add({
          'pantryItemId': pantryItemId,
          'name': pantrySnap.data()?['name'] ?? '',
          'quantity': quantityUsed,
          'unit': pantrySnap.data()?['unit'] ?? 'pieces',
        });
      }

      // Create audit log
      if (consumedItems.isNotEmpty) {
        final logRef = _pantryLogs(userId).doc();
        transaction.set(logRef, {
          'actionType': 'consumed',
          'recipeId': recipeId,
          'recipeTitle': recipeTitle,
          'items': consumedItems,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  // ============================================================
  // 5. RECIPE DISCOVERY (Filter Panel)
  // ============================================================

  /// Gets recommended recipes with advanced filtering.
  /// Supports the Priority Hierarchy from requirements.
  Future<List<Recipe>> getRecommendedRecipes({
    int? energyLevel,
    String? mealType,
    List<String>? flavorProfile,
    List<String>? prepTags,
    List<String>? equipment,
    List<String>? dietaryTags,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _recipes
        .where('visibility', isEqualTo: 'public')
        .where('isActive', isEqualTo: true);

    // Apply filters (Firestore allows ONE array-contains-any per query)
    if (energyLevel != null) {
      query = query.where('energyLevel', isEqualTo: energyLevel);
    }

    if (mealType != null) {
      query = query.where('mealType', isEqualTo: mealType);
    }

    // Priority: Use the most specific array filter
    if (dietaryTags != null && dietaryTags.isNotEmpty) {
      query = query.where('dietaryTags', arrayContainsAny: dietaryTags);
    } else if (flavorProfile != null && flavorProfile.isNotEmpty) {
      query = query.where('flavorProfile', arrayContainsAny: flavorProfile);
    } else if (prepTags != null && prepTags.isNotEmpty) {
      query = query.where('prepTags', arrayContainsAny: prepTags);
    } else if (equipment != null && equipment.isNotEmpty) {
      query = query.where('equipment', arrayContainsAny: equipment);
    }

    // Order by popularity
    query = query.orderBy('stats.popularityScore', descending: true);

    // Pagination
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    query = query.limit(limit);

    final snap = await query.get();
    return snap.docs.map((d) => Recipe.fromFirestore(d)).toList();
  }

  // ============================================================
  // 6. GUEST-TO-USER MIGRATION (ATOMIC)
  // ============================================================

  /// Migrates guest's local data to Firestore after sign up.
  /// Uses a SINGLE atomic WriteBatch to prevent partial migration.
  /// Called after AuthService.signUp() succeeds.
  Future<void> migrateGuestData(
    String userId, {
    required List<PantryItem> guestPantry,
    List<String> likedRecipeIds = const [],
  }) async {
    if (guestPantry.isEmpty && likedRecipeIds.isEmpty) return;

    // CRITICAL: Use single WriteBatch for atomicity
    final batch = _firestore.batch();

    // Migrate pantry items
    for (final item in guestPantry) {
      final docRef = _userPantry(userId).doc();
      final migratedItem = PantryItem(
        id: docRef.id,
        userId: userId,
        name: item.name,
        normalizedName: item.normalizedName,
        category: item.category,
        quantity: item.quantity,
        unit: item.unit,
        source: 'manual',
        addedAt: item.addedAt,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      batch.set(docRef, migratedItem.toFirestore());
    }

    // Migrate liked recipes (stored as "interests" for future recommendations)
    for (final recipeId in likedRecipeIds) {
      final docRef = _savedRecipes(userId).doc(recipeId);
      batch.set(docRef, {
        'recipeId': recipeId,
        'isUnlocked': false,
        'isGuestInterest': true,
        'savedAt': FieldValue.serverTimestamp(),
      });
    }

    // ATOMIC COMMIT: All-or-nothing
    await batch.commit();
  }

  // ============================================================
  // 7. USER PROFILE
  // ============================================================

  /// Gets user profile.
  Future<UserProfile?> getUserProfile(String userId) async {
    final doc = await _users.doc(userId).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(doc);
  }

  /// Watches user profile for real-time updates.
  Stream<UserProfile?> watchUserProfile(String userId) {
    return _users.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromFirestore(doc);
    });
  }

  /// Creates initial user profile after signup.
  Future<void> createUserProfile({
    required String uid,
    String? email,
    String? displayName,
    bool isAnonymous = false,
  }) async {
    final userRef = _users.doc(uid);
    final existing = await userRef.get();

    if (existing.exists) {
      // Update last login
      await userRef.update({'lastLoginAt': FieldValue.serverTimestamp()});
      return;
    }

    await userRef.set({
      'uid': uid,
      'email': email,
      'displayName': displayName ?? 'User',
      'isAnonymous': isAnonymous,
      'subscriptionStatus': 'free',
      'carrots': {
        'current': 5,
        'max': 5,
        'lastResetAt': FieldValue.serverTimestamp(),
      },
      'preferences': {
        'dietaryRestrictions': [],
        'allergies': [],
        'defaultEnergyLevel': 2,
        'preferredCuisines': [],
        'pantryFlexibility': 'lenient',
      },
      'appState': {'hasSeenOnboarding': false, 'hasSeenTutorials': {}},
      'stats': {'recipesUnlocked': 0, 'totalCarrotsSpent': 0, 'scanCount': 0},
      'accountCreatedAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Updates user preferences (allergies, diets, cuisines, etc.)
  Future<void> updateUserPreferences(
    String userId,
    Map<String, dynamic> preferences,
  ) async {
    final userRef = _users.doc(userId);

    // Build update map with preferences prefix
    final updateData = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    for (final entry in preferences.entries) {
      updateData['preferences.${entry.key}'] = entry.value;
    }

    await userRef.update(updateData);
  }

  /// Saves an AI-generated recipe to user's saved recipes
  Future<void> saveAiGeneratedRecipe(String userId, Recipe recipe) async {
    final savedRef = _savedRecipes(userId).doc(recipe.id);

    await savedRef.set({
      'recipeId': recipe.id,
      'isUnlocked': true,
      'isAiGenerated': true,
      'unlockedAt': FieldValue.serverTimestamp(),
      'title': recipe.title,
      'imageUrl': recipe.imageUrl,
      'description': recipe.description,
      'ingredients': recipe.ingredients,
      'instructions': recipe.instructions,
      'energyLevel': recipe.energyLevel,
      'timeMinutes': recipe.timeMinutes,
      'calories': recipe.calories,
      'equipment': recipe.equipment,
      'currentStep': 0,
      'savedAt': FieldValue.serverTimestamp(),
    });

    // Increment recipe count in user stats
    await _users.doc(userId).update({
      'stats.recipesUnlocked': FieldValue.increment(1),
    });
  }

  /// Publishes a recipe into the global recipes collection so all users can
  /// swipe/browse it.
  ///
  /// Note: In a stricter production setup this should be done by backend-only
  /// code (Cloud Functions) to prevent spam. For now we gate via Firestore rules.
  Future<void> publishRecipeToGlobal({
    required String userId,
    required Recipe recipe,
  }) async {
    final docRef = _recipes.doc(recipe.id);

    await docRef.set({
      ...recipe.toFirestore(),
      'isActive': true,
      'visibility': 'public',
      'createdBy': userId,
      'source': 'ai_user',
      // Keep createdAt stable if already present.
      'createdAt': FieldValue.serverTimestamp(),
      // Ensure stats exists for ordering.
      'stats': {
        'likes': recipe.stats.likes,
        'popularityScore': recipe.stats.popularityScore,
      },
    }, SetOptions(merge: true));
  }

  // ============================================================
  // 9. AI RECIPE HISTORY
  // ============================================================

  /// Gets the user's AI-generated recipe history (latest 3)
  Stream<List<Map<String, dynamic>>> getAiRecipeHistory(String userId) {
    return _firestore
        .collection('ai_recipe_requests')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(3)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList(),
        );
  }

  // ============================================================
  // 10. LIKE/FAVORITE RECIPES (Heart Icon)
  // ============================================================

  /// Toggle like status for a recipe
  Future<bool> toggleRecipeLike(String userId, String recipeId) async {
    final userRef = _users.doc(userId);
    final userDoc = await userRef.get();
    final likedRecipes = List<String>.from(
      userDoc.data()?['likedRecipeIds'] ?? [],
    );

    final isLiked = likedRecipes.contains(recipeId);

    if (isLiked) {
      likedRecipes.remove(recipeId);
    } else {
      likedRecipes.add(recipeId);
    }

    await userRef.update({
      'likedRecipeIds': likedRecipes,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return !isLiked; // Return new like status
  }

  /// Check if a recipe is liked
  Future<bool> isRecipeLiked(String userId, String recipeId) async {
    final userDoc = await _users.doc(userId).get();
    final likedRecipes = List<String>.from(
      userDoc.data()?['likedRecipeIds'] ?? [],
    );
    return likedRecipes.contains(recipeId);
  }

  /// Get all liked recipe IDs
  Stream<List<String>> getLikedRecipeIds(String userId) {
    return _users.doc(userId).snapshots().map((doc) {
      return List<String>.from(doc.data()?['likedRecipeIds'] ?? []);
    });
  }
}
