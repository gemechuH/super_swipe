import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/providers/app_state_provider.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/features/auth/widgets/auth_text_field.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  ProviderSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = ref.listenManual(authProvider, (previous, next) {
      if (!mounted) return;
      if (next.error != null && previous?.error != next.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        ref.read(authProvider.notifier).clearError();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final size = MediaQuery.of(context).size;
    final h = size.height;

    final double titleFontSize = h < 680 ? 22 : 26;
    final double subtitleFontSize = h < 680 ? 12 : 13;
    final double buttonHeight = h < 680 ? 44 : 48;
    final double socialButtonHeight = h < 680 ? 44 : 48;
    final double sectionGap = h < 680 ? 10 : 14;
    final double fieldGap = h < 680 ? 8 : 10;
    final double horizontalPad = size.width * 0.06;

    return Scaffold(
      // true = Flutter shrinks the body when keyboard opens,
      // so the ScrollView can scroll the focused field into view
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // Keyboard-aware: scrolls just enough to show focused field
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(horizontal: horizontalPad),
              child: ConstrainedBox(
                // Minimum height = full available viewport
                // so content fills screen when keyboard is closed
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Header ─────────────────────────────────
                        SizedBox(height: h * 0.04),
                        _BrandHeader(titleFontSize: titleFontSize),

                        // ── Fields ─────────────────────────────────
                        SizedBox(height: h * 0.035),
                        AuthTextField(
                          controller: _emailController,
                          label: 'Email Address',
                          hint: 'swipe@example.com',
                          prefixIcon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: _validateEmail,
                        ),
                        SizedBox(height: fieldGap),
                        AuthTextField(
                          controller: _passwordController,
                          label: 'Password',
                          hint: 'Enter your password',
                          prefixIcon: Icons.lock_outline_rounded,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          validator: _validatePassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppTheme.textSecondary,
                              size: 20,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                          onFieldSubmitted: (_) => _handleLogin(),
                        ),

                        // ── Forgot Password ────────────────────────
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                fontSize: subtitleFontSize,
                                color: AppTheme.warningColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                        // ── Flexible gap — shrinks when keyboard open
                        const Spacer(),

                        // ── Log In Button ──────────────────────────
                        SizedBox(
                          height: buttonHeight,
                          child: ElevatedButton(
                            onPressed: authState.isLoading
                                ? null
                                : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  buttonHeight / 2,
                                ),
                              ),
                              elevation: 0,
                            ),
                            child: authState.isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: AppInlineLoading(
                                      size: 20,
                                      baseColor: Color(0xFFEFEFEF),
                                      highlightColor: Color(0xFFFFFFFF),
                                    ),
                                  )
                                : const Text(
                                    'Log In',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                        SizedBox(height: sectionGap),

                        // ── Sign Up Button ─────────────────────────
                        SizedBox(
                          height: buttonHeight,
                          child: OutlinedButton(
                            onPressed: () => context.go(AppRoutes.signup),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textPrimary,
                              side: BorderSide(color: Colors.grey.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  buttonHeight / 2,
                                ),
                              ),
                            ),
                            child: const Text(
                              'Sign Up',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: sectionGap),

                        // ── OR Divider ─────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: Divider(color: Colors.grey.shade300),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(color: Colors.grey.shade300),
                            ),
                          ],
                        ),
                        SizedBox(height: sectionGap),

                        // ── Social Buttons ─────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: socialButtonHeight,
                                child: OutlinedButton(
                                  onPressed: authState.isLoading
                                      ? null
                                      : _handleGoogleLogin,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.textPrimary,
                                    side: BorderSide(
                                      color: Colors.grey.shade400,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        socialButtonHeight / 2,
                                      ),
                                    ),
                                  ),
                                  child: Image.asset(
                                    'assets/images/google.png',
                                    height: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: socialButtonHeight,
                                child: OutlinedButton(
                                  onPressed: authState.isLoading
                                      ? null
                                      : _handleAppleLogin,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.textPrimary,
                                    side: BorderSide(
                                      color: Colors.grey.shade400,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        socialButtonHeight / 2,
                                      ),
                                    ),
                                  ),
                                  child: Image.asset(
                                    'assets/images/apple-logo.png',
                                    height: 22,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: sectionGap * 0.5),

                        // ── Continue as Guest ──────────────────────
                        TextButton(
                          onPressed: () async {
                            await ref
                                .read(appStateProvider.notifier)
                                .markWelcomeSeen();
                            final success = await ref
                                .read(authProvider.notifier)
                                .signInAnonymously();
                            if (!context.mounted) return;
                            if (success) {
                              ref
                                  .read(appStateProvider.notifier)
                                  .setGuestMode(true);
                              context.go(AppRoutes.home);
                            }
                          },
                          child: Text(
                            'Continue as Guest',
                            style: TextStyle(
                              fontSize: subtitleFontSize + 1,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.warningColor,
                            ),
                          ),
                        ),
                        SizedBox(height: h * 0.02),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Please enter your email';
    final emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) return 'Please enter a valid email';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  Future<void> _handleAppleLogin() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Apple Sign In coming soon! 🍎')),
    );
  }

  Future<void> _handleGoogleLogin() async {
    final success = await ref.read(authProvider.notifier).signInWithGoogle();
    if (success && mounted) {
      ref.read(appStateProvider.notifier).setGuestMode(false);
      context.go(AppRoutes.home);
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final success = await ref
        .read(authProvider.notifier)
        .signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    if (success && mounted) {
      ref.read(appStateProvider.notifier).setGuestMode(false);
      context.go(AppRoutes.home);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController(text: _emailController.text);
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter your email and we\'ll send you a reset link.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.spacingM),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await ref
                  .read(authProvider.notifier)
                  .sendPasswordReset(email: emailController.text.trim());
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Password reset email sent! 📧'
                          : 'Failed to send reset email',
                    ),
                    backgroundColor: success
                        ? AppTheme.successColor
                        : AppTheme.errorColor,
                  ),
                );
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
    emailController.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Brand Header Widget
// ─────────────────────────────────────────────────────────────────────────────

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.titleFontSize});

  final double titleFontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Text('🍽️', style: TextStyle(fontSize: 22)),
          ),
        ),
        const SizedBox(height: 10),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              AppTheme.primaryDark,
              AppTheme.primaryColor,
              Color(0xFFFFB5A7),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(bounds),
          child: Text(
            'Super Swipe',
            style: TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
