import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:super_swipe/core/config/assumed_seasonings.dart';

const String kPantryFirstSwipePromptVersion = 'pantry_first_swipe_v1';

String buildSwipeInputsSignature({
  required Iterable<String> pantryIngredientNames,
  required bool includeBasics,
  required bool willingToShop,
  List<String> allergies = const <String>[],
  List<String> dietaryRestrictions = const <String>[],
  List<String> preferredCuisines = const <String>[],
  String mealType = '',
  String promptVersion = kPantryFirstSwipePromptVersion,
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

  final payload = <String, dynamic>{
    'v': promptVersion,
    'includeBasics': includeBasics,
    'willingToShop': willingToShop,
    'mealType': mealType.toLowerCase().trim(),
    'allergies': normalizedAllergies,
    'dietaryRestrictions': normalizedDietary,
    'preferredCuisines': normalizedCuisines,
    'pantry': normalized,
  };

  final bytes = utf8.encode(jsonEncode(payload));
  return sha256.convert(bytes).toString();
}
