import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_swipe/core/router/app_router.dart';
import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/features/auth/providers/auth_provider.dart';

/// Main wrapper that provides the notched bottom navigation shell
class MainWrapper extends ConsumerWidget {
  final Widget child;

  const MainWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      resizeToAvoidBottomInset:
          false, // CRITICAL: Prevents FAB from moving when keyboard opens
      extendBody:
          true, // CRITICAL: Allows content to extend behind BottomAppBar
      body: child,
      floatingActionButton: _buildAIFab(context, ref),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _NotchedBottomNavBar(
        onAIPressed: () => _handleAIPressed(context, ref),
      ),
    );
  }

  Widget _buildAIFab(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 56,
      width: 56,
      child: FloatingActionButton(
        onPressed: () => _handleAIPressed(context, ref),
        backgroundColor: AppTheme.primaryColor,
        elevation: 3,
        shape: const CircleBorder(),
        child: const Icon(Icons.restaurant, color: Colors.white, size: 26),
      ),
    );
  }

  void _handleAIPressed(BuildContext context, WidgetRef ref) {
    final authState = ref.read(authProvider);

    // Guest check - show auth modal if not signed in or anonymous
    if (!authState.isSignedIn || authState.user?.isAnonymous == true) {
      _showAuthRequiredModal(context);
      return;
    }

    // Navigate to AI generation screen
    context.push(AppRoutes.aiGenerate);
  }

  void _showAuthRequiredModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Icon(
              Icons.restaurant,
              size: 48,
              color: AppTheme.primaryColor,
            ),
            const SizedBox(height: 16),
            const Text(
              'Kitchen Hub',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create personalized recipes tailored to your pantry, preferences, and cooking energy level.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.go(AppRoutes.login);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Sign In'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.go(AppRoutes.signup);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Sign Up'),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}

class _NotchedBottomNavBar extends StatelessWidget {
  final VoidCallback onAIPressed;

  const _NotchedBottomNavBar({required this.onAIPressed});

  @override
  Widget build(BuildContext context) {
    final currentIndex = _calculateSelectedIndex(context);

    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 6,
      color: AppTheme.surfaceColor,
      elevation: 8,
      height: 64,
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Left side: Home, Pantry
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: currentIndex == 0,
                  onTap: () {
                    shellNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                    context.go(AppRoutes.home);
                  },
                ),
                // TODO: SWIPE FEATURE — uncomment to restore the Swipe tab
                // _NavItem(
                //   icon: Icons.swipe_outlined,
                //   selectedIcon: Icons.swipe_rounded,
                //   label: 'Swipe',
                //   isSelected: currentIndex == 1,
                //   onTap: () {
                //     shellNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                //     context.go(AppRoutes.swipe);
                //   },
                // ),
                _NavItem(
                  icon: Icons.kitchen_outlined,
                  selectedIcon: Icons.kitchen_rounded,
                  label: 'Pantry',
                  isSelected: currentIndex == 2,
                  onTap: () {
                    shellNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                    context.go(AppRoutes.pantry);
                  },
                ),
              ],
            ),
          ),

          // Center gap for FAB with text label below it
          SizedBox(
            width: 80,
            child: GestureDetector(
              onTap: onAIPressed,
              behavior: HitTestBehavior.opaque,
              child: CustomPaint(
                size: const Size(80, 64),
                painter: _CurvedTextPainter(
                  text: 'My chef',
                  textStyle: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textLight,
                    letterSpacing: 2.5,
                  ),
                  radius: 40, // Perfect radius to fit below the notch
                ),
              ),
            ),
          ),

          // Right side: Recipes, Settings
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NavItem(
                  icon: Icons.restaurant_menu_outlined,
                  selectedIcon: Icons.restaurant_menu_rounded,
                  label: 'Recipes',
                  isSelected: currentIndex == 3,
                  onTap: () {
                    shellNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                    context.go(AppRoutes.recipes);
                  },
                ),
                _NavItem(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                  label: 'Settings',
                  isSelected: currentIndex == 4,
                  onTap: () {
                    shellNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                    context.go(AppRoutes.settings);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(AppRoutes.home)) return 0;
    // TODO: SWIPE FEATURE — restore index 1 when swipe tab is re-added
    // if (location.startsWith(AppRoutes.swipe)) return 1;
    if (location.startsWith(AppRoutes.pantry)) return 2;
    if (location.startsWith(AppRoutes.recipes)) return 3;
    if (location.startsWith(AppRoutes.settings)) return 4;
    return 0;
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected ? AppTheme.primaryColor : AppTheme.textLight,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppTheme.primaryColor : AppTheme.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurvedTextPainter extends CustomPainter {
  final String text;
  final TextStyle textStyle;
  final double radius;

  _CurvedTextPainter({
    required this.text,
    required this.textStyle,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Top-center of the gap is exactly the center of the FAB circle
    canvas.translate(size.width / 2, 0);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    
    double totalAngle = 0;
    final List<double> charAngles = [];

    for (int i = 0; i < text.length; i++) {
      textPainter.text = TextSpan(text: text[i], style: textStyle);
      textPainter.layout();
      final charAngle = textPainter.width / radius;
      charAngles.add(charAngle);
      totalAngle += charAngle;
    }

    // Start angle at bottom-left (pi/2 + totalAngle/2). Sweep from left to right by DECREASING angle.
    double currentAngle = (math.pi / 2) + (totalAngle / 2);

    for (int i = 0; i < text.length; i++) {
      textPainter.text = TextSpan(text: text[i], style: textStyle);
      textPainter.layout();

      final charAngle = charAngles[i];
      // Move angle to the center of the character (decreasing angle moves right)
      currentAngle -= charAngle / 2;

      canvas.save();
      
      // Find position on the arc
      final x = radius * math.cos(currentAngle);
      final y = radius * math.sin(currentAngle);
      canvas.translate(x, y);
      
      // Rotate the canvas so the letter points up/down correctly
      // math.pi / 2 points down. Subtracting it makes the letter upright.
      canvas.rotate(currentAngle - math.pi / 2);

      // Draw the character centered
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );

      canvas.restore();
      
      // Move to the next character
      currentAngle -= charAngle / 2;
    }
  }

  @override
  bool shouldRepaint(covariant _CurvedTextPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.radius != radius;
  }
}
