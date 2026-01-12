import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final userProfileAsync = ref.watch(userProfileProvider);
    final pantryCount = ref.watch(pantryCountProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: userProfileAsync.when(
        loading: () => const AppPageLoading(),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'Error loading profile',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
        data: (userProfile) {
          if (userProfile == null) {
            return const Center(child: Text('No profile found'));
          }

          final user = authState.user;
          final isAnonymous = user?.isAnonymous == true;
          final displayName = isAnonymous
              ? 'Guest User'
              : userProfile.displayName;

          // Real-time Firestore data
          final recipesUnlocked = userProfile.stats.recipesUnlocked;
          final totalCarrotsSpent = userProfile.stats.totalCarrotsSpent;
          final dietaryRestrictions =
              userProfile.preferences.dietaryRestrictions;
          final allergies = userProfile.preferences.allergies;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // 1. User Card with real data
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.primaryLight,
                          border: Border.all(
                            color: AppTheme.primaryColor,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _getInitials(displayName),
                            style: const TextStyle(
                              color: AppTheme.primaryDark,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? '',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              userProfile.subscriptionStatus == 'premium'
                                  ? '⭐ Premium Member'
                                  : 'Free Plan',
                              style: TextStyle(
                                color:
                                    userProfile.subscriptionStatus == 'premium'
                                    ? Colors.amber[700]
                                    : Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () {
                          // TODO: Implement profile edit
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppTheme.spacingL),

                // 2. Real-time Stats from Firestore
                Row(
                  children: [
                    Expanded(
                      child: _buildStat('$pantryCount', 'Pantry', Colors.blue),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStat(
                        '$recipesUnlocked',
                        'Recipes',
                        Colors.red,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppTheme.spacingL),

                // 3. Carrots Stats
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Weekly Carrots',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${userProfile.carrots.current} / ${userProfile.carrots.max}',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Remaining this week',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: const Text(
                                  '🥕',
                                  style: TextStyle(fontSize: 32),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Total Spent: $totalCarrotsSpent',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppTheme.spacingL),

                // 4. Dietary Preferences from Firestore
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dietary Preferences',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (dietaryRestrictions.isEmpty &&
                          (allergies.isEmpty || allergies.first == ''))
                        Text(
                          'No dietary restrictions set',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ...dietaryRestrictions
                                .where((r) => r.isNotEmpty)
                                .map((r) => _buildFilterChip(r, true)),
                            ...allergies
                                .where((a) => a.isNotEmpty)
                                .map((a) => _buildFilterChip('No $a', true)),
                            _buildAddChip(),
                          ],
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: AppTheme.spacingL),

                // 5. Menu Options
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Column(
                    children: [
                      _buildMenuItem(
                        Icons.favorite_border_rounded,
                        'My Favorites',
                      ),
                      _buildDivider(),
                      _buildMenuItem(
                        Icons.shopping_bag_outlined,
                        'Shopping List',
                      ),
                      _buildDivider(),
                      _buildMenuItem(
                        Icons.help_outline_rounded,
                        'Help & Support',
                      ),
                    ],
                  ),
                ),

                SizedBox(height: MediaQuery.of(context).size.height * 0.13),

                // 6. Sign Out
                TextButton(
                  onPressed: () async {
                    await ref.read(authProvider.notifier).signOut();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                    backgroundColor: AppTheme.surfaceColor,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Sign Out',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 100),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStat(String value, String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryColor : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildAddChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Icon(Icons.add, size: 16, color: Colors.grey),
    );
  }

  Widget _buildMenuItem(IconData icon, String title) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.black87, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
      onTap: () {},
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      indent: 70,
      endIndent: 20,
      color: Color(0xFFF5F5F5),
    );
  }

  /// Fix #12: Safe initials extraction with edge case handling
  String _getInitials(String name) {
    // Trim and split by any whitespace, filter empty parts
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.isEmpty) return '?';

    if (parts.length == 1) {
      return parts[0].isEmpty ? '?' : parts[0][0].toUpperCase();
    }

    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
