import 'package:flutter/material.dart';

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;
  final Color color;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.color = const Color(0xFFE9E9E9),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: color, borderRadius: borderRadius),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  final Color color;

  const SkeletonLine({
    super.key,
    this.width,
    this.height = 14,
    this.color = const Color(0xFFE9E9E9),
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(10),
      color: color,
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  final double size;
  final Color color;

  const SkeletonCircle({
    super.key,
    this.size = 18,
    this.color = const Color(0xFFE9E9E9),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class SkeletonListTile extends StatelessWidget {
  final bool showLeading;

  const SkeletonListTile({super.key, this.showLeading = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (showLeading) ...[
            const SkeletonCircle(size: 44),
            const SizedBox(width: 14),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 220, height: 16),
                SizedBox(height: 10),
                SkeletonLine(width: 160, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonRecipeCard extends StatelessWidget {
  const SkeletonRecipeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(height: 220, borderRadius: BorderRadius.zero),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        SkeletonLine(width: 80, height: 14),
                        SizedBox(width: 10),
                        SkeletonLine(width: 60, height: 14),
                        SizedBox(width: 10),
                        SkeletonLine(width: 70, height: 14),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const SkeletonLine(width: 260, height: 20),
                    const SizedBox(height: 10),
                    const SkeletonLine(width: 320, height: 12),
                    const SizedBox(height: 8),
                    const SkeletonLine(width: 280, height: 12),
                    const SizedBox(height: 16),
                    Row(
                      children: const [
                        SkeletonLine(width: 90, height: 16),
                        SizedBox(width: 12),
                        SkeletonLine(width: 90, height: 16),
                        SizedBox(width: 12),
                        SkeletonLine(width: 90, height: 16),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
