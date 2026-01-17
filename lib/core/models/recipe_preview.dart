import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:super_swipe/core/utils/recipe_image_utils.dart';

/// Lightweight recipe preview model for swipe deck cards.
/// Contains only essential info - no instructions (saves on AI costs).
/// Full recipe is generated only after carrot spend.
class RecipePreview {
  final String id;
  final String title;
  final String vibeDescription;

  /// Full ingredient list (no quantities) for the preview card.
  final List<String> ingredients;

  /// Back-compat: small subset used for chips in some UIs.
  final List<String> mainIngredients;
  final String? imageUrl;
  final int estimatedTimeMinutes;
  final int calories;

  /// Normalized equipment/icon tokens (e.g. "pan", "oven", "blender").
  final List<String> equipmentIcons;
  final String mealType;
  final int energyLevel;

  /// Optional discovery metadata.
  final String cuisine;
  final String skillLevel;

  const RecipePreview({
    required this.id,
    required this.title,
    required this.vibeDescription,
    this.ingredients = const [],
    required this.mainIngredients,
    this.imageUrl,
    this.estimatedTimeMinutes = 30,
    this.calories = 0,
    this.equipmentIcons = const [],
    this.mealType = 'dinner',
    this.energyLevel = 2,
    this.cuisine = 'other',
    this.skillLevel = 'beginner',
  });

  /// Create from OpenAI JSON response
  factory RecipePreview.fromJson(Map<String, dynamic> json) {
    final parsedIngredients = List<String>.from(
      json['ingredients'] ??
          json['ingredient_list'] ??
          json['main_ingredients'] ??
          [],
    );
    final parsedMain = List<String>.from(json['main_ingredients'] ?? []);
    final mealType =
        (json['meal_type'] ?? json['mealType'] ?? 'dinner') as String;
    final cuisine = (json['cuisine'] ?? 'other') as String;
    final title = (json['title'] ?? 'Chef\'s Special') as String;

    final providedImageUrl =
        (json['imageUrl'] ?? json['image_url'] ?? json['image'] ?? '')
            as Object;
    final imageUrl = providedImageUrl is String ? providedImageUrl : '';

    final generatedId = 'preview_${DateTime.now().millisecondsSinceEpoch}';

    return RecipePreview(
      id: generatedId,
      title: title,
      vibeDescription: json['vibe_description'] ?? json['description'] ?? '',
      ingredients: parsedIngredients,
      mainIngredients: parsedMain.isNotEmpty
          ? parsedMain
          : (parsedIngredients.length > 4
                ? parsedIngredients.take(4).toList()
                : parsedIngredients),
      imageUrl: RecipeImageUtils.forRecipe(
        existing: imageUrl,
        id: generatedId,
        title: title,
        mealType: mealType,
        cuisine: cuisine,
        ingredients: parsedIngredients,
      ),
      estimatedTimeMinutes:
          (json['estimated_time_minutes'] ?? json['timeMinutes'] ?? 30) as int,
      calories: (json['calories'] ?? json['calories_estimate'] ?? 0) as int,
      equipmentIcons: List<String>.from(
        json['equipment_icons'] ?? json['equipment'] ?? [],
      ),
      mealType: mealType,
      energyLevel: json['energy_level'] ?? json['energyLevel'] ?? 2,
      cuisine: cuisine,
      skillLevel: json['skill_level'] ?? json['skillLevel'] ?? 'beginner',
    );
  }

  /// Convert to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'vibe_description': vibeDescription,
      'ingredients': ingredients,
      'main_ingredients': mainIngredients,
      'estimated_time_minutes': estimatedTimeMinutes,
      'calories': calories,
      'equipment_icons': equipmentIcons,
      'meal_type': mealType,
      'energy_level': energyLevel,
      'cuisine': cuisine,
      'skill_level': skillLevel,
    };
  }

  /// Create from Firestore document
  factory RecipePreview.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    return RecipePreview(
      id: doc.id,
      title: data['title'] ?? '',
      vibeDescription: data['vibeDescription'] ?? data['description'] ?? '',
      ingredients: List<String>.from(
        data['ingredients'] ??
            data['ingredientList'] ??
            data['mainIngredients'] ??
            [],
      ),
      mainIngredients: List<String>.from(data['mainIngredients'] ?? []),
      imageUrl: data['imageUrl'],
      estimatedTimeMinutes: data['estimatedTimeMinutes'] ?? 30,
      calories: (data['calories'] as num?)?.toInt() ?? 0,
      equipmentIcons: List<String>.from(data['equipmentIcons'] ?? []),
      mealType: data['mealType'] ?? 'dinner',
      energyLevel: data['energyLevel'] ?? 2,
      cuisine: data['cuisine'] ?? 'other',
      skillLevel: data['skillLevel'] ?? 'beginner',
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'vibeDescription': vibeDescription,
      'ingredients': ingredients,
      'mainIngredients': mainIngredients,
      'imageUrl': imageUrl,
      'estimatedTimeMinutes': estimatedTimeMinutes,
      'calories': calories,
      'equipmentIcons': equipmentIcons,
      'mealType': mealType,
      'energyLevel': energyLevel,
      'cuisine': cuisine,
      'skillLevel': skillLevel,
    };
  }

  RecipePreview copyWith({
    String? id,
    String? title,
    String? vibeDescription,
    List<String>? ingredients,
    List<String>? mainIngredients,
    String? imageUrl,
    int? estimatedTimeMinutes,
    int? calories,
    List<String>? equipmentIcons,
    String? mealType,
    int? energyLevel,
    String? cuisine,
    String? skillLevel,
  }) {
    return RecipePreview(
      id: id ?? this.id,
      title: title ?? this.title,
      vibeDescription: vibeDescription ?? this.vibeDescription,
      ingredients: ingredients ?? this.ingredients,
      mainIngredients: mainIngredients ?? this.mainIngredients,
      imageUrl: imageUrl ?? this.imageUrl,
      estimatedTimeMinutes: estimatedTimeMinutes ?? this.estimatedTimeMinutes,
      calories: calories ?? this.calories,
      equipmentIcons: equipmentIcons ?? this.equipmentIcons,
      mealType: mealType ?? this.mealType,
      energyLevel: energyLevel ?? this.energyLevel,
      cuisine: cuisine ?? this.cuisine,
      skillLevel: skillLevel ?? this.skillLevel,
    );
  }
}
