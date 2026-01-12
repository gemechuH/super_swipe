import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/models/pantry_item.dart';
import 'package:super_swipe/core/providers/user_data_providers.dart';
import 'package:super_swipe/core/providers/firestore_providers.dart';
import 'package:super_swipe/core/services/undo_service.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_loading.dart';
import 'package:super_swipe/features/pantry/widgets/pantry_category_selector.dart';

class PantryScreen extends ConsumerStatefulWidget {
  const PantryScreen({super.key});

  @override
  ConsumerState<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends ConsumerState<PantryScreen> {
  String _searchQuery = '';
  bool _showDepleted = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final pantryItemsAsync = ref.watch(pantryItemsProvider);

    return pantryItemsAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: const AppPageLoading(),
      ),
      error: (error, stack) => _buildErrorScreen(context, error, stack),
      data: (allItems) {
        final filtered = allItems.where((item) {
          if (!_showDepleted && item.quantity <= 0) return false;
          return item.name.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();
        return _buildScreen(context, authState, filtered);
      },
    );
  }

  Widget _buildScreen(
    BuildContext context,
    authState,
    List<PantryItem> filtered,
  ) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      // NOTE: No floatingActionButton - MainWrapper has one that overrides.
      // Add button is positioned inside body Stack instead.
      body: Stack(
        children: [
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacingL,
                      AppTheme.spacingXL,
                      AppTheme.spacingL,
                      AppTheme.spacingM,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Text(
                            'My Pantry',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 32,
                                ),
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingL),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceColor,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: TextField(
                                  onChanged: (value) =>
                                      setState(() => _searchQuery = value),
                                  decoration: InputDecoration(
                                    hintText: 'Search ingredients...',
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.only(
                                      left: 26,
                                      right: 20,
                                    ),
                                    hintStyle: TextStyle(
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppTheme.spacingM),
                            Container(
                              height: 48,
                              width: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.search_rounded,
                                  color: AppTheme.textPrimary,
                                ),
                                onPressed: () {},
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spacingM),
                        Row(
                          children: [
                            Switch(
                              value: _showDepleted,
                              onChanged: (v) =>
                                  setState(() => _showDepleted = v),
                              activeThumbColor: AppTheme.primaryColor,
                            ),
                            const Text(
                              'Show depleted items',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingL,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final item = filtered[index];
                      return Dismissible(
                        key: Key(item.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          if (_requireAuth() || _isGuest()) return false;
                          final authState = ref.read(authProvider);
                          if (authState.user == null) return false;

                          // Store item data for undo
                          final deletedItem = item;
                          final userId = authState.user!.uid;

                          try {
                            final pantryService = ref.read(
                              pantryServiceProvider,
                            );
                            await pantryService.deletePantryItem(
                              userId,
                              item.id,
                            );

                            // Register undo operation
                            if (context.mounted) {
                              ref
                                  .read(undoServiceProvider.notifier)
                                  .registerUndo(
                                    id: 'delete_pantry_${item.id}',
                                    description:
                                        '${item.name} removed from pantry',
                                    context: context,
                                    undoAction: () async {
                                      // Restore the item
                                      await pantryService.addPantryItem(
                                        userId,
                                        deletedItem.name,
                                        category: deletedItem.category,
                                        quantity: deletedItem.quantity,
                                      );
                                    },
                                  );
                            }
                            return true;
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to delete: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                            return false;
                          }
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          color: AppTheme.errorColor.withValues(alpha: 0.1),
                          child: const Icon(
                            Icons.delete_forever,
                            color: AppTheme.errorColor,
                          ),
                        ),
                        child: InkWell(
                          onTap: () {
                            if (_requireAuth() || _isGuest()) return;
                            _showQuantityEditor(item);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                _buildIconForItem(item.name),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${item.quantity}',
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Row(
                                      children: [
                                        Text(
                                          'Edit',
                                          style: TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        SizedBox(width: 6),
                                        Icon(
                                          Icons.chevron_right,
                                          color: AppTheme.textLight,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          'Swipe to delete',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: AppTheme.textSecondary
                                                .withValues(alpha: 0.4),
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Icon(
                                          Icons.swipe_left_sharp,
                                          size: 12,
                                          color: AppTheme.textSecondary
                                              .withValues(alpha: 0.4),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }, childCount: filtered.length),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
          // Positioned buttons row (avoids MainWrapper FAB conflict)
          Positioned(
            left: 16,
            right: 16,
            bottom: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Start Preparing button - only visible when pantry has items
                if (filtered.isNotEmpty)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 22),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Navigate to AI Recipe Generation
                          context.go('/ai-generate');
                        },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Start Preparing'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                // Add button
                FloatingActionButton.extended(
                  heroTag: 'pantryAddButton',
                  onPressed: () {
                    if (_requireAuth() || _isGuest()) return;
                    _showIngredientSelector();
                  },
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('Add'),
                  elevation: 3,
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _requireAuth() {
    final authState = ref.read(authProvider);
    if (authState.user == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Login Required'),
          content: const Text('Saving pantry changes requires login.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                GoRouter.of(context).go(AppRoutes.login);
              },
              child: const Text('Login'),
            ),
          ],
        ),
      );
      return true;
    }
    return false;
  }

  bool _isGuest() {
    final authState = ref.read(authProvider);
    if (authState.user?.isAnonymous == true) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Guest Mode Restriction'),
          content: const Text(
            'Guest users can view the pantry but cannot save changes.\n\n'
            'Create a free account to:\n• Save your pantry inventory\n• Get personalized recipe suggestions\n• Track your cooking progress\n\nSign up now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                GoRouter.of(context).go(AppRoutes.signup);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
              child: const Text('Sign Up'),
            ),
          ],
        ),
      );
      return true;
    }
    return false;
  }

  Widget _buildIconForItem(String name) {
    IconData icon = Icons.local_grocery_store;
    Color color = Colors.orange;
    final lower = name.toLowerCase();
    if (lower.contains('egg')) {
      icon = Icons.egg_outlined;
      color = Colors.brown;
    } else if (lower.contains('carrot')) {
      icon = Icons.emoji_food_beverage;
      color = Colors.deepOrange;
    } else if (lower.contains('bread')) {
      icon = Icons.bakery_dining;
      color = Colors.brown.shade400;
    } else if (lower.contains('chicken')) {
      icon = Icons.set_meal;
      color = Colors.deepOrangeAccent;
    } else if (lower.contains('spinach') || lower.contains('leaf')) {
      icon = Icons.eco_outlined;
      color = Colors.green;
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: Icon(icon, color: color)),
    );
  }

  Future<void> _showQuantityEditor(PantryItem item) async {
    if (_requireAuth() || _isGuest()) return;
    final authState = ref.read(authProvider);
    final user = authState.user;
    if (user == null) return;

    int qty = item.quantity;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(item.name),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Update quantity'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: isSaving
                            ? null
                            : () => setDialogState(
                                () => qty = (qty - 1).clamp(0, 9999),
                              ),
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$qty',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: isSaving
                            ? null
                            : () => setDialogState(
                                () => qty = (qty + 1).clamp(0, 9999),
                              ),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (qty == 0)
                    const Text(
                      'Quantity 0 will hide this item unless "Show depleted items" is enabled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await ref
                                .read(pantryServiceProvider)
                                .updatePantryItem(
                                  user.uid,
                                  item.id,
                                  quantity: qty,
                                );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Failed to update: $e'),
                                backgroundColor: AppTheme.errorColor,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: AppInlineLoading(
                            size: 18,
                            baseColor: Color(0xFFEFEFEF),
                            highlightColor: Color(0xFFFFFFFF),
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showIngredientSelector() async {
    if (_requireAuth() || _isGuest()) return;
    final authState = ref.read(authProvider);
    final user = authState.user;
    if (user == null) return;

    final pantryItems =
        ref.read(pantryItemsProvider).value ?? const <PantryItem>[];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return PantryCategorySelector(
          existingPantryItems: pantryItems,
          onApply: (toAdd, toRemove, categoryMap) async {
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            try {
              // We need to read the providers from the parent context,
              // or ensure the sheet has access to them.
              // Since we are in a closure, we can capture 'ref' from valid scope if this is ConsumerState.
              // Using 'ref.read' here is fine as long as we are in ConsumerState.
              final pantryService = ref.read(pantryServiceProvider);
              final userId = user.uid;

              // Handle Removals
              for (final key in toRemove) {
                final normKey = key.toLowerCase().trim();
                final itemsToDelete = pantryItems.where(
                  (i) =>
                      i.normalizedName.toLowerCase().trim() == normKey &&
                      i.quantity > 0,
                );
                for (final item in itemsToDelete) {
                  await pantryService.deletePantryItem(userId, item.id);
                }
              }

              // Handle Adds
              final batchPayload = <Map<String, dynamic>>[];
              for (final key in toAdd) {
                final normKey = key.toLowerCase().trim();
                final depletedItem = pantryItems
                    .where(
                      (i) =>
                          i.normalizedName.toLowerCase().trim() == normKey &&
                          i.quantity == 0,
                    )
                    .firstOrNull;

                if (depletedItem != null) {
                  await pantryService.updatePantryItem(
                    userId,
                    depletedItem.id,
                    name: key, // Keep original casing logic or map if available
                    category: categoryMap[key] ?? 'other',
                    quantity: 1,
                  );
                } else {
                  batchPayload.add({
                    'name': key,
                    'quantity': 1,
                    'category': categoryMap[key] ?? 'other',
                    'source': 'manual',
                  });
                }
              }

              if (batchPayload.isNotEmpty) {
                await pantryService.batchAddPantryItems(userId, batchPayload);
              }

              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Updated pantry (+${toAdd.length}, -${toRemove.length})',
                  ),
                  backgroundColor: AppTheme.successColor,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            } catch (e) {
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Failed to apply changes: $e'),
                  backgroundColor: AppTheme.errorColor,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildErrorScreen(
    BuildContext context,
    Object error,
    StackTrace stack,
  ) {
    final errorString = error.toString().toLowerCase();
    String title;
    String message;
    IconData icon;
    Color iconColor;
    String actionText;
    VoidCallback? onAction;

    if (errorString.contains('failed-precondition') ||
        errorString.contains('index')) {
      title = 'Database Setup Required';
      message =
          'Your pantry needs a database index to organize items by category.\n\nThis is a one-time setup that takes 2-3 minutes to complete.';
      icon = Icons.construction_rounded;
      iconColor = Colors.orange;
      actionText = 'Create Index in Firebase';
      final urlMatch = RegExp(r'https://[^\s]+').firstMatch(errorString);
      if (urlMatch != null) {
        final url = urlMatch.group(0)!;
        onAction = () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Index URL copied to clipboard.')),
          );
        };
      }
    } else if (errorString.contains('permission') ||
        errorString.contains('denied')) {
      title = 'Access Denied';
      message = 'You don\'t have permission to access the pantry.';
      icon = Icons.lock_rounded;
      iconColor = Colors.red;
      actionText = 'Sign In Again';
      onAction = () => context.go(AppRoutes.login);
    } else if (errorString.contains('network') ||
        errorString.contains('unavailable')) {
      title = 'Connection Issue';
      message =
          'Can\'t connect to the database.\n\nPlease check your internet connection and try again.';
      icon = Icons.wifi_off_rounded;
      iconColor = Colors.grey;
      actionText = 'Retry';
      onAction = () => setState(() {});
    } else {
      title = 'Something Went Wrong';
      message = 'We encountered an unexpected error while loading your pantry.';
      icon = Icons.error_outline_rounded;
      iconColor = Colors.deepOrange;
      actionText = 'Go Back';
      onAction = () => context.go(AppRoutes.home);
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Pantry'),
        backgroundColor: AppTheme.surfaceColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 50, color: iconColor),
                ),
                const SizedBox(height: 32),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (onAction != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.refresh),
                      label: Text(actionText),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => context.go(AppRoutes.home),
                  icon: const Icon(Icons.home),
                  label: const Text('Go to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
