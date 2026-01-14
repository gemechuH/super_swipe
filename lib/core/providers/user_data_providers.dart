import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/core/models/user_profile.dart';
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/config/pantry_constants.dart';
import 'package:super_swipe/core/providers/firestore_providers.dart';
import 'package:super_swipe/core/services/user_service.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/core/providers/guest_state_provider.dart';

/// Stream user profile (real-time updates)
/// Implements graceful loading for new accounts:
/// - On first access for a new account, the Firestore document may not exist yet
/// - Instead of showing an error, we wait up to 5 seconds for the document to be created
/// - This handles the race condition between Auth completion and Firestore doc creation
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authState = ref.watch(authProvider);
  final userService = ref.watch(userServiceProvider);

  if (authState.user == null) {
    return Stream.value(null);
  }

  final userId = authState.user!.uid;

  // Use a StreamController to handle graceful loading for new accounts
  return _gracefulProfileStream(userService, userId);
});

/// Creates a stream that waits gracefully for new user profile creation
Stream<UserProfile?> _gracefulProfileStream(
  UserService userService,
  String userId,
) async* {
  final stopTime = DateTime.now().add(const Duration(seconds: 5));
  var hasYieldedProfile = false;

  await for (final profile in userService.watchUserProfile(userId)) {
    if (profile != null) {
      hasYieldedProfile = true;
      yield profile;
    } else {
      // Document doesn't exist yet
      if (DateTime.now().isBefore(stopTime) && !hasYieldedProfile) {
        // During grace period, yield null but don't error
        // This keeps the UI in a "loading" state rather than error
        yield null;
        // Small delay to prevent tight loop
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        // After grace period, yield null (no profile)
        yield null;
      }
    }
  }
}

/// Stream pantry items (real-time updates)
final pantryItemsProvider = StreamProvider<List<PantryItem>>((ref) {
  final authState = ref.watch(authProvider);
  final pantryService = ref.watch(pantryServiceProvider);

  if (authState.user == null) {
    return Stream.value([]);
  }

  if (authState.user!.isAnonymous) {
    // Stream guest pantry updates from local state.
    final controller = StreamController<List<PantryItem>>(sync: true);

    controller.add(ref.read(guestPantryProvider));
    final sub = ref.listen<List<PantryItem>>(
      guestPantryProvider,
      (_, next) => controller.add(next),
    );

    ref.onDispose(() {
      sub.close();
      controller.close();
    });

    return controller.stream;
  }

  return pantryService.watchUserPantry(authState.user!.uid);
});

/// Get pantry items count
final pantryCountProvider = Provider<int>((ref) {
  final pantryItems = ref.watch(pantryItemsProvider);
  return pantryItems.maybeWhen(data: (items) => items.length, orElse: () => 0);
});

/// Fetch pantry categories (Cached & Server-updated)
final pantryCategoriesProvider = FutureProvider<List<PantryCategory>>((ref) {
  final configService = ref.watch(configServiceProvider);
  return configService.getPantryCategories();
});
