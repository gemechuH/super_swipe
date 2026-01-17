import 'package:super_swipe/core/config/constants.dart';

/// Deterministic fallback recipe images.
///
/// We want:
/// - Swipe previews to have images even when AI doesn't provide one.
/// - Images to vary across recipe "types" (mealType/cuisine) and titles.
/// - No dependency on an Unsplash API key.
class RecipeImageUtils {
  RecipeImageUtils._();

  static const Map<String, List<String>> _mealTypePools = {
    'breakfast': [
      'https://images.unsplash.com/photo-1533089862017-5614ec45e25a?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1551024601-bec78aea704b?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1525351484163-7529414344d8?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1513442542250-854d436a73f2?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1525351484163-7529414344d8?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1484723091739-30a097e8f929?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1551963831-b3b1ca40c98e?auto=format&fit=crop&w=1200&q=80',
    ],
    'lunch': [
      'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1540914124281-342587941389?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1523986371872-9d3ba2e2f642?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1498837167922-ddd27525d352?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1551183053-bf91a1d81141?auto=format&fit=crop&w=1200&q=80',
    ],
    'dinner': [
      'https://images.unsplash.com/photo-1512058564366-18510be2db19?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1563379926898-05f4575a45d8?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1553621042-f6e147245754?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1604908177225-6f4d5f8b4e63?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1543352634-8730c07f67a9?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1467003909585-2f8a72700288?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=1200&q=80',
    ],
    'snack': [
      'https://images.unsplash.com/photo-1621506289937-a8e4df240d0b?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1604908177453-7462950a6a82?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1525385133512-2f3bdd039054?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1541592106381-b31e9677c0e5?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1521305916504-4a1121188589?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1528825871115-3581a5387919?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1505253216365-1dce3b8ca8f0?auto=format&fit=crop&w=1200&q=80',
    ],
    'dessert': [
      'https://images.unsplash.com/photo-1563729784474-d77dbb933a9e?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1505253216365-1dce3b8ca8f0?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1542826438-5d8f4e406c63?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1499636136210-6f4ee915583e?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1509440159598-8b90f4f4276f?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1551782450-a2132b4ba21d?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1534351590666-13e3e96b5017?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1519869325930-281384150729?auto=format&fit=crop&w=1200&q=80',
    ],
    'drinks': [
      'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1544145945-f90425340c7e?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1527169402691-a3fbde6d4d1b?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1510627498534-cf7e9002facc?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1532634726-8b9fb99825d0?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1541976844346-f18aeac57b06?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1542444592-0d599fcedd68?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1497534446932-c925b458314e?auto=format&fit=crop&w=1200&q=80',
    ],
  };

  static const Map<String, List<String>> _cuisinePools = {
    'italian': [
      'https://images.unsplash.com/photo-1523986371872-9d3ba2e2f642?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1528731708534-816fe59f90cb?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1525755662778-989d0524087e?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1529042410759-befb1204b468?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1603133872878-684f208fb84b?auto=format&fit=crop&w=1200&q=80',
    ],
    'mexican': [
      'https://images.unsplash.com/photo-1552332386-f8dd00dc2f85?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1615870216514-334cf2e02c21?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1505253758473-96b7015fcd40?auto=format&fit=crop&w=1200&q=80',
    ],
    'indian': [
      'https://images.unsplash.com/photo-1604908554162-19050f2f0e3c?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1600628422019-6c6d2c96e650?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1604909053191-57a3b7c6bdb0?auto=format&fit=crop&w=1200&q=80',
    ],
    'japanese': [
      'https://images.unsplash.com/photo-1541544181074-eefb6c15f5d5?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1553621042-cc3f1e77d13b?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1553621042-4fbb8fdb6430?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1562158070-57c420f5a9a4?auto=format&fit=crop&w=1200&q=80',
    ],
    'chinese': [
      'https://images.unsplash.com/photo-1553621042-68511e57caa2?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1553621042-5b29cddbbfe2?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1604908177453-7462950a6a82?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=1200&q=80',
    ],
    'mediterranean': [
      'https://images.unsplash.com/photo-1543339308-43e59d6b73a6?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1504754524776-8f4f37790ca0?auto=format&fit=crop&w=1200&q=80',
    ],
    'american': [
      'https://images.unsplash.com/photo-1550547660-d9450f859349?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1550317138-10000687a72b?auto=format&fit=crop&w=1200&q=80',
      'https://images.unsplash.com/photo-1550547660-1a9b5c49e3ce?auto=format&fit=crop&w=1200&q=80',
    ],
  };

  static String forRecipe({
    String? existing,
    required String title,
    required String mealType,
    required String cuisine,
    String? id,
    List<String>? ingredients,
  }) {
    final normalizedExisting = (existing ?? '').trim();
    if (normalizedExisting.isNotEmpty &&
        normalizedExisting != AppAssets.placeholderRecipe) {
      return normalizedExisting;
    }

    final cuisineKey = cuisine.trim().toLowerCase();
    final mealKey = mealType.trim().toLowerCase();

    final pool =
        _cuisinePools[cuisineKey] ??
        _mealTypePools[mealKey] ??
        const <String>[];

    if (pool.isEmpty) {
      return AppAssets.placeholderRecipe;
    }

    final ingredientHint = (ingredients ?? const <String>[])
        .take(3)
        .map((e) => e.toLowerCase().trim())
        .where((e) => e.isNotEmpty)
        .join(',');
    final seed = '$cuisineKey|$mealKey|$title|${id ?? ''}|$ingredientHint';
    final idx = _fnv1a32(seed) % pool.length;
    return pool[idx];
  }

  static int _fnv1a32(String input) {
    const int fnvPrime = 0x01000193;
    int hash = 0x811C9DC5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }
}
