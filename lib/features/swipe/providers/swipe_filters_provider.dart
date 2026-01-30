import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_swipe/features/swipe/models/swipe_filters.dart';

// Re-export SwipeFilters model for convenience
export 'package:super_swipe/features/swipe/models/swipe_filters.dart';

/// Provider for the current swipe filters state
final swipeFiltersProvider =
    StateNotifierProvider<SwipeFiltersNotifier, SwipeFilters>((ref) {
      return SwipeFiltersNotifier();
    });

/// Notifier that manages swipe filter state
class SwipeFiltersNotifier extends StateNotifier<SwipeFilters> {
  SwipeFiltersNotifier() : super(const SwipeFilters());

  /// Toggle a diet filter on/off
  void toggleDiet(SwipeDiet diet) {
    final newDiets = Set<SwipeDiet>.from(state.diets);
    if (newDiets.contains(diet)) {
      newDiets.remove(diet);
    } else {
      newDiets.add(diet);
    }
    state = state.copyWith(diets: newDiets);
    _logChange('Diet toggled: $diet, active diets: $newDiets');
  }

  /// Set the time filter
  void setTimeFilter(SwipeTimeFilter filter) {
    if (state.timeFilter == filter) return;
    state = state.copyWith(timeFilter: filter);
    _logChange('Time filter set to: ${filter.displayName}');
  }

  /// Set the meal type filter
  void setMealType(SwipeMealType? mealType) {
    if (state.mealType == mealType) return;
    if (mealType == null) {
      state = state.copyWith(clearMealType: true);
    } else {
      state = state.copyWith(mealType: mealType);
    }
    _logChange('Meal type set to: ${mealType?.displayName ?? 'Any'}');
  }

  /// Toggle a cooking method on/off
  void toggleCookingMethod(SwipeCookingMethod method) {
    final newMethods = Set<SwipeCookingMethod>.from(state.cookingMethods);
    if (newMethods.contains(method)) {
      newMethods.remove(method);
    } else {
      newMethods.add(method);
    }
    state = state.copyWith(cookingMethods: newMethods);
    _logChange('Cooking method toggled: $method');
  }

  /// Set the custom text filter
  void setCustomText(String text) {
    // Trim to max 200 characters
    final trimmed = text.length > 200 ? text.substring(0, 200) : text;
    if (state.customText == trimmed) return;
    state = state.copyWith(customText: trimmed);
    _logChange('Custom text set: "${trimmed.substring(0, trimmed.length.clamp(0, 30))}..."');
  }

  /// Clear all filters to default
  void clearAll() {
    state = const SwipeFilters();
    _logChange('All filters cleared');
  }

  void _logChange(String message) {
    if (kDebugMode) {
      debugPrint('[SwipeFiltersNotifier] $message');
    }
  }
}

