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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final isCompact = maxH.isFinite && maxH < 520;
        final isVeryCompact = maxH.isFinite && maxH < 320;

        final outerVPad = isVeryCompact ? 4.0 : 8.0;
        final outerHPad = isVeryCompact ? 4.0 : 8.0;
        final contentPad = isVeryCompact ? 12.0 : 16.0;

        // Estimate content height below the image (padding + lines + spacers).
        final belowImageHeight = isVeryCompact ? 132.0 : 196.0;

        final imageHeight = maxH.isFinite
            ? (maxH - (outerVPad * 2) - belowImageHeight).clamp(0.0, 280.0)
            : (isCompact ? 140.0 : 220.0);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: outerHPad, vertical: outerVPad),
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
                  SkeletonBox(
                    height: imageHeight,
                    borderRadius: BorderRadius.zero,
                  ),
                  Padding(
                    padding: EdgeInsets.all(contentPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: isVeryCompact
                          ? const [
                              FractionallySizedBox(
                                widthFactor: 0.72,
                                alignment: Alignment.centerLeft,
                                child: SkeletonLine(height: 18),
                              ),
                              SizedBox(height: 8),
                              FractionallySizedBox(
                                widthFactor: 0.92,
                                alignment: Alignment.centerLeft,
                                child: SkeletonLine(height: 12),
                              ),
                              SizedBox(height: 12),
                              FractionallySizedBox(
                                widthFactor: 0.68,
                                alignment: Alignment.centerLeft,
                                child: SkeletonLine(height: 12),
                              ),
                              SizedBox(height: 8),
                              FractionallySizedBox(
                                widthFactor: 0.78,
                                alignment: Alignment.centerLeft,
                                child: SkeletonLine(height: 12),
                              ),
                              SizedBox(height: 12),
                              SkeletonLine(width: 120, height: 14),
                            ]
                          : const [
                              FractionallySizedBox(
                                widthFactor: 0.75,
                                alignment: Alignment.centerLeft,
                                child: SkeletonLine(height: 20),
                              ),
                              SizedBox(height: 10),
                              FractionallySizedBox(
                                widthFactor: 0.92,
                                alignment: Alignment.centerLeft,
                                child: SkeletonLine(height: 12),
                              ),
                              SizedBox(height: 8),
                              FractionallySizedBox(
                                widthFactor: 0.82,
                                alignment: Alignment.centerLeft,
                                child: SkeletonLine(height: 12),
                              ),
                              SizedBox(height: 16),
                              FractionallySizedBox(
                                widthFactor: 0.68,
                                alignment: Alignment.centerLeft,
                                child: SkeletonLine(height: 12),
                              ),
                              SizedBox(height: 8),
                              FractionallySizedBox(
                                widthFactor: 0.78,
                                alignment: Alignment.centerLeft,
                                child: SkeletonLine(height: 12),
                              ),
                              SizedBox(height: 8),
                              FractionallySizedBox(
                                widthFactor: 0.62,
                                alignment: Alignment.centerLeft,
                                child: SkeletonLine(height: 12),
                              ),
                              SizedBox(height: 18),
                              SkeletonLine(width: 140, height: 16),
                            ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
