import 'vehicle.dart';

/// A job the form can fill in with one tap, with the interval it usually comes
/// round at.
class ServicePreset {
  const ServicePreset(this.name, {this.intervalKm, this.intervalMonths});

  final String name;
  final int? intervalKm;
  final int? intervalMonths;
}

/// Usual maintenance intervals for a family car and a 70–125 cc bike.
///
/// These are **starting values**, not rules: the form shows them already filled
/// in, and whatever the mechanic actually said is what gets saved on the record.
abstract final class ServiceCatalog {
  static const car = <ServicePreset>[
    ServicePreset('Tuning', intervalKm: 10000, intervalMonths: 12),
    ServicePreset('Engine oil change', intervalKm: 5000, intervalMonths: 6),
    ServicePreset('Oil filter', intervalKm: 5000, intervalMonths: 6),
    ServicePreset('Air filter', intervalKm: 10000, intervalMonths: 12),
    ServicePreset('Wheel alignment', intervalKm: 10000, intervalMonths: 6),
    ServicePreset('Brake service', intervalKm: 20000, intervalMonths: 12),
    ServicePreset('Spark plugs', intervalKm: 20000, intervalMonths: 24),
    ServicePreset('AC service', intervalMonths: 12),
    ServicePreset('Coolant flush', intervalKm: 40000, intervalMonths: 24),
    ServicePreset('Battery check', intervalMonths: 12),
  ];

  static const bike = <ServicePreset>[
    ServicePreset('Tuning', intervalKm: 3000, intervalMonths: 6),
    ServicePreset('Engine oil change', intervalKm: 1000, intervalMonths: 2),
    ServicePreset('Chain clean & adjust', intervalKm: 500, intervalMonths: 1),
    ServicePreset('Air filter', intervalKm: 3000, intervalMonths: 6),
    ServicePreset('Brake shoes', intervalKm: 5000, intervalMonths: 12),
    ServicePreset('Spark plug', intervalKm: 5000, intervalMonths: 12),
    ServicePreset('Clutch adjust', intervalKm: 3000, intervalMonths: 6),
  ];

  static List<ServicePreset> forKind(VehicleKind kind) => switch (kind) {
    VehicleKind.car => car,
    VehicleKind.bike => bike,
  };

  /// The preset matching [name] for this kind, ignoring case and spaces.
  static ServicePreset? find(VehicleKind kind, String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final preset in forKind(kind)) {
      if (preset.name.toLowerCase() == key) return preset;
    }
    return null;
  }

  /// Jobs to offer on the form: what this vehicle has already had done first,
  /// most recent first, then the presets it has not used yet.
  static List<String> suggestions(
    VehicleKind kind,
    List<VehicleService> history,
  ) {
    final seen = <String>{};
    final out = <String>[];
    for (final record in history) {
      if (seen.add(record.serviceKey)) out.add(record.title);
    }
    for (final preset in forKind(kind)) {
      if (seen.add(preset.name.toLowerCase())) out.add(preset.name);
    }
    return out;
  }
}
