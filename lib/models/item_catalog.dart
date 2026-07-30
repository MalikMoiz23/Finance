import 'expense.dart';
import 'expense_category.dart';

/// One autocomplete row: what you bought, which category it belongs to, and
/// what it usually costs.
class ItemSuggestion {
  const ItemSuggestion({
    required this.name,
    required this.category,
    this.typicalAmount,
    this.uses = 0,
    this.lastUsed,
  });

  final String name;
  final ExpenseCategory category;

  /// The most recent price paid, offered as a default when adding.
  final double? typicalAmount;

  /// How many times this account has bought it. 0 for the built-in catalogue.
  final int uses;

  final DateTime? lastUsed;

  bool get fromHistory => uses > 0;
}

/// Item names for the autocomplete.
///
/// Suggestions come from the account's own history first — including the last
/// price paid — and fall back to a built-in list so a brand new account still
/// gets useful completions on day one.
abstract final class ItemCatalog {
  static const starters = <ExpenseCategory, List<String>>{
    ExpenseCategory.groceries: [
      'Chicken',
      'Beef',
      'Mutton',
      'Fish',
      'Eggs',
      'Milk',
      'Yogurt',
      'Bread',
      'Atta',
      'Rice',
      'Sugar',
      'Tea',
      'Cooking oil',
      'Ghee',
      'Vegetables',
      'Fruit',
      'Onions',
      'Tomatoes',
      'Potatoes',
      'Daal',
      'Spices',
      'Biscuits',
      'Soap',
      'Detergent',
      'Shampoo',
      'Toothpaste',
    ],
    ExpenseCategory.fuel: [
      'Petrol',
      'Diesel',
      'CNG',
      'Rickshaw fare',
      'Careem ride',
      'Bus fare',
      'Bike service',
      'Car service',
      'Car wash',
      'Parking',
    ],
    ExpenseCategory.dining: [
      'Restaurant',
      'Food delivery',
      'Chai',
      'Samosa',
      'Ice cream',
      'Bakery',
      'Pizza',
      'Burger',
      'Biryani',
      'Juice',
    ],
    ExpenseCategory.bills: [
      'Electricity bill',
      'Gas bill',
      'Water bill',
      'Internet bill',
      'Mobile top-up',
      'TV subscription',
      'Trash collection',
    ],
    ExpenseCategory.rent: [
      'House rent',
      'Maintenance',
      'Plumber',
      'Electrician',
      'Carpenter',
      'Paint',
      'Furniture',
    ],
    ExpenseCategory.health: [
      'Medicines',
      'Doctor visit',
      'Lab tests',
      'Dentist',
      'Spectacles',
      'Vitamins',
    ],
    ExpenseCategory.shopping: [
      'Clothes',
      'Shoes',
      'Kids clothes',
      'Phone accessories',
      'Kitchen items',
      'Bedding',
      'Gift',
      'Toys',
    ],
    ExpenseCategory.other: [
      'School fee',
      'Tuition',
      'Stationery',
      'Haircut',
      'Charity',
      'Courier',
      'Repair',
    ],
  };

  /// Everything the account has bought before, newest price first, most used
  /// first. Keyed by lowercase name so "chicken" and "Chicken" are one item.
  static List<ItemSuggestion> fromHistory(List<Expense> expenses) {
    final byName = <String, _Tally>{};
    for (final expense in expenses) {
      final name = expense.item.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      final tally = byName.putIfAbsent(key, () => _Tally(name));
      tally.add(expense);
    }
    final out = byName.values.map((t) => t.toSuggestion()).toList()
      ..sort((a, b) {
        final byUses = b.uses.compareTo(a.uses);
        if (byUses != 0) return byUses;
        return (b.lastUsed ?? DateTime(0)).compareTo(a.lastUsed ?? DateTime(0));
      });
    return out;
  }

  /// Recently bought items, newest first — the one-tap "buy again" chips.
  static List<ItemSuggestion> recent(List<Expense> expenses, {int limit = 6}) {
    final seen = <String>{};
    final out = <ItemSuggestion>[];
    final history = fromHistory(expenses);
    final byRecency = [...history]
      ..sort(
        (a, b) =>
            (b.lastUsed ?? DateTime(0)).compareTo(a.lastUsed ?? DateTime(0)),
      );
    for (final suggestion in byRecency) {
      if (seen.add(suggestion.name.toLowerCase())) out.add(suggestion);
      if (out.length == limit) break;
    }
    return out;
  }

  /// Autocomplete for [query]: the account's own items first (they carry a
  /// price), then the built-in catalogue. Prefix matches outrank substring ones.
  static List<ItemSuggestion> suggest({
    required String query,
    required List<Expense> history,
    int limit = 6,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return recent(history, limit: limit);

    final own = fromHistory(history);
    final taken = <String>{};
    final prefix = <ItemSuggestion>[];
    final contains = <ItemSuggestion>[];

    void consider(ItemSuggestion suggestion) {
      final key = suggestion.name.toLowerCase();
      if (!taken.add(key)) return;
      if (key.startsWith(q)) {
        prefix.add(suggestion);
      } else if (key.contains(q)) {
        contains.add(suggestion);
      } else {
        taken.remove(key); // no match; let a later source try
      }
    }

    for (final suggestion in own) {
      consider(suggestion);
    }
    for (final entry in starters.entries) {
      for (final name in entry.value) {
        consider(ItemSuggestion(name: name, category: entry.key));
      }
    }

    return [...prefix, ...contains].take(limit).toList();
  }

  /// Total spent per item in [expenses], biggest first — "what do I buy most".
  static List<
    ({String name, ExpenseCategory category, double total, int count})
  >
  topItems(List<Expense> expenses, {int limit = 5}) {
    final byName = <String, _Tally>{};
    for (final expense in expenses) {
      final name = expense.item.trim();
      if (name.isEmpty) continue;
      byName.putIfAbsent(name.toLowerCase(), () => _Tally(name)).add(expense);
    }
    final rows =
        byName.values
            .map(
              (t) => (
                name: t.display,
                category: t.category,
                total: t.total,
                count: t.count,
              ),
            )
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));
    return rows.take(limit).toList();
  }
}

class _Tally {
  _Tally(this.display);

  final String display;
  ExpenseCategory category = ExpenseCategory.other;
  double total = 0;
  int count = 0;
  double? lastAmount;
  DateTime? lastUsed;

  void add(Expense expense) {
    total += expense.amount;
    count++;
    // The newest entry defines the category and the offered price.
    final at = expense.createdAt;
    if (lastUsed == null || at.isAfter(lastUsed!)) {
      lastUsed = at;
      lastAmount = expense.amount;
      category = expense.category;
    }
  }

  ItemSuggestion toSuggestion() => ItemSuggestion(
    name: display,
    category: category,
    typicalAmount: lastAmount,
    uses: count,
    lastUsed: lastUsed,
  );
}
