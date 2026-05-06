import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/providers/recipe_providers.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/features/swipe/providers/pantry_first_swipe_deck_provider.dart';

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

    // Responsive font sizes
    final double greetingSize = h < 680
        ? 24
        : h < 780
        ? 28
        : 32;
    final double subtitleSize = h < 680 ? 13 : 14;
    final double buttonHeight = h < 680 ? 52 : 56;
    final double sectionTitleSize = h < 680 ? 18 : 20;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
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
              return _buildErrorState(
                context,
                'Profile not found. Please sign in.',
                ref,
              );
            }

            String displayName;
            if (authState.user?.isAnonymous == true) {
              displayName = 'Guest';
            } else {
              displayName = userProfile.displayName.split(' ').first;
            }

            final carrotCount = userProfile.carrots.current;
            final maxCarrots = userProfile.carrots.max;
            final recipesUnlocked = userProfile.stats.recipesUnlocked;
            final subscription = userProfile.subscriptionStatus.toLowerCase();
            final isPremium = subscription == 'premium';

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: w * 0.06),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SwipeDeckPreloader(),
                  SizedBox(height: h * 0.03),

                  // ── Greeting ─────────────────────────────────────
                  Text(
                    'Welcome back, $displayName',
                    style: GoogleFonts.dmSerifDisplay(
                      fontSize: greetingSize,
                      height: 1.2,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: h * 0.01),
                  Text(
                    'Ready to find your next meal?',
                    style: TextStyle(
                      fontSize: subtitleSize,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  SizedBox(height: h * 0.03),

                  // ── Swipe Button ─────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: buttonHeight,
                    child: ElevatedButton(
                      onPressed: () => context.push(AppRoutes.swipe),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(buttonHeight / 2),
                        ),
                      ),
                      child: Text(
                        'Swipe for Supper',
                        style: GoogleFonts.inter(
                          fontSize: h < 680 ? 15 : 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: h * 0.012),
                  Center(
                    child: Text(
                      'Unlimited swipes • Unlock when ready to cook',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: h < 680 ? 12 : 13,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  SizedBox(height: h * 0.03),

                  // ── Latest Recipes (Horizontal Scroll) ───────────
                  savedRecipesAsync.when(
                    data: (recipes) {
                      if (recipes.isEmpty) return const SizedBox.shrink();

                      final latestRecipes = recipes.take(3).toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Latest Recipes',
                            style: GoogleFonts.dmSerifDisplay(
                              fontSize: sectionTitleSize,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          SizedBox(height: h * 0.015),
                          SizedBox(
                            height: 140,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: latestRecipes.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) =>
                                  _buildHorizontalRecipeCard(
                                    context,
                                    latestRecipes[index],
                                    w,
                                  ),
                            ),
                          ),
                          SizedBox(height: h * 0.025),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                  // ── Pantry + Stats Row ───────────────────────────
                  Row(
                    children: [
                      // Pantry card
                      Expanded(
                        child: _buildCompactCard(
                          icon: Icons.kitchen_rounded,
                          iconColor: Colors.orange,
                          title: 'Pantry',
                          value: '$pantryCount',
                          label: 'items',
                          onTap: () => context.go(AppRoutes.pantry),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Stats card
                      Expanded(
                        child: _buildCompactCard(
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

                  SizedBox(height: h * 0.03),

                  // ── Weekly Activity ──────────────────────────────
                  Text(
                    'Weekly Activity',
                    style: GoogleFonts.dmSerifDisplay(
                      fontSize: sectionTitleSize,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: h * 0.015),
                  if (!isPremium) ...[
                    _buildCarrotDisplay(carrotCount, maxCarrots),
                    SizedBox(height: h * 0.01),
                    Text(
                      '$carrotCount of $maxCarrots unlocks remaining',
                      style: TextStyle(
                        fontSize: subtitleSize,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: h * 0.015),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Upgrade to Premium for unlimited unlocks',
                              style: TextStyle(
                                fontSize: subtitleSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text('⭐', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Premium: Unlimited • $recipesUnlocked unlocked',
                              style: TextStyle(
                                fontSize: subtitleSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  SizedBox(height: h * 0.04),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D2621),
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildHorizontalRecipeCard(
    BuildContext context,
    recipe,
    double screenWidth,
  ) {
    return GestureDetector(
      onTap: () =>
          context.push('${AppRoutes.recipes}/${recipe.id}', extra: recipe),
      child: Container(
        width: screenWidth * 0.65,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: SizedBox(
                height: 80,
                width: double.infinity,
                child: recipe.imageUrl.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: recipe.imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 400,
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
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSerifDisplay(
                      fontSize: 15,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${recipe.timeMinutes} min',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.local_fire_department,
                        size: 12,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${recipe.calories} kcal',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactCard({
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 16,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Fix #10: Build carrot display with cap for premium users
  Widget _buildCarrotDisplay(int current, int max) {
    // Cap at 20 to prevent overflow on premium
    if (max > 20) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orange.withValues(alpha: 0.1),
              Colors.orange.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🥕', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Text(
              '$current / $max',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ],
        ),
      );
    }

    // Normal display for <= 20 carrots
    final displayMax = max.clamp(0, 20);
    return Row(
      children: List.generate(displayMax, (index) {
        final isActive = index < current;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: isActive ? 1.0 : 0.25,
            child: const Text('🥕', style: TextStyle(fontSize: 26)),
          ),
        );
      }),
    );
  }

  Widget _buildLoadingState() {
    return const AppPageLoading();
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
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
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              authState.user?.email ?? 'Guest',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('View Profile'),
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(authProvider.notifier).signOut();
                if (context.mounted) context.go(AppRoutes.login);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Invisible widget that triggers the swipe deck generation in the background
class _SwipeDeckPreloader extends ConsumerStatefulWidget {
  const _SwipeDeckPreloader();

  @override
  ConsumerState<_SwipeDeckPreloader> createState() =>
      _SwipeDeckPreloaderState();
}

class _SwipeDeckPreloaderState extends ConsumerState<_SwipeDeckPreloader> {
  // We'll warm up the default energy level (2 - Medium)
  static const int _defaultEnergyLevel = 2;

  @override
  void initState() {
    super.initState();
    // Schedule the read for after the first frame to avoid build-phase issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerPreload();
    });
  }

  void _triggerPreload() {
    // Just valid reading the provider triggers the build() method,
    // which calls ensureInitialDeck()
    ref.read(pantryFirstSwipeDeckProvider(_defaultEnergyLevel));
  }

  @override
  Widget build(BuildContext context) {
    // We also watch it here to ensure it stays active if the user changes pantry items
    // ignoring the value to avoid unnecessary rebuilds of this widget (using select)
    ref.watch(
      pantryFirstSwipeDeckProvider(_defaultEnergyLevel).select((_) => 0),
    );

    return const SizedBox.shrink();
  }
}
