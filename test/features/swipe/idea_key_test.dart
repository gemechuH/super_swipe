import 'package:flutter_test/flutter_test.dart';
import 'package:super_swipe/features/swipe/services/idea_key.dart';

void main() {
  group('ideaKey', () {
    test('is stable for same title/ingredients regardless of order/case', () {
      final a = buildIdeaKey(
        energyLevel: 2,
        title: 'Spicy Chicken Bowl',
        ingredients: const ['Chicken', 'Rice', 'Garlic Powder'],
      );

      final b = buildIdeaKey(
        energyLevel: 2,
        title: '  spicy chicken bowl  ',
        ingredients: const ['garlic powder', 'rice', 'CHICKEN'],
      );

      expect(a, equals(b));
    });

    test('changes when energyLevel changes', () {
      final a = buildIdeaKey(
        energyLevel: 1,
        title: 'Spicy Chicken Bowl',
        ingredients: const ['chicken', 'rice'],
      );

      final b = buildIdeaKey(
        energyLevel: 2,
        title: 'Spicy Chicken Bowl',
        ingredients: const ['chicken', 'rice'],
      );

      expect(a, isNot(equals(b)));
    });
  });
}
