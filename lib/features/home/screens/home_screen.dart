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

    // Responsive font sizes — clean and readable
    final double subtitleSize = h < 680 ? 12 : 13;
    final double buttonHeight = h < 680 ? 44 : 48;
    final double sectionTitleSize = h < 680 ? 17 : 18;
    final double cardTitleSize = h < 680 ? 13 : 14;

    return Scaffold(
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
                  ? _buildAppBarCarrotBadge(carrotCount, maxCarrots)
                  : _buildAppBarPremiumBadge(),
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
              return _buildErrorState(
                context,
                'Profile not found. Please sign in.',
                ref,
              );
            }

            final carrotCount = userProfile.carrots.current;
            final maxCarrots = userProfile.carrots.max;
            final recipesUnlocked = userProfile.stats.recipesUnlocked;
            final subscription = userProfile.subscriptionStatus.toLowerCase();
            final isPremium = subscription == 'premium';

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
                  const _SwipeDeckPreloader(),
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
                        'Swipe for Super',
                        style: GoogleFonts.inter(
                          fontSize: h < 680 ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: h * 0.01),
                  Center(
                    child: Text(
                      'Unlimited swipes • Unlock when ready to cook',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: h < 680 ? 12 : 13,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                        fontWeight: FontWeight.w400,
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

                  // ── Latest Recipes (Better Cards) ────────────────
                  savedRecipesAsync.when(
                    data: (recipes) {
                      if (recipes.isEmpty) return const SizedBox.shrink();

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
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                  SizedBox(height: h * 0.03),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppBarCarrotBadge(int current, int max) {
    return Container(
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
    );
  }

  Widget _buildAppBarPremiumBadge() {
    return Container(
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
    );
  }

  Widget _buildTopCarrotBadge(int current, int max) {
    final remaining = max - current;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🥕', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$current/$max',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.orange.shade900,
                  height: 1.1,
                ),
              ),
              Text(
                '$remaining left this week',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Colors.orange.shade800,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopPremiumBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.amber.shade900,
            ),
          ),
        ],
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

  Widget _buildSimpleCard({
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
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
