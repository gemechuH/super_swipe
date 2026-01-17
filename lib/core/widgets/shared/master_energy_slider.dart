import 'package:flutter/material.dart';
import 'package:super_swipe/core/config/swipe_constants.dart';
import 'package:super_swipe/core/theme/app_theme.dart';

/// A reusable Energy Level slider with consistent styling across the app.
/// Uses emoji labels and gradient track for premium look.
class MasterEnergySlider extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final String? label;
  final bool showLabels;

  const MasterEnergySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    final int clampedValue = value.clamp(
      EnergyLevel.minValue,
      EnergyLevel.maxValue,
    );
    final level = EnergyLevel.fromInt(clampedValue);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Current value display with emoji
          Text(
            level.sliderLabel,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            level.sliderDescription,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.primaryColor,
              inactiveTrackColor: AppTheme.primaryColor.withValues(alpha: 0.2),
              thumbColor: AppTheme.primaryColor,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              trackHeight: 6,
            ),
            child: Slider(
              value: clampedValue.toDouble(),
              min: EnergyLevel.minValue.toDouble(),
              max: EnergyLevel.maxValue.toDouble(),
              divisions: EnergyLevel.maxValue - EnergyLevel.minValue,
              onChanged: (v) => onChanged(
                v.round().clamp(EnergyLevel.minValue, EnergyLevel.maxValue),
              ),
            ),
          ),

          // Labels
          if (showLabels)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sleepy',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    'Energized',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
