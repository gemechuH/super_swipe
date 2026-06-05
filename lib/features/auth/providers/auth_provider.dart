import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/features/auth/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auth state model
enum AuthLoadingAction {
  emailSignIn,
  emailSignUp,
  googleSignIn,
  appleSignIn,
  anonymousSignIn,
  passwordReset,
}

class AuthState {
  final User? user;
  final String? displayName; // Explicit display name from Firestore/Auth
  final bool isLoading;
  final AuthLoadingAction? loadingAction;
  final String? error;
  final bool hasSeenOnboarding;

  const AuthState({
    this.user,
    this.displayName,
    this.isLoading = false,
    this.loadingAction,
    this.error,
    this.hasSeenOnboarding = false,
  });

  bool get isSignedIn => user != null;

  AuthState copyWith({
    User? user,
    String? displayName,
    bool? isLoading,
    AuthLoadingAction? loadingAction,
    String? error,
    bool? hasSeenOnboarding,
    bool clearError = false,
    bool clearUser = false,
    bool clearLoadingAction = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      displayName: clearUser ? null : (displayName ?? this.displayName),
      isLoading: isLoading ?? this.isLoading,
      loadingAction: clearLoadingAction
          ? null
          : (loadingAction ?? this.loadingAction),
      error: clearError ? null : (error ?? this.error),
      hasSeenOnboarding: hasSeenOnboarding ?? this.hasSeenOnboarding,
    );
  }
}

/// AuthService provider
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Auth Notifier using modern Riverpod syntax
class AuthNotifier extends Notifier<AuthState> {
  late final AuthService _authService;
  StreamSubscription<User?>? _authSubscription;
  static const _onboardingKey = 'has_seen_onboarding';

  // Temporary storage for display name during signup to bridge the gap
  // between local creation and Firebase stream updates.
  String? _pendingDisplayName;

  @override
  AuthState build() {
    _authService = ref.watch(authServiceProvider);
    _loadOnboardingState();

    _authSubscription?.cancel();
    // Use userChanges instead of authStateChanges to catch profile updates (like displayName)
    _authSubscription = _authService.userChanges.listen((user) {
      _handleUserChange(user);
    });

    ref.onDispose(() => _authSubscription?.cancel());

    return AuthState(user: _authService.currentUser, isLoading: false);
  }

  Future<void> _handleUserChange(User? user) async {
    String? name = user?.displayName;

    // 1. Check pending display name (highest priority during signup)
    if ((name == null || name.isEmpty) && _pendingDisplayName != null) {
      name = _pendingDisplayName;
    }

    // 2. If still missing, try fetching from Firestore (REMOVED for Supabase migration)
    /*
    if (user != null && !user.isAnonymous && (name == null || name.isEmpty)) {
      try {
        final profile = await _authService.getUserProfile(user.uid);
        if (profile != null && profile['displayName'] != null) {
          name = profile['displayName'];
        }
      } catch (e) {
        // Ignore error, fallback to null
      }
    }
    */

    // 3. Fallback to existing state if valid
    if ((name == null || name.isEmpty) &&
        user != null &&
        state.user?.uid == user.uid &&
        state.displayName != null &&
        state.displayName!.isNotEmpty) {
      name = state.displayName;
    }

    state = state.copyWith(
      user: user,
      displayName: name,
      isLoading: false,
      clearLoadingAction: true,
      clearUser: user == null,
      clearError: true,
    );
  }

  Future<void> _loadOnboardingState() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_onboardingKey) ?? false;
    state = state.copyWith(hasSeenOnboarding: seen);
  }

  Future<void> setOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
    state = state.copyWith(hasSeenOnboarding: true);
  }

  Future<bool> signIn({required String email, required String password}) async {
    state = state.copyWith(
      isLoading: true,
      loadingAction: AuthLoadingAction.emailSignIn,
      clearError: true,
    );
    final result = await _authService.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (result.success) {
      // _handleUserChange will be called by the listener, but we can set state optimistically if needed
      // For now, let the listener handle it to ensure consistency
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        clearLoadingAction: true,
        error: result.errorMessage,
      );
      return false;
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = state.copyWith(
      isLoading: true,
      loadingAction: AuthLoadingAction.emailSignUp,
      clearError: true,
    );

    // Store name temporarily to bridge the gap until Firebase stream updates
    _pendingDisplayName = displayName;

    final result = await _authService.createUserWithEmailAndPassword(
      email: email,
      password: password,
      displayName: displayName,
    );
    if (result.success) {
      // Explicitly set the display name since we just created it
      state = state.copyWith(
        user: result.user,
        displayName: displayName,
        isLoading: false,
        clearLoadingAction: true,
        hasSeenOnboarding: true,
      );

      // ==========================================
      // GUEST-TO-USER MIGRATION
      // ==========================================
      // If the user was previously a guest with local pantry data,
      // migrate that data to Firestore now.
      // Note: The actual migration is triggered from the UI layer
      // via guestStateProvider.migrateToFirestore(userId) after
      // this method returns true. This ensures proper ref access.
      // ==========================================

      // Force a reload after a short delay to ensure the profile update propagates
      // and triggers the userChanges stream with the correct name.
      Future.delayed(const Duration(seconds: 1), () async {
        final user = _authService.currentUser;
        if (user != null) {
          await user.reload();
        }
      });

      // Clear pending name after a safe delay
      Future.delayed(const Duration(seconds: 10), () {
        _pendingDisplayName = null;
      });

      return true;
    } else {
      _pendingDisplayName = null;
      state = state.copyWith(
        isLoading: false,
        clearLoadingAction: true,
        error: result.errorMessage,
      );
      return false;
    }
  }

  Future<bool> signInWithGoogle() async {
    state = state.copyWith(
      isLoading: true,
      loadingAction: AuthLoadingAction.googleSignIn,
      clearError: true,
    );
    final result = await _authService.signInWithGoogle();
    if (result.success) {
      return true;
    } else {
      // Only show error if not cancelled
      if (result.errorMessage != 'Sign in cancelled by user') {
        state = state.copyWith(
          isLoading: false,
          clearLoadingAction: true,
          error: result.errorMessage,
        );
      } else {
        state = state.copyWith(isLoading: false, clearLoadingAction: true);
      }
      return false;
    }
  }

  Future<bool> signInAnonymously() async {
    state = state.copyWith(
      isLoading: true,
      loadingAction: AuthLoadingAction.anonymousSignIn,
      clearError: true,
    );
    final result = await _authService.signInAnonymously();
    if (result.success) {
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        clearLoadingAction: true,
        error: result.errorMessage,
      );
      return false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(
      isLoading: true,
      clearLoadingAction: true,
    );
    await _authService.signOut();
    state = state.copyWith(isLoading: false, clearUser: true);
  }

  Future<bool> sendPasswordReset({required String email}) async {
    state = state.copyWith(
      isLoading: true,
      loadingAction: AuthLoadingAction.passwordReset,
      clearError: true,
    );
    final result = await _authService.sendPasswordResetEmail(email: email);
    state = state.copyWith(
      isLoading: false,
      clearLoadingAction: true,
      error: result.success ? null : result.errorMessage,
    );
    return result.success;
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// Main auth provider
final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  () => AuthNotifier(),
);

/// Convenience providers
final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(authProvider).isSignedIn,
);
final currentUserProvider = Provider<User?>(
  (ref) => ref.watch(authProvider).user,
);
