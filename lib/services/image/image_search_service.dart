import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Result from Unsplash image search with attribution data
class UnsplashImageResult {
  final String imageUrl;
  final String photographerName;
  final String photographerUrl;
  final String unsplashPhotoUrl;

  const UnsplashImageResult({
    required this.imageUrl,
    required this.photographerName,
    required this.photographerUrl,
    required this.unsplashPhotoUrl,
  });
}

/// Service for fetching recipe images from Unsplash API
class ImageSearchService {
  static const String _baseUrl = 'https://api.unsplash.com';

  /// Get the API key from dotenv
  String? get _accessKey => dotenv.env['UNSPLASH_ACCESS_KEY'];

  /// Search for a recipe image using refined query
  /// Returns UnsplashImageResult with image URL and attribution, or null if not found
  Future<UnsplashImageResult?> searchRecipeImage({
    required String recipeTitle,
    required List<String> ingredients,
  }) async {
    final key = _accessKey;
    if (key == null || key.isEmpty) {
      debugPrint('Unsplash API key not configured in .env');
      return null;
    }

    try {
      // Build refined query for better food photography results
      final topIngredients = ingredients.take(3).join(' and ');
      final query =
          'Professional food photography of $recipeTitle with $topIngredients';

      final uri = Uri.parse('$_baseUrl/search/photos').replace(
        queryParameters: {
          'query': query,
          'per_page': '1',
          'orientation': 'landscape',
          'content_filter': 'high',
        },
      );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Client-ID $key', 'Accept-Version': 'v1'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          final photo = results.first;
          // Use regular size for good quality without being too large
          final imageUrl = photo['urls']?['regular'] as String?;

          // Extract attribution data for Unsplash compliance
          final user = photo['user'] as Map<String, dynamic>?;
          final photographerName = user?['name'] as String? ?? 'Unknown';
          final photographerUsername = user?['username'] as String? ?? '';
          final photographerUrl =
              'https://unsplash.com/@$photographerUsername?utm_source=super_swipe&utm_medium=referral';
          final unsplashPhotoUrl =
              '${photo['links']?['html'] as String? ?? 'https://unsplash.com'}?utm_source=super_swipe&utm_medium=referral';

          // Track download for Unsplash guidelines compliance
          _trackDownload(photo['links']?['download_location'] as String?);

          if (imageUrl != null) {
            return UnsplashImageResult(
              imageUrl: imageUrl,
              photographerName: photographerName,
              photographerUrl: photographerUrl,
              unsplashPhotoUrl: unsplashPhotoUrl,
            );
          }
        }
      } else {
        debugPrint(
          'Unsplash API error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Unsplash search error: $e');
    }

    return null;
  }

  /// Trigger download tracking (Unsplash API requirement)
  Future<void> _trackDownload(String? downloadLocation) async {
    final key = _accessKey;
    if (downloadLocation == null || key == null || key.isEmpty) return;

    try {
      await http.get(
        Uri.parse(downloadLocation),
        headers: {'Authorization': 'Client-ID $key'},
      );
    } catch (e) {
      // Silent fail - tracking is best effort
    }
  }

  static const List<String> fallbackAssets = [
    'assets/images/salad.jpg',
    'assets/images/pasta.jpg',
    'assets/images/curry.jpg',
    'assets/images/stirfry.jpg',
    'assets/images/toast.jpg',
    'assets/images/smoothie.jpg',
  ];

  /// Get deterministic local asset fallback based on ID (matches RecipePreviewCard)
  static String getDeterministicFallbackAsset(String id) {
    return fallbackAssets[id.hashCode.abs() % fallbackAssets.length];
  }

  /// Simple fallback image based on meal type
  static String getFallbackImage(String mealType) {
    const fallbacks = {
      'breakfast':
          'https://images.unsplash.com/photo-1533089862017-5614ec45e25a?q=80', // Pancakes
      'lunch':
          'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?q=80', // Salad bowl
      'dinner':
          'https://images.unsplash.com/photo-1512058564366-18510be2db19?q=80', // Stir fry
      'snack':
          'https://images.unsplash.com/photo-1621506289937-a8e4df240d0b?q=80', // Granola bar
      'dessert':
          'https://images.unsplash.com/photo-1563729784474-d77dbb933a9e?q=80', // Cake
      'drinks':
          'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?q=80', // Smoothie
    };
    return fallbacks[mealType.toLowerCase()] ??
        'https://images.unsplash.com/photo-1737032571846-445ec57a41da?q=80'; // Default
  }
}
