import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:super_swipe/core/models/recipe_preview.dart';
import 'package:super_swipe/core/theme/app_theme.dart';

class RecipePreviewCard extends StatelessWidget {
  final RecipePreview preview;
  final VoidCallback? onShowDirections;

  const RecipePreviewCard({
    super.key,
    required this.preview,
    this.onShowDirections,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final isCompact = maxH.isFinite && maxH < 360;
        final imageHeight = isCompact
            ? 120.0
            : (maxH.isFinite ? (maxH * 0.55).clamp(140.0, 240.0) : 220.0);
        final padding = isCompact ? 12.0 : 16.0;

        final chips = <Widget>[
          _Chip(label: '${preview.estimatedTimeMinutes} min'),
          if (preview.calories > 0) _Chip(label: '${preview.calories} cal'),
          if (!isCompact) _Chip(label: preview.skillLevel),
          if (!isCompact) _Chip(label: preview.cuisine),
        ];

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    if (preview.imageUrl != null && preview.imageUrl!.isNotEmpty)
                      SizedBox(
                        height: imageHeight,
                        child: CachedNetworkImage(
                          imageUrl: preview.imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Container(
                            color: AppTheme.surfaceColor,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_not_supported),
                          ),
                        ),
                      )
                    else
                      Container(
                        height: imageHeight,
                        color: AppTheme.surfaceColor,
                        alignment: Alignment.center,
                        child: const Icon(Icons.restaurant_menu, size: 36),
                      ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(padding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              preview.title,
                              maxLines: isCompact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
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
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: AppTheme.textSecondary,
                                    height: 1.35,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: chips),
                            if (!isCompact && preview.mainIngredients.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                preview.mainIngredients.take(4).join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
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
                  ],
                ),
                if (onShowDirections != null)
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
                        onPressed: onShowDirections,
                        icon: const Icon(Icons.menu_book_rounded, size: 16),
                        label: const Text('Show Directions'),
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

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
