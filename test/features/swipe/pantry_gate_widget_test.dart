import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/providers/recipe_providers.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/features/swipe/screens/swipe_screen.dart';

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

void main() {
  testWidgets('Swipe shows pantry gate when <3 non-seasoning items', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/swipe',
      routes: [
        GoRoute(
          path: '/swipe',
          builder: (context, state) => const SwipeScreen(),
        ),
        GoRoute(
          path: '/pantry',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Pantry Screen'))),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            () => _FakeAuthNotifier(_FakeUser(uid: 'u1', isAnonymous: false)),
          ),
          pantryItemsProvider.overrideWith((ref) {
            return Stream.value(<PantryItem>[_item('chicken'), _item('rice')]);
          }),
          includeBasicsProvider.overrideWithValue(true),
          userProfileProvider.overrideWith((ref) => Stream.value(null)),
          savedRecipesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Add at least 3 ingredients to start'), findsOneWidget);
    expect(find.text('Go to Pantry'), findsOneWidget);

    await tester.tap(find.text('Go to Pantry'));
    await tester.pumpAndSettle();

    expect(find.text('Pantry Screen'), findsOneWidget);
  });
}
