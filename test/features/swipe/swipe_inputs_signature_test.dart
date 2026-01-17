import 'package:flutter_test/flutter_test.dart';
import 'package:super_swipe/features/swipe/services/swipe_inputs_signature.dart';

void main() {
  group('swipeInputsSignature', () {
    test('is stable for same inputs', () {
      final a = buildSwipeInputsSignature(
        pantryIngredientNames: const ['Chicken', 'Rice', 'Table Salt'],
        includeBasics: true,
        willingToShop: false,
      );

      final b = buildSwipeInputsSignature(
        pantryIngredientNames: const [' rice ', 'table salt', 'CHICKEN'],
        includeBasics: true,
        willingToShop: false,
      );

      expect(a, equals(b));
    });

    test('changes when toggles change', () {
      final base = buildSwipeInputsSignature(
        pantryIngredientNames: const ['Chicken', 'Rice'],
        includeBasics: true,
        willingToShop: false,
      );

      final willingToShop = buildSwipeInputsSignature(
        pantryIngredientNames: const ['Chicken', 'Rice'],
        includeBasics: true,
        willingToShop: true,
      );

      final includeBasicsOff = buildSwipeInputsSignature(
        pantryIngredientNames: const ['Chicken', 'Rice'],
        includeBasics: false,
        willingToShop: false,
      );

      expect(base, isNot(equals(willingToShop)));
      expect(base, isNot(equals(includeBasicsOff)));
    });

    test('treats butter as assumed only when includeBasics is true', () {
      final withBasics = buildSwipeInputsSignature(
        pantryIngredientNames: const ['butter', 'chicken', 'rice'],
        includeBasics: true,
        willingToShop: false,
      );

      final withoutBasics = buildSwipeInputsSignature(
        pantryIngredientNames: const ['butter', 'chicken', 'rice'],
        includeBasics: false,
        willingToShop: false,
      );

      expect(withBasics, isNot(equals(withoutBasics)));
    });
  });
}
