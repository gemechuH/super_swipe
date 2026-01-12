import 'package:flutter/material.dart';

import 'package:super_swipe/core/theme/app_theme.dart';
import 'package:super_swipe/core/widgets/loading/app_shimmer.dart';
import 'package:super_swipe/core/widgets/loading/skeleton.dart';

class AppPageLoading extends StatelessWidget {
  final EdgeInsets padding;

  const AppPageLoading({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
  });

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: padding,
          child: Column(
            children: const [
              SizedBox(height: 6),
              SkeletonRecipeCard(),
              SizedBox(height: AppTheme.spacingL),
              SkeletonRecipeCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class AppListLoading extends StatelessWidget {
  final int itemCount;
  const AppListLoading({super.key, this.itemCount = 8});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (context, index) => const SkeletonListTile(),
      ),
    );
  }
}

class AppInlineLoading extends StatelessWidget {
  final double size;
  final Color baseColor;
  final Color highlightColor;

  const AppInlineLoading({
    super.key,
    this.size = 18,
    this.baseColor = const Color(0xFFE0E0E0),
    this.highlightColor = const Color(0xFFF6F6F6),
  });

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: SkeletonCircle(size: size, color: baseColor),
    );
  }
}
