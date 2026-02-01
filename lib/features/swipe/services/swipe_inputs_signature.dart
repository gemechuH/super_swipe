import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:super_swipe/core/config/assumed_seasonings.dart';
import 'package:super_swipe/features/swipe/models/swipe_filters.dart';

const String kPantryFirstSwipePromptVersion = 'pantry_first_swipe_v2';

String buildSwipeInputsSignature({
  required Iterable<String> pantryIngredientNames,
  required bool includeBasics,
  required bool willingToShop,
  List<String> allergies = const <String>[],
  List<String> dietaryRestrictions = const <String>[],
  List<String> preferredCuisines = const <String>[],
  String mealType = '',
  String promptVersion = kPantryFirstSwipePromptVersion,
  // Swipe filter panel options
  SwipeFilters? swipeFilters,
}) {
  final normalized =
      pantryIngredientNames
          .map(normalizeIngredientName)
          .where((n) => n.isNotEmpty)
          .where(
            (n) => !isAssumedSeasoningName(n, includeBasics: includeBasics),
          )
          .toSet()
          .toList(growable: false)
        ..sort();

  final normalizedAllergies =
      allergies
          .map((e) => e.toLowerCase().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false)
        ..sort();

  final normalizedDietary =
      dietaryRestrictions
          .map((e) => e.toLowerCase().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false)
        ..sort();

  final normalizedCuisines =
      preferredCuisines
          .map((e) => e.toLowerCase().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false)
        ..sort();

  // Build filter signature if filters are provided
  final filterPayload = swipeFilters != null
      ? <String, dynamic>{
          'diets': swipeFilters.diets.map((d) => d.name).toList()..sort(),
          'timeFilter': swipeFilters.timeFilter.name,
          'mealType': swipeFilters.mealType?.name ?? '',
          'cookingMethods':
              swipeFilters.cookingMethods.map((m) => m.name).toList()..sort(),
          'customText': swipeFilters.customText.toLowerCase().trim(),
        }
      : <String, dynamic>{};

  final payload = <String, dynamic>{
    'v': promptVersion,
    'includeBasics': includeBasics,
    'willingToShop': willingToShop,
    'mealType': mealType.toLowerCase().trim(),
    'allergies': normalizedAllergies,
    'dietaryRestrictions': normalizedDietary,
    'preferredCuisines': normalizedCuisines,
    'pantry': normalized,
    'filters': filterPayload,
  };

  final bytes = utf8.encode(jsonEncode(payload));
  return sha256.convert(bytes).toString();
}
