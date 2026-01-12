import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_preview/device_preview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Fast boot: render immediately, initialize in the background.
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    _startInit();
  }

  void _startInit() {
    setState(() {
      _initFuture = _init().catchError((error, stack) {
        debugPrint('Bootstrap error: $error');
        debugPrint('Stack trace: $stack');
        throw error; // Re-throw so FutureBuilder shows error screen
      });
    });
  }

  Future<void> _init() async {
    final sw = Stopwatch()..start();

    // 1) Load env quickly (do not hard-crash if missing).
    try {
      await dotenv.load(fileName: '.env').timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('Warning: Could not load .env: $e');
    }

    // 2) Initialize Firebase robustly.
    await _initializeFirebase().timeout(const Duration(seconds: 10));

    // 3) Configure Firestore (after Firebase init).
    // Web IndexedDB can get into a corrupted state (often after "clear site data"),
    // causing Firestore to refuse opening persistence.
    // Disable persistence on web to keep the app usable.
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: !kIsWeb,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    if (kDebugMode) {
      debugPrint('Bootstrap init done in ${sw.elapsedMilliseconds}ms');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Important: Don't create ProviderScope / router until Firebase is ready,
    // otherwise FirebaseAuth / Firestore access can throw [core/no-app].
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _BootstrapLoadingScreen(),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _BootstrapErrorScreen(
              error: snapshot.error,
              onRetry: _startInit,
            ),
          );
        }

        // DevicePreview for development/testing
        return DevicePreview(
          enabled: !kReleaseMode,
          builder: (context) => const ProviderScope(child: SuperSwipeApp()),
        );
      },
    );
  }
}

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: const AppPageLoading(),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _BootstrapErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                'Startup failed',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Robustly initializes Firebase across platforms:
/// - Android/iOS: usually auto-initialized from native config; try no-options first.
/// - Web/Desktop: initialize with options from `firebase_options.dart` (.env-backed).
/// - Duplicate app: ignored (safe).
Future<void> _initializeFirebase() async {
  // If a Dart-side app is already registered, we are done.
  if (Firebase.apps.isNotEmpty) return;

  // Try native config first on mobile.
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      await Firebase.initializeApp();
      return;
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app') return;
      // Fall through to explicit options.
    } catch (_) {
      // Fall through to explicit options.
    }
  }

  // Fallback: explicit options (needed for web/desktop).
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') return;
    rethrow;
  }
}

class SuperSwipeApp extends ConsumerWidget {
  const SuperSwipeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    final baseTheme = AppTheme.lightTheme;
    TextTheme withDmSansFallback(TextTheme theme) {
      final dm = GoogleFonts.dmSansTextTheme(theme);
      TextStyle? f(TextStyle? s) => s?.copyWith(
        fontFamilyFallback: const <String>['Arial', 'sans-serif'],
      );
      return dm.copyWith(
        displayLarge: f(dm.displayLarge),
        displayMedium: f(dm.displayMedium),
        displaySmall: f(dm.displaySmall),
        headlineLarge: f(dm.headlineLarge),
        headlineMedium: f(dm.headlineMedium),
        headlineSmall: f(dm.headlineSmall),
        titleLarge: f(dm.titleLarge),
        titleMedium: f(dm.titleMedium),
        titleSmall: f(dm.titleSmall),
        bodyLarge: f(dm.bodyLarge),
        bodyMedium: f(dm.bodyMedium),
        bodySmall: f(dm.bodySmall),
        labelLarge: f(dm.labelLarge),
        labelMedium: f(dm.labelMedium),
        labelSmall: f(dm.labelSmall),
      );
    }

    return MaterialApp.router(
      title: 'Super Swipe',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: withDmSansFallback(baseTheme.textTheme),
        primaryTextTheme: withDmSansFallback(baseTheme.primaryTextTheme),
      ),
      routerConfig: router,
      // locale: DevicePreview.locale(context),
      // builder: DevicePreview.appBuilder,
    );
  }
}
