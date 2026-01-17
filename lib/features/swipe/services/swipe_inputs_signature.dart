import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:super_swipe/core/config/assumed_seasonings.dart';

const String kPantryFirstSwipePromptVersion = 'pantry_first_swipe_v1';

String buildSwipeInputsSignature({
  required Iterable<String> pantryIngredientNames,
  required bool includeBasics,
  required bool willingToShop,
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

  final payload = <String, dynamic>{
    'v': promptVersion,
    'includeBasics': includeBasics,
    'willingToShop': willingToShop,
    'pantry': normalized,
  };

  final bytes = utf8.encode(jsonEncode(payload));
  return sha256.convert(bytes).toString();
}
