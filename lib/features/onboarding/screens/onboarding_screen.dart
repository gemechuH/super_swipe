import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:super_swipe/core/providers/app_state_provider.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _isLoading = false;

  Future<void> _onGetStarted() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await ref.read(appStateProvider.notifier).markWelcomeSeen();
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final h = size.height;
    final w = size.width;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Responsive scale
    final double titleSize = h < 680
        ? 32
        : h < 780
        ? 38
        : 44;
    final double subtitleSize = h < 680 ? 13 : 15;
    final double bodySize = h < 680 ? 13 : 14;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.06),
                child: Column(
                  children: [
                    SizedBox(height: h * 0.045),

                    // ── Brand Header ─────────────────────────────────
                    _BrandHeader(
                      titleSize: titleSize,
                      subtitleSize: subtitleSize,
                    ),

                    SizedBox(height: h * 0.045),

                    // ── Food Cards ───────────────────────────────────
                    _FoodCardsRow(screenHeight: h, screenWidth: w),

                    SizedBox(height: h * 0.045),

                    // ── Body text ────────────────────────────────────
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: w * 0.04),
                      child: Text(
                        'Discover meals you\'ll love,\nmade from what\'s already in your kitchen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: bodySize,
                          height: 1.6,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Get Started Button ────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                w * 0.08,
                16,
                w * 0.08,
                bottomPadding + 24,
              ),
              child: SizedBox(
                width: double.infinity,
                height: h < 680 ? 52 : 58,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _onGetStarted,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: AppTheme.primaryColor.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: AppInlineLoading(
                            size: 22,
                            baseColor: Color(0xFFEFEFEF),
                            highlightColor: Color(0xFFFFFFFF),
                          ),
                        )
                      : Text(
                          'Get Started',
                          style: GoogleFonts.inter(
                            fontSize: h < 680 ? 15 : 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Brand Header
// ─────────────────────────────────────────────────────────────────────────────

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.titleSize, required this.subtitleSize});

  final double titleSize;
  final double subtitleSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon badge — same style as login/signup
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Center(
            child: Text('🍽️', style: TextStyle(fontSize: 26)),
          ),
        ),
        const SizedBox(height: 14),

        // Brand name — serif display font for premium feel
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
            style: GoogleFonts.dmSerifDisplay(
              fontSize: titleSize,
              color: Colors.white, // masked by shader
              fontWeight: FontWeight.w400,
              letterSpacing: -0.5,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),

        // Subtitle
        Text(
          'Match with your next meal',
          style: TextStyle(
            fontSize: subtitleSize,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Food Cards Row — uses local assets, loads instantly
// ─────────────────────────────────────────────────────────────────────────────

class _FoodCardsRow extends StatelessWidget {
  const _FoodCardsRow({required this.screenHeight, required this.screenWidth});

  final double screenHeight;
  final double screenWidth;

  @override
  Widget build(BuildContext context) {
    // Card sizes scale with screen
    final double centerW = screenWidth * 0.32;
    final double sideW = screenWidth * 0.22;
    final double centerH = screenHeight * 0.22;
    final double sideH = screenHeight * 0.16;
    final double centerImg = centerW * 0.62;
    final double sideImg = sideW * 0.62;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left card — skip
        _FoodCard(
          imagePath: 'assets/images/pasta.jpg',
          width: sideW,
          height: sideH,
          imageSize: sideImg,
          isLike: false,
          isCenter: false,
        ),
        SizedBox(width: screenWidth * 0.03),
        // Center card — like
        _FoodCard(
          imagePath: 'assets/images/curry.jpg',
          width: centerW,
          height: centerH,
          imageSize: centerImg,
          isLike: true,
          isCenter: true,
        ),
        SizedBox(width: screenWidth * 0.03),
        // Right card — skip
        _FoodCard(
          imagePath: 'assets/images/salad.jpg',
          width: sideW,
          height: sideH,
          imageSize: sideImg,
          isLike: false,
          isCenter: false,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single Food Card
// ─────────────────────────────────────────────────────────────────────────────

class _FoodCard extends StatelessWidget {
  const _FoodCard({
    required this.imagePath,
    required this.width,
    required this.height,
    required this.imageSize,
    required this.isLike,
    required this.isCenter,
  });

  final String imagePath;
  final double width;
  final double height;
  final double imageSize;
  final bool isLike;
  final bool isCenter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isCenter
            ? Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.25),
                width: 1.5,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isCenter ? 0.10 : 0.06),
            blurRadius: isCenter ? 24 : 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Circular image — local asset, instant load
          Container(
            width: imageSize,
            height: imageSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: isCenter
                  ? Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.20),
                      width: 3,
                    )
                  : null,
            ),
            child: ClipOval(
              child: Image.asset(
                imagePath,
                fit: BoxFit.cover,
                // Preload hint — renders from bundle, zero network latency
                cacheWidth: 300,
              ),
            ),
          ),
          SizedBox(height: height * 0.1),

          // Like / Skip icon
          Container(
            width: isCenter ? 32 : 26,
            height: isCenter ? 32 : 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLike
                  ? const Color(0xFF22B14C).withValues(alpha: 0.10)
                  : AppTheme.errorColor.withValues(alpha: 0.10),
            ),
            child: Icon(
              isLike ? Icons.check_rounded : Icons.close_rounded,
              color: isLike ? const Color(0xFF22B14C) : AppTheme.errorColor,
              size: isCenter ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
