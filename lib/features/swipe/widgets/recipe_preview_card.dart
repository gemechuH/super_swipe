import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/utils/recipe_image_utils.dart';
import 'package:super_swipe/core/widgets/loading/app_shimmer.dart';
import 'package:super_swipe/core/widgets/loading/skeleton.dart';

class RecipePreviewCard extends StatelessWidget {
  final RecipePreview preview;
  final VoidCallback? onShowIngredients;

  const RecipePreviewCard({
    super.key,
    required this.preview,
    this.onShowIngredients,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final isCompact = maxH.isFinite && maxH < 420;
        final imageHeight = isCompact
            ? 140.0
            : (maxH.isFinite ? (maxH * 0.58).clamp(160.0, 280.0) : 240.0);
        final padding = isCompact ? 12.0 : 16.0;

        final ingredients = preview.ingredients.isNotEmpty
            ? preview.ingredients
            : preview.mainIngredients;
        final ingredientPreviewCount = isCompact ? 4 : 6;
        final visibleIngredients = ingredients.take(ingredientPreviewCount);
        final hasMoreIngredients = ingredients.length > ingredientPreviewCount;

        final resolvedImageUrl = RecipeImageUtils.forRecipe(
          existing: preview.imageUrl,
          id: preview.id,
          title: preview.title,
          mealType: preview.mealType,
          cuisine: preview.cuisine,
          ingredients: preview.ingredients,
        );

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: imageHeight,
                      child: resolvedImageUrl.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: resolvedImageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => AppShimmer(
                                child: SkeletonBox(
                                  height: imageHeight,
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: AppTheme.surfaceColor,
                                alignment: Alignment.center,
                                child: const Icon(Icons.image_not_supported),
                              ),
                            )
                          : Image.asset(
                              resolvedImageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: AppTheme.surfaceColor,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.image_not_supported,
                                    ),
                                  ),
                            ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(padding),
                        child: IgnorePointer(
                          ignoring: true,
                          child: SingleChildScrollView(
                            // Layout safety only (prevents overflow). Gestures go to swiper.
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  preview.title,
                                  maxLines: isCompact ? 1 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        height: 1.1,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  preview.vibeDescription,
                                  maxLines: isCompact ? 2 : 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: AppTheme.textSecondary,
                                        height: 1.35,
                                      ),
                                ),
                                const SizedBox(height: 14),
                                if (visibleIngredients.isNotEmpty) ...[
                                  ...visibleIngredients.map(
                                    (ing) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        '• $ing',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppTheme.textSecondary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ),
                                  if (hasMoreIngredients)
                                    Text(
                                      '…and ${ingredients.length - ingredientPreviewCount} more',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (onShowIngredients != null)
                  Positioned(
                    right: padding,
                    top: padding,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: TextButton.icon(
                        onPressed: onShowIngredients,
                        icon: const Icon(
                          Icons.format_list_bulleted_rounded,
                          size: 16,
                        ),
                        label: const Text('Show Ingredients'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          foregroundColor: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
