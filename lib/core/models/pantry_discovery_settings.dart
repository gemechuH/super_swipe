class PantryDiscoverySettings {
  final bool includeBasics;
  final bool willingToShop;

  const PantryDiscoverySettings({
    this.includeBasics = true,
    this.willingToShop = false,
  });

  factory PantryDiscoverySettings.fromMap(Map<String, dynamic> map) {
    return PantryDiscoverySettings(
      includeBasics: map['includeBasics'] ?? true,
      willingToShop: map['willingToShop'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {'includeBasics': includeBasics, 'willingToShop': willingToShop};
  }

  PantryDiscoverySettings copyWith({bool? includeBasics, bool? willingToShop}) {
    return PantryDiscoverySettings(
      includeBasics: includeBasics ?? this.includeBasics,
      willingToShop: willingToShop ?? this.willingToShop,
    );
  }
}
