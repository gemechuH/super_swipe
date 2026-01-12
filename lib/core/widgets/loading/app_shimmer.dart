import 'package:flutter/material.dart';

class AppShimmer extends StatefulWidget {
  final Widget child;
  final Duration period;
  final Color baseColor;
  final Color highlightColor;

  const AppShimmer({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1200),
    this.baseColor = const Color(0xFFE9E9E9),
    this.highlightColor = const Color(0xFFF6F6F6),
  });

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        // Slide the highlight from left -> right.
        final begin = Alignment(-1.2 + (2.4 * t), 0);
        final end = Alignment(-0.2 + (2.4 * t), 0);

        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            return LinearGradient(
              begin: begin,
              end: end,
              colors: <Color>[
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const <double>[0.0, 0.5, 1.0],
            ).createShader(rect);
          },
          child: child,
        );
      },
    );
  }
}
