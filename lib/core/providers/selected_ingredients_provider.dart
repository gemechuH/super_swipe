import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manages selected pantry ingredients state across navigation.
/// NOT auto-disposed to persist across tab switches.
class SelectedIngredientsNotifier extends StateNotifier<Set<String>> {
  SelectedIngredientsNotifier() : super({});

  /// Initialize with all pantry items (called on first load)
  void initializeIfEmpty(List<String> allItems) {
    if (state.isEmpty && allItems.isNotEmpty) {
      state = allItems.toSet();
    }
  }

  /// Sync with current pantry (remove items no longer in pantry)
  void syncWithPantry(List<String> currentPantryItems) {
    final pantrySet = currentPantryItems.toSet();
    // Remove any selected items that are no longer in pantry
    state = state.intersection(pantrySet);
    // If after sync we have no items but pantry has items, select all
    if (state.isEmpty && currentPantryItems.isNotEmpty) {
      state = pantrySet;
    }
  }

  /// Toggle single ingredient selection
  /// Returns false if deselecting would leave no items selected
  bool toggleIngredient(String name) {
    if (state.contains(name)) {
      // Trying to deselect - check if it's the last one
      if (state.length <= 1) {
        return false; // Deny deselection of last item
      }
      state = {...state}..remove(name);
    } else {
      state = {...state, name};
    }
    return true;
  }

  /// Select all items
  void selectAll(List<String> allItems) {
    state = allItems.toSet();
  }

  /// Deselect all except one (keeps first item)
  void deselectAllExceptOne(List<String> allItems) {
    if (allItems.isNotEmpty) {
      state = {allItems.first};
    }
  }

  /// Get current selection
  Set<String> get selectedItems => state;

  /// Check if all items are selected
  bool isAllSelected(List<String> allItems) {
    return state.length == allItems.length && allItems.isNotEmpty;
  }
}

/// Non-autodispose provider for selected ingredients persistence across tabs
final selectedIngredientsProvider =
    StateNotifierProvider<SelectedIngredientsNotifier, Set<String>>((ref) {
      return SelectedIngredientsNotifier();
    });
