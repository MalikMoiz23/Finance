/// Stage names and units offered while adding to a project.
///
/// Suggestions only — any text is accepted. A project's own stages come first,
/// because after three entries the list you actually use beats any list shipped
/// in the app. The built-in names lean towards house building, since that is
/// what most of this money goes on, with the generic ones at the end for a
/// wedding, a vehicle or a one-off purchase.
abstract final class ProjectCatalog {
  static const stages = <String>[
    // Materials.
    'Bricks',
    'Blocks',
    'Cement',
    'Sand',
    'Crush',
    'Steel',
    'Concrete',
    'Wood / doors',
    'Windows',
    'Tiles',
    'Marble',
    'Paint',
    'Glass',
    'Grill',
    // Work.
    'Excavation',
    'Foundation',
    'Slab / roof',
    'Plaster',
    'Flooring',
    'Electric wiring',
    'Plumbing',
    'Sanitary',
    'Water tank',
    'Kitchen',
    'False ceiling',
    // People.
    'Mason labour',
    'Labour',
    'Electrician',
    'Plumber',
    'Carpenter',
    'Painter',
    'Contractor',
    // Everything else.
    'Transport',
    'Machinery rent',
    'Map approval',
    'Land',
    'Government fees',
    'Furniture',
    'Appliances',
    'Electronics',
    'Vehicle',
    'Decoration',
    'Catering',
    'Clothes',
    'Jewellery',
    'Travel',
    'Medical',
    'Other',
  ];

  static const units = <String>[
    'pieces',
    'bags',
    'kg',
    'ton',
    'ft',
    'sq ft',
    'cu ft',
    'metre',
    'trips',
    'days',
    'hours',
    'litres',
    'rolls',
    'sets',
    'sheets',
  ];

  /// The unit a stage is normally bought in, so picking "Cement" fills in
  /// "bags" without a second tap. Null when there is no obvious one.
  static String? unitFor(String stage) => _units[stage.trim().toLowerCase()];

  static const _units = <String, String>{
    'bricks': 'pieces',
    'blocks': 'pieces',
    'cement': 'bags',
    'sand': 'trips',
    'crush': 'trips',
    'steel': 'kg',
    'concrete': 'cu ft',
    'wood / doors': 'pieces',
    'windows': 'pieces',
    'tiles': 'sq ft',
    'marble': 'sq ft',
    'paint': 'litres',
    'glass': 'sq ft',
    'grill': 'sq ft',
    'plaster': 'sq ft',
    'flooring': 'sq ft',
    'mason labour': 'days',
    'labour': 'days',
    'electrician': 'days',
    'plumber': 'days',
    'carpenter': 'days',
    'painter': 'days',
    'transport': 'trips',
    'machinery rent': 'hours',
  };

  /// Stage suggestions for [query]: this project's own stages first, then the
  /// built-in names. Prefix matches outrank substring ones — the same ranking
  /// the daily-expense item autocomplete uses.
  static List<String> suggestStages({
    required String query,
    required List<String> used,
    int limit = 8,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      final out = <String>[];
      final taken = <String>{};
      for (final name in [...used, ...stages]) {
        if (taken.add(name.toLowerCase())) out.add(name);
        if (out.length == limit) break;
      }
      return out;
    }

    final taken = <String>{};
    final prefix = <String>[];
    final contains = <String>[];

    for (final name in [...used, ...stages]) {
      final key = name.toLowerCase();
      if (taken.contains(key)) continue;
      if (key.startsWith(q)) {
        taken.add(key);
        prefix.add(name);
      } else if (key.contains(q)) {
        taken.add(key);
        contains.add(name);
      }
    }

    return [...prefix, ...contains].take(limit).toList();
  }
}
