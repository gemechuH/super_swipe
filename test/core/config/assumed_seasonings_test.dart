import 'package:flutter_test/flutter_test.dart';
import 'package:super_swipe/core/config/assumed_seasonings.dart';
import 'package:super_swipe/core/models/pantry_item.dart';

PantryItem _item(String name) {
  final now = DateTime(2026, 1, 1);
  return PantryItem(
    id: name,
    userId: 'u1',
    name: name,
    normalizedName: name.toLowerCase().trim(),
    category: 'other',
    quantity: 1,
    addedAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('countNonSeasoningPantryItems', () {
    test('excludes canonical seasonings', () {
      final count = countNonSeasoningPantryItems([
        _item('sea salt'),
        _item('black pepper'),
        _item('chicken'),
      ], includeBasics: false);

      expect(count, 1);
    });

    test('treats butter as assumed only when includeBasics=true', () {
      final items = [_item('butter'), _item('chicken')];

      expect(
        countNonSeasoningPantryItems(items, includeBasics: true),
        1,
        reason: 'Butter should not count when basics are included.',
      );
      expect(
        countNonSeasoningPantryItems(items, includeBasics: false),
        2,
        reason: 'Butter should count when basics are NOT included.',
      );
    });
  });
}
