import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/providers/recipe_providers.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_shimmer.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final userProfileAsync = ref.watch(userProfileProvider);
    final pantryCount = ref.watch(pantryCountProvider);
    final savedRecipesAsync = ref.watch(savedRecipesProvider);

    final size = MediaQuery.of(context).size;
    final h = size.height;
    final w = size.width;

    // Responsive font sizes — clean and readable
    final double subtitleSize = h < 680 ? 12 : 13;
    final double buttonHeight = h < 680 ? 44 : 48;
    final double sectionTitleSize = h < 680 ? 17 : 18;
    final double cardTitleSize = h < 680 ? 13 : 14;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: userProfileAsync.maybeWhen(
          data: (userProfile) {
            if (userProfile == null) return const SizedBox.shrink();
            final carrotCount = userProfile.carrots.current;
            final maxCarrots = userProfile.carrots.max;
            final subscription = userProfile.subscriptionStatus.toLowerCase();
            final isPremium = subscription == 'premium';

            return Align(
              alignment: Alignment.centerLeft,
              child: !isPremium
                  ? _buildAppBarCarrotBadge(context, carrotCount, maxCarrots)
                  : _buildAppBarPremiumBadge(context),
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),
        actions: [
          _buildProfileAvatar(context, ref, authState, userProfileAsync),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        top: false,
        child: userProfileAsync.when(
          loading: () => _buildLoadingState(),
          error: (error, stack) => _buildErrorState(context, error, ref),
          data: (userProfile) {
            if (userProfile == null) {
              // Show loading instead of error during initial profile creation
              return _buildLoadingState();
            }

            final recipesUnlocked = userProfile.stats.recipesUnlocked;

            // Get first name from display name
            String firstName;
            if (authState.user?.isAnonymous == true) {
              firstName = 'Guest';
            } else {
              firstName = userProfile.displayName.split(' ').first;
            }

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: w * 0.06),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: h * 0.02),
                  // ── Welcome Greeting ─────────────────────────────
                  Text(
                    'Welcome back, $firstName',
                    style: GoogleFonts.inter(
                      fontSize: h < 680 ? 20 : 22,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: h * 0.008),
                  Text(
                    'Ready to find your next meal?',
                    style: GoogleFonts.inter(
                      fontSize: subtitleSize,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),

                  SizedBox(height: h * 0.024),

                  // ── Generate Recipe Button ─────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: buttonHeight,
                    child: ElevatedButton(
                      onPressed: () => context.push(AppRoutes.aiGenerate),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(buttonHeight / 2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.restaurant, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Generate a Recipe',
                            style: GoogleFonts.inter(
                              fontSize: h < 680 ? 13 : 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: h * 0.024),

                  // ── Pantry + Recipes Row (Small Cards) ───────────
                  Row(
                    children: [
                      // Pantry card
                      Expanded(
                        child: _buildTinyCard(
                          icon: Icons.kitchen_rounded,
                          iconColor: Colors.orange,
                          title: 'Pantry',
                          value: '$pantryCount',
                          label: 'items',
                          onTap: () => context.go(AppRoutes.pantry),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Recipes card
                      Expanded(
                        child: _buildTinyCard(
                          icon: Icons.restaurant_rounded,
                          iconColor: AppTheme.primaryColor,
                          title: 'Recipes',
                          value: '$recipesUnlocked',
                          label: 'unlocked',
                          onTap: () => context.go(AppRoutes.recipes),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: h * 0.024),

                  // ── Latest Recipes Section ───────────────────────
                  savedRecipesAsync.when(
                    data: (recipes) {
                      if (recipes.isEmpty) {
                        // Empty state for new users
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Latest Recipes',
                              style: GoogleFonts.inter(
                                fontSize: sectionTitleSize,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: h * 0.015),
                            _buildEmptyRecipesState(context, h),
                            SizedBox(height: h * 0.01),
                          ],
                        );
                      }

                      final latestRecipes = recipes.take(5).toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Latest Recipes',
                            style: GoogleFonts.inter(
                              fontSize: sectionTitleSize,
                              fontWeight: FontWeight.w400,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: h * 0.015),
                          ...latestRecipes.map(
                            (recipe) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _buildRecipeCard(
                                context,
                                recipe,
                                cardTitleSize,
                              ),
                            ),
                          ),
                          SizedBox(height: h * 0.01),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (e, s) => const SizedBox.shrink(),
                  ),

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 90),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyRecipesState(BuildContext context, double screenHeight) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: screenHeight * 0.02,
        horizontal: 22,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.2),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Text('🍽️', style: TextStyle(fontSize: 48)),
          ),
          SizedBox(height: screenHeight * 0.02),
          Text(
            'No recipes yet!',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          SizedBox(height: screenHeight * 0.008),
          Text(
            'Generate a recipe to discover meals you\'ll love',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          SizedBox(height: screenHeight * 0.01),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => context.push(AppRoutes.aiGenerate),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Generate a Recipe',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.restaurant, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarCarrotBadge(BuildContext context, int current, int max) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.store),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🥕', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            '$current/$max weekly unlocks',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.orange.shade900,
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildAppBarPremiumBadge(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.store),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⭐', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            'Premium',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.amber.shade900,
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildRecipeCard(BuildContext context, recipe, double titleSize) {
    return GestureDetector(
      onTap: () =>
          context.push('${AppRoutes.recipes}/${recipe.id}', extra: recipe),
      child: Container(
        height: 120, // Fixed height for all cards
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Image - Fixed size
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
              child: SizedBox(
                width: 120,
                height: 120,
                child: recipe.imageUrl.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: recipe.imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        placeholder: (context, url) =>
                            Container(color: Colors.grey.shade200),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(
                            Icons.restaurant,
                            color: Colors.grey,
                          ),
                        ),
                      )
                    : Image.asset(recipe.imageUrl, fit: BoxFit.cover),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      recipe.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${recipe.timeMinutes} min',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Icon(
                          Icons.local_fire_department,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${recipe.calories} kcal',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTinyCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const _HomeScreenSkeleton();
  }

  Widget _buildErrorState(BuildContext context, Object error, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Couldn\'t Load Profile',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 24,
                color: const Color(0xFF2D2621),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please sign in again to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                // Sign out first to clear state
                await ref.read(authProvider.notifier).signOut();
                if (context.mounted) {
                  context.go(AppRoutes.login);
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Sign In Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(
    BuildContext context,
    WidgetRef ref,
    AuthState authState,
    AsyncValue userProfileAsync,
  ) {
    final photoUrl = authState.user?.photoURL;
    final displayName = userProfileAsync.value?.displayName ?? 'User';
    final initials = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : 'U';

    return GestureDetector(
      onTap: () => _showProfileModal(context, ref, authState),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: CircleAvatar(
          radius: 20,
          backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.3),
          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
          child: photoUrl == null
              ? Text(
                  initials,
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  void _showProfileModal(
    BuildContext context,
    WidgetRef ref,
    AuthState authState,
  ) {
    final userProfile = ref.read(userProfileProvider).value;
    final isPremium = userProfile?.subscriptionStatus == 'premium';

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.3),
                backgroundImage: authState.user?.photoURL != null
                    ? NetworkImage(authState.user!.photoURL!)
                    : null,
                child: authState.user?.photoURL == null
                    ? Icon(Icons.person, size: 40, color: AppTheme.primaryColor)
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                authState.user?.displayName ?? 'User',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                authState.user?.email ?? 'Guest',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPremium
                      ? Colors.amber.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPremium
                        ? Colors.amber.withValues(alpha: 0.3)
                        : Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPremium)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Text('⭐', style: TextStyle(fontSize: 12)),
                      ),
                    Text(
                      isPremium ? 'Premium' : 'Free Plan',
                      style: TextStyle(
                        color: isPremium ? Colors.amber[800] : Colors.grey[700],
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  context.push(AppRoutes.profile);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: AppTheme.textPrimary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'View Profile',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () async {
                  Navigator.pop(context);
                  await ref.read(authProvider.notifier).signOut();
                  if (context.mounted) context.go(AppRoutes.login);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: AppTheme.textPrimary, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'Sign Out',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton screen that mirrors the real home screen layout.
/// Uses shimmer animation on grey placeholder shapes.
class _HomeScreenSkeleton extends StatelessWidget {
  const _HomeScreenSkeleton();

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;
    final px = w * 0.06;

    return AppShimmer(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: px),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: h * 0.02),

            // Greeting line
            _SkeletonBox(width: w * 0.55, height: 22, radius: 6),
            SizedBox(height: h * 0.008),
            _SkeletonBox(width: w * 0.45, height: 14, radius: 6),

            SizedBox(height: h * 0.024),

            // Swipe button
            _SkeletonBox(
              width: double.infinity,
              height: h < 680 ? 44 : 48,
              radius: 24,
            ),
            SizedBox(height: h * 0.01),
            // Subtitle under button
            Center(child: _SkeletonBox(width: w * 0.6, height: 12, radius: 6)),

            SizedBox(height: h * 0.024),

            // Two small cards row
            Row(
              children: [
                Expanded(child: _SkeletonBox(height: 72, radius: 14)),
                const SizedBox(width: 8),
                Expanded(child: _SkeletonBox(height: 72, radius: 14)),
              ],
            ),

            SizedBox(height: h * 0.024),

            // Section title
            _SkeletonBox(width: w * 0.35, height: 16, radius: 6),
            SizedBox(height: h * 0.015),

            // Recipe cards
            _SkeletonRecipeRow(w: w),
            const SizedBox(height: 10),
            _SkeletonRecipeRow(w: w),
            const SizedBox(height: 10),
            _SkeletonRecipeRow(w: w),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const _SkeletonBox({this.width, required this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton for a single recipe card row (image left + text right)
class _SkeletonRecipeRow extends StatelessWidget {
  final double w;
  const _SkeletonRecipeRow({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Image placeholder
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Text lines
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SkeletonBox(width: w * 0.25, height: 10, radius: 4),
                const SizedBox(height: 6),
                _SkeletonBox(width: w * 0.45, height: 13, radius: 4),
                const SizedBox(height: 6),
                _SkeletonBox(width: w * 0.35, height: 10, radius: 4),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
