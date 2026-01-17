import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/core/models/pantry_discovery_settings.dart';
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/models/user_profile.dart';
import 'package:super_swipe/core/providers/firestore_providers.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/services/user_service.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/features/pantry/screens/pantry_screen.dart';

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

UserProfile _profile({PantryDiscoverySettings? discovery}) {
  return UserProfile(
    uid: 'u1',
    email: 'u1@example.com',
    displayName: 'User',
    isAnonymous: false,
    subscriptionStatus: 'free',
    carrots: const Carrots(current: 5, max: 5),
    preferences: UserPreferences(
      pantryDiscovery: discovery ?? const PantryDiscoverySettings(),
    ),
    appState: const AppState(),
    stats: const UserStats(),
  );
}

class _FakeUserService extends Fake implements UserService {
  final StreamController<UserProfile?> controller;
  PantryDiscoverySettings _settings;

  _FakeUserService(this.controller, this._settings);

  @override
  Future<void> updatePantryDiscoverySettings(
    String userId,
    PantryDiscoverySettings settings,
  ) async {
    _settings = settings;
    controller.add(_profile(discovery: _settings));
  }
}

void main() {
  testWidgets('Pantry shows toggles and persists changes', (tester) async {
    final controller = StreamController<UserProfile?>.broadcast();
    addTearDown(controller.close);

    controller.add(_profile());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            () => _FakeAuthNotifier(_FakeUser(uid: 'u1', isAnonymous: false)),
          ),
          userProfileProvider.overrideWith((ref) => controller.stream),
          pantryItemsProvider.overrideWith(
            (ref) => Stream.value(<PantryItem>[_item('chicken')]),
          ),
          userServiceProvider.overrideWithValue(
            _FakeUserService(controller, const PantryDiscoverySettings()),
          ),
        ],
        child: const MaterialApp(home: PantryScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Discovery settings'), findsOneWidget);
    expect(find.text('Include basics'), findsOneWidget);
    expect(find.text('Willing to shop'), findsOneWidget);

    final includeRowFinder = find.ancestor(
      of: find.text('Include basics'),
      matching: find.byType(Row),
    );
    final includeSwitchFinder = find.descendant(
      of: includeRowFinder,
      matching: find.byType(Switch),
    );

    expect(includeSwitchFinder, findsOneWidget);

    // Default is true per PantryDiscoverySettings.
    final includeSwitch = tester.widget<Switch>(includeSwitchFinder);
    expect(includeSwitch.value, isTrue);

    await tester.tap(includeSwitchFinder);
    await tester.pumpAndSettle();

    // After persistence roundtrip, UI should reflect new value.
    final includeSwitchAfter = tester.widget<Switch>(includeSwitchFinder);
    expect(includeSwitchAfter.value, isFalse);
  });
}
