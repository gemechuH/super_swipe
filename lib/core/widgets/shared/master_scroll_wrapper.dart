import 'package:flutter/material.dart';

/// A standard scroll wrapper to prevent overflow errors.
/// Uses LayoutBuilder and SingleChildScrollView for safe scrolling.
class MasterScrollWrapper extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;

  const MasterScrollWrapper({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Container(
              color: backgroundColor,
              padding: padding ?? const EdgeInsets.all(20),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
