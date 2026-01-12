import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

    // Simulate a small delay for better UX
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    // Update state to indicate onboarding is seen
    await ref.read(appStateProvider.notifier).markWelcomeSeen();

    if (!mounted) return;
    // Navigate to login
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5), // Warm cream background
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            // Title
            Text(
              'Supper Swipe',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 42,
                color: const Color(0xFF2D2621), // Dark brown/black
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Match with your next meal',
              style: TextStyle(
                fontSize: 18,
                color: const Color(0xFF2D2621).withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),

            const Spacer(),

            // Cards Row
            SizedBox(
              height: 300,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Left Card
                  _buildFoodCard(
                    image:
                        'https://images.unsplash.com/photo-1563379926898-05f4575a45d8?auto=format&fit=crop&w=200&q=60',
                    isCenter: false,
                    isLike: false,
                  ),
                  const SizedBox(width: 12),
                  // Center Card
                  _buildFoodCard(
                    image:
                        'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?auto=format&fit=crop&w=200&q=60',
                    isCenter: true,
                    isLike: true,
                  ),
                  const SizedBox(width: 12),
                  // Right Card
                  _buildFoodCard(
                    image:
                        'https://images.unsplash.com/photo-1555126634-323283e090fa?auto=format&fit=crop&w=200&q=60',
                    isCenter: false,
                    isLike: false,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Swipe right on recipes you love based on ingredients you already have.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: const Color(0xFF2D2621).withValues(alpha: 0.8),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),

            const Spacer(),

            // Get Started Button
            Padding(
              padding: const EdgeInsets.only(
                  left: 40, right: 40, bottom: 80, top: 40),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _onGetStarted,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor, // Golden yellow
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: AppInlineLoading(
                            size: 24,
                            baseColor: Color(0xFFEFEFEF),
                            highlightColor: Color(0xFFFFFFFF),
                          ),
                        )
                      : const Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
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

  Widget _buildFoodCard({
    required String image,
    required bool isCenter,
    required bool isLike,
  }) {
    final double width = isCenter ? 140 : 95;
    final double height = isCenter ? 190 : 140;
    final double imageSize = isCenter ? 100 : 65;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Circular Image
          Container(
            width: imageSize,
            height: imageSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isCenter
                    ? const Color(0xFFEBB238).withValues(alpha: 0.2)
                    : Colors.transparent,
                width: 4,
              ),
            ),
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.cover,
                memCacheWidth: 400,
                placeholder: (context, url) => Container(
                  color: Colors.grey[100],
                  child: const Center(
                    child: AppInlineLoading(
                      size: 20,
                      baseColor: Color(0xFFE6E6E6),
                      highlightColor: Color(0xFFF7F7F7),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) {
                  // debugPrint('Image failed to load: $error');
                  return Container(
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Icon
          Icon(
            isLike ? Icons.check_rounded : Icons.close_rounded,
            color: isLike
                ? const Color(0xFF22B14C)
                : const Color(0xFFD96C56), // Dark green or soft red
            size: isCenter ? 32 : 24,
            weight: 800, // Make icon thicker
          ),
        ],
      ),
    );
  }
}
