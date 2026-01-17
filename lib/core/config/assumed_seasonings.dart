import 'package:super_swipe/core/models/pantry_item.dart';

String normalizeIngredientName(String value) => value.toLowerCase().trim();

Set<String> canonicalAssumedSeasonings({required bool includeBasics}) {
  final base = <String>{
    // Salts
    'table salt',
    'sea salt',

    // Peppers
    'black pepper',
    'white pepper',

    // Oils
    'olive oil',
    'vegetable oil',
    'canola oil',

    // Spices
    'garlic powder',
    'onion powder',
    'dried oregano',
    'red pepper flakes',
  };

  if (includeBasics) {
    base.addAll({'butter', 'unsalted butter', 'salted butter'});
  }

  return base;
}

bool isAssumedSeasoningName(
  String ingredientName, {
  required bool includeBasics,
}) {
  final normalized = normalizeIngredientName(ingredientName);
  if (normalized.isEmpty) return false;

  final seasonings = canonicalAssumedSeasonings(includeBasics: includeBasics);
  if (seasonings.contains(normalized)) return true;

  // A small amount of leniency for common butter variants.
  if (includeBasics && RegExp(r'\bbutter\b').hasMatch(normalized)) return true;

  return false;
}

int countNonSeasoningPantryItems(
  Iterable<PantryItem> items, {
  required bool includeBasics,
}) {
  var count = 0;
  for (final item in items) {
    final name = item.normalizedName.isNotEmpty
        ? item.normalizedName
        : normalizeIngredientName(item.name);

    if (!isAssumedSeasoningName(name, includeBasics: includeBasics)) {
      count++;
    }
  }
  return count;
}
