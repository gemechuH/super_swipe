import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:super_swipe/core/models/pantry_discovery_settings.dart';
import 'package:super_swipe/core/models/user_profile.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/services/firestore_service.dart';
import 'package:super_swipe/features/swipe/services/swipe_inputs_signature.dart';

/// Service for user profile management in Firestore
class UserService {
  final FirestoreService _firestoreService;

  UserService(this._firestoreService);

  /// Create user profile on signup or first login
  Future<void> createUserProfile(User firebaseUser) async {
    final userDoc = _firestoreService.users.doc(firebaseUser.uid);

    final snapshot = await userDoc.get();
    if (!snapshot.exists) {
      await userDoc.set({
        'uid': firebaseUser.uid,
        'email': firebaseUser.email,
        'displayName': firebaseUser.displayName ?? 'User',
        'isAnonymous': firebaseUser.isAnonymous,
        'subscriptionStatus': 'free',
        'accountCreatedAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
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
          'pantryDiscovery': {'includeBasics': true, 'willingToShop': false},
        },
        'appState': {
          'hasSeenOnboarding': false,
          'hasSeenTutorials': {'swipe': false, 'pantry': false},
          'swipeInputsSignature': '',
          'swipeInputsUpdatedAt': FieldValue.serverTimestamp(),
        },
        'stats': {'recipesUnlocked': 0, 'totalCarrotsSpent': 0},
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Update last login
      await userDoc.update({'lastLoginAt': FieldValue.serverTimestamp()});
    }
  }

  /// Get user profile (one-time fetch)
  Future<UserProfile?> getUserProfile(String userId) async {
    final doc = await _firestoreService.users.doc(userId).get();
    if (doc.exists) {
      return UserProfile.fromFirestore(doc);
    }
    return null;
  }

  /// Stream user profile (real-time updates)
  Stream<UserProfile?> watchUserProfile(String userId) {
    return _firestoreService.users.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromFirestore(doc);
    });
  }

  /// Update user profile
  Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> updates,
  ) async {
    await _firestoreService.users.doc(userId).update({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update dietary preferences
  Future<void> updatePreferences(
    String userId,
    UserPreferences preferences,
  ) async {
    await updateUserProfile(userId, {'preferences': preferences.toMap()});
  }

  Future<void> updateSwipeInputsSignature(
    String userId, {
    required String swipeInputsSignature,
  }) async {
    await updateUserProfile(userId, {
      'appState.swipeInputsSignature': swipeInputsSignature,
      'appState.swipeInputsUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updatePantryDiscoverySettings(
    String userId,
    PantryDiscoverySettings settings,
  ) async {
    final pantrySnap = await _firestoreService
        .userPantry(userId)
        .orderBy('name')
        .get();
    final pantryNames = pantrySnap.docs
        .map((d) => (d.data() as Map<String, dynamic>?) ?? {})
        .map((m) => (m['normalizedName'] ?? m['name'] ?? '').toString())
        .toList(growable: false);

    final sig = buildSwipeInputsSignature(
      pantryIngredientNames: pantryNames,
      includeBasics: settings.includeBasics,
      willingToShop: settings.willingToShop,
    );

    await updateUserProfile(userId, {
      'preferences.pantryDiscovery': settings.toMap(),
      'appState.swipeInputsSignature': sig,
      'appState.swipeInputsUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Spend carrots (with transaction to prevent race conditions)
  /// Fix #3 & #9: Enhanced with validation and proper DI
  Future<bool> spendCarrots(String userId, int amount) async {
    if (amount <= 0) {
      throw ArgumentError('Amount must be positive');
    }

    final userRef = _firestoreService.users.doc(userId);

    return await _firestoreService.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);

      if (!snapshot.exists) {
        throw StateError('User not found: $userId');
      }

      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) {
        throw StateError('User data is null for: $userId');
      }

      final carrots = (data['carrots'] as Map<String, dynamic>?) ?? {};
      final currentCarrots = (carrots['current'] as num?)?.toInt() ?? 0;

      if (currentCarrots < amount) {
        return false; // Insufficient carrots
      }

      transaction.update(userRef, {
        'carrots.current': currentCarrots - amount,
        'stats.totalCarrotsSpent': FieldValue.increment(amount),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    });
  }

  /// Atomically unlock and save recipe
  /// Fix #15: Prevents race condition where carrots are spent but recipe not saved
  Future<bool> unlockRecipe(String userId, Recipe recipe) async {
    final userRef = _firestoreService.users.doc(userId);
    final recipeRef = _firestoreService.userSavedRecipes(userId).doc(recipe.id);

    return await _firestoreService.instance.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);

      if (!userSnapshot.exists) throw StateError('User not found');

      // Prevent double-spending: if already unlocked/saved, do nothing.
      final savedSnapshot = await transaction.get(recipeRef);
      if (savedSnapshot.exists) {
        return true;
      }

      final data = userSnapshot.data() as Map<String, dynamic>?;
      final carrots = (data?['carrots'] as Map<String, dynamic>?) ?? {};
      var currentCarrots = (carrots['current'] as num?)?.toInt() ?? 0;
      final subscriptionStatus =
          (data?['subscriptionStatus'] as String?)?.toLowerCase() ?? 'free';
      final isPremium = subscriptionStatus == 'premium';

      if (!isPremium && currentCarrots < 1) return false;

      // Update user stats (and carrots for free users)
      final userUpdates = <String, dynamic>{
        'stats.recipesUnlocked': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!isPremium) {
        userUpdates.addAll({
          'carrots.current': currentCarrots - 1,
          'stats.totalCarrotsSpent': FieldValue.increment(1),
        });
      }
      transaction.update(userRef, userUpdates);

      // Save recipe
      transaction.set(recipeRef, recipe.toSavedRecipeFirestore());

      return true;
    });
  }

  /// Reset carrots (weekly reset or manual)
  Future<void> resetCarrots(String userId) async {
    await _firestoreService.users.doc(userId).update({
      'carrots.current': 5,
      'carrots.lastResetAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Mark onboarding as complete
  Future<void> markOnboardingComplete(String userId) async {
    await updateUserProfile(userId, {'appState.hasSeenOnboarding': true});
  }

  /// Mark tutorial as complete
  Future<void> markTutorialComplete(String userId, String tutorialKey) async {
    await updateUserProfile(userId, {
      'appState.hasSeenTutorials.$tutorialKey': true,
    });
  }

  /// Increment recipes unlocked count
  Future<void> incrementRecipesUnlocked(String userId) async {
    await _firestoreService.users.doc(userId).update({
      'stats.recipesUnlocked': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
