import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/models/recipe.dart';
import 'package:super_swipe/core/providers/recipe_providers.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/services/undo_service.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';

/// RecipesScreen - Displays user's saved recipes from Firestore
///
/// Now using real database data instead of hardcoded recipes
class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  int _selectedFilter = 0; // 0: All, 1: Recent, 2: Favorites
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final savedRecipesAsync = ref.watch(savedRecipesProvider);
    final userId = ref.watch(authProvider).user?.uid;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingL,
                  AppTheme.spacingXL,
                  AppTheme.spacingL,
                  AppTheme.spacingM,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'My Recipes',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 32,
                            ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingL),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: TextField(
                              onChanged: (value) =>
                                  setState(() => _searchQuery = value),
                              decoration: InputDecoration(
                                hintText: 'Search recipes...',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.only(
                                  left: 26,
                                  right: 20,
                                ),
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingM),
                        Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.search_rounded,
                              color: AppTheme.textPrimary,
                            ),
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingM),
                  ],
                ),
              ),
            ),

            // Filter Chips
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingL,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', 0),
                      const SizedBox(width: 8),
                      _buildFilterChip('Recent', 1),
                      const SizedBox(width: 8),
                      _buildFilterChip('Favorites', 2),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: AppTheme.spacingL),
            ),

            // Recipes List
            savedRecipesAsync.when(
              loading: () => const SliverFillRemaining(child: AppListLoading()),
              error: (error, stack) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading recipes',
                        style: Theme.of(context).textTheme.titleLarge,
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
              data: (recipes) {
                // Fix #13: Apply functional filtering + search
                final filteredRecipes = _filterRecipes(recipes)
                    .where(
                      (recipe) =>
                          recipe.title.toLowerCase().contains(
                            _searchQuery.toLowerCase(),
                          ) ||
                          recipe.ingredients.any(
                            (ingredient) => ingredient.toLowerCase().contains(
                              _searchQuery.toLowerCase(),
                            ),
                          ),
                    )
                    .toList();

                if (filteredRecipes.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchQuery.isNotEmpty
                                ? Icons.search_off_rounded
                                : Icons.restaurant_menu_rounded,
                            size: 80,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No Recipes Found'
                                : (_selectedFilter == 0
                                      ? 'No Saved Recipes Yet'
                                      : 'No Recipes Match Filter'),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: Text(
                              _searchQuery.isNotEmpty
                                  ? 'Try a different search term'
                                  : (_selectedFilter == 0
                                        ? 'Start swiping to unlock and save delicious recipes!'
                                        : 'Try selecting a different filter'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          if (_selectedFilter == 0 && _searchQuery.isEmpty)
                            ElevatedButton.icon(
                              onPressed: () => context.push(AppRoutes.swipe),
                              icon: const Icon(Icons.swipe_rounded),
                              label: const Text('Start Swiping'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingL,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildRecipeCard(
                        context,
                        filteredRecipes[index],
                        userId,
                      ),
                      childCount: filteredRecipes.length,
                    ),
                  ),
                );
              },
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  /// Fix #13: Filter recipes based on selected filter
  List<Recipe> _filterRecipes(List<Recipe> recipes) {
    switch (_selectedFilter) {
      case 0: // All
        return recipes;
      case 1: // Recent
        return recipes.take(10).toList();
      case 2: // Favorites - filter by isFavorite flag
        return recipes.where((r) => r.isFavorite == true).toList();
      default:
        return recipes;
    }
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilter == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textPrimary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildRecipeCard(BuildContext context, Recipe recipe, String? userId) {
    return InkWell(
      onTap: userId == null
          ? null
          : () => context.push(
              '${AppRoutes.recipes}/${recipe.id}',
              extra: recipe,
            ),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: SizedBox(
                    height: 180,
                    width: double.infinity,
                    child: recipe.imageUrl.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: recipe.imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 800,
                            placeholder: (context, url) => Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: AppInlineLoading(
                                  size: 28,
                                  baseColor: Color(0xFFE6E6E6),
                                  highlightColor: Color(0xFFF7F7F7),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(
                                Icons.broken_image,
                                size: 48,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : Image.asset(
                            recipe.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(
                                    Icons.broken_image,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                ),
                          ),
                  ),
                ),
                // Favorite/Like button (NOT delete!)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        recipe.isFavorite == true
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: recipe.isFavorite == true
                            ? AppTheme.errorColor
                            : Colors.grey,
                        size: 20,
                      ),
                      onPressed: () async {
                        if (userId != null) {
                          final wasLiked = recipe.isFavorite == true;
                          // Toggle favorite status
                          await ref
                              .read(recipeServiceProvider)
                              .toggleRecipeFavorite(userId, recipe.id);

                          // Show undo snackbar for unlike actions
                          if (wasLiked && context.mounted) {
                            ref
                                .read(undoServiceProvider.notifier)
                                .registerUndo(
                                  id: 'unlike_${recipe.id}',
                                  description:
                                      'Removed "${recipe.title}" from favorites',
                                  context: context,
                                  undoAction: () async {
                                    // Re-favorite the recipe
                                    await ref
                                        .read(recipeServiceProvider)
                                        .toggleRecipeFavorite(
                                          userId,
                                          recipe.id,
                                        );
                                  },
                                );
                          } else if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Added to favorites ❤️'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          recipe.difficulty ?? 'Medium',
                          style: const TextStyle(
                            color: AppTheme.secondaryDark,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '4.8',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    recipe.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        recipe.cookTime ?? '${recipe.timeMinutes} min',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${recipe.calories} kcal',
                        style: TextStyle(color: Colors.grey.shade500),
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
}
