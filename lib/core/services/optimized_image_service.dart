import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:super_swipe/core/widgets/loading/app_shimmer.dart';
import 'package:super_swipe/core/widgets/loading/skeleton.dart';

class OptimizedImageService {
  OptimizedImageService._();

  // Singleton instance
  static final OptimizedImageService instance = OptimizedImageService._();

  /// Image quality for compression (0-100)
  static const int defaultQuality = 85;

  /// Max dimensions for images
  static const int maxWidth = 1024;
  static const int maxHeight = 1024;

  /// Get optimized network image widget
  ///
  /// Usage:
  /// ```dart
  /// OptimizedImageService.instance.buildNetworkImage(
  ///   imageUrl: recipe.imageUrl,
  ///   fit: BoxFit.cover,
  /// )
  /// ```
  Widget buildNetworkImage({
    required String imageUrl,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    Widget Function(BuildContext, String)? placeholder,
    Widget Function(BuildContext, String, dynamic)? errorWidget,
    int? memCacheWidth,
    int? memCacheHeight,
  }) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth ?? maxWidth,
      memCacheHeight: memCacheHeight ?? maxHeight,
      placeholder: placeholder ?? _defaultPlaceholder,
      errorWidget: errorWidget ?? _defaultErrorWidget,
      fadeInDuration: const Duration(milliseconds: 300),
      fadeOutDuration: const Duration(milliseconds: 100),
    );
  }

  /// Default loading placeholder
  Widget _defaultPlaceholder(BuildContext context, String url) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height =
            constraints.hasBoundedHeight &&
                constraints.maxHeight.isFinite &&
                constraints.maxHeight > 0
            ? constraints.maxHeight
            : 160.0;
        final width =
            constraints.hasBoundedWidth &&
                constraints.maxWidth.isFinite &&
                constraints.maxWidth > 0
            ? constraints.maxWidth
            : null;

        return AppShimmer(
          baseColor: Colors.grey.shade200,
          highlightColor: Colors.grey.shade100,
          child: SkeletonBox(
            width: width,
            height: height,
            borderRadius: BorderRadius.zero,
            color: Colors.grey.shade200,
          ),
        );
      },
    );
  }

  /// Default error widget
  Widget _defaultErrorWidget(BuildContext context, String url, dynamic error) {
    return Container(
      color: Colors.grey[200],
      child: const Icon(
        Icons.broken_image_rounded,
        size: 48,
        color: Colors.grey,
      ),
    );
  }

  /// Get optimized image provider
  ///
  /// Use this for Image.network() or DecorationImage
  ImageProvider getOptimizedImageProvider(String url) {
    return CachedNetworkImageProvider(
      url,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  /// Pre-cache images for better performance
  ///
  /// Call this during app initialization or before navigating to image-heavy screens
  Future<void> precacheImages(
    BuildContext context,
    List<String> imageUrls,
  ) async {
    for (final url in imageUrls) {
      try {
        await precacheImage(CachedNetworkImageProvider(url), context);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to precache image: $url, Error: $e');
        }
      }
    }
  }

  /// Clear image cache
  ///
  /// Useful for memory management or when user signs out
  Future<void> clearCache() async {
    await DefaultCacheManager().emptyCache();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();

    if (kDebugMode) {
      debugPrint('Image cache cleared');
    }
  }

  /// Clear specific image from cache
  Future<void> clearImageFromCache(String imageUrl) async {
    await CachedNetworkImage.evictFromCache(imageUrl);
  }
}

/// Extension for easy access to optimized images
extension OptimizedImageExtension on String {
  /// Build optimized network image widget
  Widget toOptimizedImage({
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
  }) {
    return OptimizedImageService.instance.buildNetworkImage(
      imageUrl: this,
      fit: fit,
      width: width,
      height: height,
    );
  }

  /// Get optimized image provider
  ImageProvider toOptimizedImageProvider() {
    return OptimizedImageService.instance.getOptimizedImageProvider(this);
  }
}

/// Optimized image builder for recipe cards
class RecipeImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const RecipeImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = OptimizedImageService.instance.buildNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      // Optimize for recipe cards
      memCacheWidth: 800,
      memCacheHeight: 600,
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return image;
  }
}

/// Optimized thumbnail builder with aggressive caching
class ThumbnailImage extends StatelessWidget {
  final String imageUrl;
  final double size;
  final BoxFit fit;

  const ThumbnailImage({
    super.key,
    required this.imageUrl,
    this.size = 60,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: OptimizedImageService.instance.buildNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        width: size,
        height: size,
        // Aggressive compression for thumbnails
        memCacheWidth: 200,
        memCacheHeight: 200,
      ),
    );
  }
}
