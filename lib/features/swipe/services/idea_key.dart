import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:super_swipe/core/config/assumed_seasonings.dart';

String buildIdeaKey({
  required int energyLevel,
  required String title,
  required Iterable<String> ingredients,
}) {
  final normTitle = normalizeIngredientName(title);
  final normIngredients =
      ingredients
          .map(normalizeIngredientName)
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();

  final payload = jsonEncode({
    'energyLevel': energyLevel,
    'title': normTitle,
    'ingredients': normIngredients,
  });

  final hash = sha256.convert(utf8.encode(payload)).toString();
  return hash;
}
