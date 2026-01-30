import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Diet options (hard constraints - recipes MUST respect these)
enum SwipeDiet {
  vegetarian('Vegetarian'),
  vegan('Vegan'),
  glutenFree('Gluten-Free'),
  keto('Keto'),
  highProtein('High Protein');

  final String displayName;
  const SwipeDiet(this.displayName);

  String get promptConstraint {
    switch (this) {
      case SwipeDiet.vegetarian:
        return 'MUST be vegetarian (no meat, poultry, or fish)';
      case SwipeDiet.vegan:
        return 'MUST be vegan (no animal products whatsoever)';
      case SwipeDiet.glutenFree:
        return 'MUST be gluten-free (no wheat, barley, rye, or gluten-containing ingredients)';
      case SwipeDiet.keto:
        return 'MUST be keto-friendly (very low carb, high fat, no sugar or starchy foods)';
      case SwipeDiet.highProtein:
        return 'MUST be high-protein (at least 25g protein per serving)';
    }
  }
}

/// Time/Effort filter
enum SwipeTimeFilter {
  under30('Under 30 min', 30),
  under60('Under 1 hour', 60),
  anyTime('Any time', null);

  final String displayName;
  final int? maxMinutes;
  const SwipeTimeFilter(this.displayName, this.maxMinutes);
}

/// Meal type filter
enum SwipeMealType {
  breakfast('Breakfast'),
  lunch('Lunch'),
  dinner('Dinner'),
  snack('Snack');

  final String displayName;
  const SwipeMealType(this.displayName);

  String get promptValue => name.toLowerCase();
}

/// Cooking method filter (optional)
enum SwipeCookingMethod {
  airFryer('Air Fryer'),
  oven('Oven'),
  stoveTop('Stove Top');

  final String displayName;
  const SwipeCookingMethod(this.displayName);
}

/// Swipe filters model - contains all filter state
@immutable
class SwipeFilters {
  /// Diet restrictions (hard constraints - multi-select)
  final Set<SwipeDiet> diets;

  /// Time/effort filter
  final SwipeTimeFilter timeFilter;

  /// Meal type filter
  final SwipeMealType? mealType;

  /// Cooking method (optional, only applied if selected)
  final Set<SwipeCookingMethod> cookingMethods;

  /// Custom text filter (soft preference, max 200 chars)
  final String customText;

  const SwipeFilters({
    this.diets = const {},
    this.timeFilter = SwipeTimeFilter.anyTime,
    this.mealType,
    this.cookingMethods = const {},
    this.customText = '',
  });

  /// Create a copy with modified fields
  SwipeFilters copyWith({
    Set<SwipeDiet>? diets,
    SwipeTimeFilter? timeFilter,
    SwipeMealType? mealType,
    bool clearMealType = false,
    Set<SwipeCookingMethod>? cookingMethods,
    String? customText,
  }) {
    return SwipeFilters(
      diets: diets ?? this.diets,
      timeFilter: timeFilter ?? this.timeFilter,
      mealType: clearMealType ? null : (mealType ?? this.mealType),
      cookingMethods: cookingMethods ?? this.cookingMethods,
      customText: customText ?? this.customText,
    );
  }

  /// Generate a unique signature for these filters
  /// Used to track when filters change and deck needs refresh
  String get signature {
    final payload = <String, dynamic>{
      'diets': diets.map((d) => d.name).toList()..sort(),
      'timeFilter': timeFilter.name,
      'mealType': mealType?.name ?? '',
      'cookingMethods': cookingMethods.map((m) => m.name).toList()..sort(),
      'customText': customText.toLowerCase().trim(),
    };
    final bytes = utf8.encode(jsonEncode(payload));
    return sha256.convert(bytes).toString().substring(0, 16);
  }

  /// Check if any filters are active (non-default)
  bool get hasActiveFilters {
    return diets.isNotEmpty ||
        timeFilter != SwipeTimeFilter.anyTime ||
        mealType != null ||
        cookingMethods.isNotEmpty ||
        customText.trim().isNotEmpty;
  }

  /// Convert diet constraints to prompt text
  String get dietPromptConstraints {
    if (diets.isEmpty) return '';
    return diets.map((d) => d.promptConstraint).join('\n');
  }

  /// Get meal type for prompt
  String get mealTypeForPrompt {
    return mealType?.promptValue ?? 'any';
  }

  /// Get cooking methods for prompt
  String get cookingMethodsForPrompt {
    if (cookingMethods.isEmpty) return '';
    return 'Preferred cooking methods: ${cookingMethods.map((m) => m.displayName).join(', ')}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SwipeFilters &&
        setEquals(other.diets, diets) &&
        other.timeFilter == timeFilter &&
        other.mealType == mealType &&
        setEquals(other.cookingMethods, cookingMethods) &&
        other.customText == customText;
  }

  @override
  int get hashCode {
    return Object.hash(
      Object.hashAllUnordered(diets),
      timeFilter,
      mealType,
      Object.hashAllUnordered(cookingMethods),
      customText,
    );
  }

  @override
  String toString() {
    return 'SwipeFilters(diets: $diets, time: $timeFilter, meal: $mealType, '
        'methods: $cookingMethods, custom: "$customText")';
  }
}

