import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/providers/app_state_provider.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/features/auth/screens/login_screen.dart';
import 'package:super_swipe/features/auth/screens/signup_screen.dart';
import 'package:super_swipe/features/home/screens/home_screen.dart';
import 'package:super_swipe/features/onboarding/screens/onboarding_screen.dart';
import 'package:super_swipe/features/pantry/screens/pantry_screen.dart';
import 'package:super_swipe/features/profile/screens/profile_screen.dart';
import 'package:super_swipe/features/recipes/screens/recipes_screen.dart';
import 'package:super_swipe/features/recipes/screens/recipe_detail_screen.dart';
import 'package:super_swipe/features/settings/screens/settings_screen.dart';
import 'package:super_swipe/features/ai/screens/ai_generation_screen.dart';
import 'package:super_swipe/features/shell/main_wrapper.dart';
import 'package:super_swipe/features/swipe/screens/swipe_screen.dart';
import 'package:super_swipe/core/models/recipe.dart';

/// Route names
class AppRoutes {
  AppRoutes._();
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/home';
  static const String pantry = '/pantry';
  static const String recipes = '/recipes';
  static const String recipeDetail = '/recipes/:recipeId';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String aiGenerate = '/ai-generate';
  static const String swipe = '/swipe';
}

const _publicRoutes = [AppRoutes.onboarding, AppRoutes.login, AppRoutes.signup];

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Router provider with auth redirect logic
final appRouterProvider = Provider<GoRouter>((ref) {
  // Do not watch here to avoid rebuilding the router on auth changes
  // The _RouterRefreshStream handles triggering redirects

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.onboarding,
    // debugLogDiagnostics: true,
    refreshListenable: _RouterRefreshStream(ref),
    redirect: (BuildContext context, GoRouterState state) {
      // Read current state during redirect
      final authState = ref.read(authProvider);
      final appState = ref.read(appStateProvider);
      final isSignedIn = authState.isSignedIn;
      final hasSeenWelcome = appState.hasSeenWelcome;
      // GoRouter 14.x: use matchedLocation for current path
      final currentPath = state.matchedLocation;
      final isPublicRoute = _publicRoutes.contains(currentPath);

      // debugPrint(
      //     'Router Redirect: path=$currentPath, isSignedIn=$isSignedIn, hasSeen=$hasSeenWelcome');

      // User NOT signed in
      if (!isSignedIn) {
        if (hasSeenWelcome && currentPath == AppRoutes.onboarding) {
          return AppRoutes.login;
        }
        if (!isPublicRoute) {
          return AppRoutes.onboarding;
        }
        return null;
      }

      // User IS signed in
      if (isSignedIn && isPublicRoute) {
        // Allow anonymous users to access login/signup pages
        if (authState.user?.isAnonymous == true) {
          if (currentPath == AppRoutes.login ||
              currentPath == AppRoutes.signup) {
            return null;
          }
        }
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      // Public routes
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        name: 'signup',
        builder: (context, state) => const SignupScreen(),
      ),

      GoRoute(
        path: AppRoutes.swipe,
        name: 'swipe',
        builder: (context, state) => const SwipeScreen(),
      ),
      GoRoute(
        path: AppRoutes.recipeDetail,
        name: 'recipeDetail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final recipeId = state.pathParameters['recipeId'] ?? '';
          final extra = state.extra;

          Recipe? initialRecipe;
          var assumeUnlocked = false;
          var openDirections = false;
          var isGenerating = false;

          if (extra is Recipe) {
            initialRecipe = extra;
          } else if (extra is Map) {
            final candidate = extra['recipe'];
            if (candidate is Recipe) {
              initialRecipe = candidate;
            }
            assumeUnlocked = extra['assumeUnlocked'] == true;
            openDirections = extra['openDirections'] == true;
            isGenerating = extra['isGenerating'] == true;
          }
          return RecipeDetailScreen(
            recipeId: recipeId,
            initialRecipe: initialRecipe,
            assumeUnlocked: assumeUnlocked,
            openDirections: openDirections,
            isGenerating: isGenerating,
          );
        },
      ),

      // AI Generation (outside shell - fullscreen experience)
      // MOVED INSIDE ShellRoute for navbar visibility

      // Protected routes with bottom navigation
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainWrapper(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            name: 'home',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: AppRoutes.pantry,
            name: 'pantry',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PantryScreen()),
          ),
          GoRoute(
            path: AppRoutes.recipes,
            name: 'recipes',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: RecipesScreen()),
          ),
          GoRoute(
            path: AppRoutes.settings,
            name: 'settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
          // AI Generation - now inside shell for navbar
          GoRoute(
            path: AppRoutes.aiGenerate,
            name: 'aiGenerate',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AiGenerationScreen()),
          ),
          // Keep profile for backwards compat but redirect to settings
          GoRoute(
            path: AppRoutes.profile,
            name: 'profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProfileScreen()),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
});

class _RouterRefreshStream extends ChangeNotifier {
  _RouterRefreshStream(this._ref) {
    _ref.listen(authProvider, (_, _) => notifyListeners());
    _ref.listen(appStateProvider, (_, _) => notifyListeners());
  }
  final Ref _ref;
}
