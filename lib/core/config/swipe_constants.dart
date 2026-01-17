enum EnergyLevel {
  level0(
    0,
    sliderLabel: '😴 Sleepy',
    sliderDescription: 'Quick & easy (under 15 min)',
    summaryLabel: 'Zero (Ready-made)',
  ),
  level1(
    1,
    sliderLabel: '😐 Low',
    sliderDescription: 'Simple recipes (15-20 min)',
    summaryLabel: 'Low (Quick & Easy)',
  ),
  level2(
    2,
    sliderLabel: '🙂 Okay',
    sliderDescription: 'Moderate effort (20-30 min)',
    summaryLabel: 'Medium (Some Effort)',
  ),
  level3(
    3,
    sliderLabel: '😊 Good',
    sliderDescription: 'Some cooking (30-45 min)',
    summaryLabel: 'High (Full Cooking)',
  ),
  level4(
    4,
    sliderLabel: '⚡ Energized',
    sliderDescription: 'Elaborate (45+ min)',
    summaryLabel: 'Max (Elaborate)',
  );

  final int value;
  final String sliderLabel;
  final String sliderDescription;
  final String summaryLabel;

  const EnergyLevel(
    this.value, {
    required this.sliderLabel,
    required this.sliderDescription,
    required this.summaryLabel,
  });

  static const int minValue = 0;
  static const int maxValue = 4;

  static const String promptLegend = '0=ready-made, 4=elaborate';

  static EnergyLevel fromInt(int value) {
    for (final level in EnergyLevel.values) {
      if (level.value == value) return level;
    }
    // Default to middle energy rather than crashing on bad data.
    return EnergyLevel.level2;
  }

  String get promptScale => '$value/$maxValue';

  String get promptLine => '$promptScale ($promptLegend)';
}
