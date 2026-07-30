import 'dart:math';

import '../models/expense.dart';
import '../models/expense_category.dart';

/// Sample household spending, generated once on first launch so the charts have
/// something to show. Clearable from the dashboard menu ("Clear all expenses").
/// Seeded RNG, so the same install always gets the same demo set.
abstract final class DemoData {
  static const _notes = <ExpenseCategory, List<String>>{
    ExpenseCategory.groceries: [
      'Weekly grocery run',
      'Vegetables & fruit',
      'Milk, eggs, bread',
      'Atta & rice',
      'Chicken and meat',
    ],
    ExpenseCategory.fuel: [
      'Petrol',
      'Bike fuel',
      'Careem to office',
      'Rickshaw fare',
      'Car service',
    ],
    ExpenseCategory.dining: [
      'Family dinner',
      'Chai & samosa',
      'Lunch with friends',
      'Food delivery',
      'Ice cream run',
    ],
    ExpenseCategory.bills: [
      'Electricity bill',
      'Gas bill',
      'Internet bill',
      'Mobile top-up',
      'Water charges',
    ],
    ExpenseCategory.rent: ['Monthly rent', 'Maintenance', 'Plumber'],
    ExpenseCategory.health: [
      'Pharmacy',
      'Doctor visit',
      'Lab tests',
      'Dentist',
    ],
    ExpenseCategory.shopping: [
      'Kids clothes',
      'Shoes',
      'Kitchen items',
      'Eid shopping',
      'Phone charger',
    ],
    ExpenseCategory.other: [
      'Gift',
      'Charity',
      'Stationery',
      'Haircut',
      'Parking',
    ],
  };

  /// (min, max) amount in PKR, and roughly how many entries per 30 days.
  static const _profile = <ExpenseCategory, (double, double, double)>{
    ExpenseCategory.groceries: (1400, 9000, 8),
    ExpenseCategory.fuel: (1800, 6500, 5),
    ExpenseCategory.dining: (700, 4800, 5),
    ExpenseCategory.bills: (2800, 17000, 3),
    ExpenseCategory.health: (500, 6500, 1.5),
    ExpenseCategory.shopping: (1200, 16000, 2.5),
    ExpenseCategory.other: (300, 3200, 2),
  };

  static List<Expense> generate({DateTime? now, int days = 120}) {
    final today = now ?? DateTime.now();
    final random = Random(7);
    final items = <Expense>[];
    var seq = 0;

    Expense make(ExpenseCategory category, DateTime date, double amount) {
      final pool = _notes[category]!;
      seq++;
      return Expense(
        id: 'demo-$seq',
        amount: (amount / 50).round() * 50,
        category: category,
        date: date,
        note: pool[random.nextInt(pool.length)],
        createdAt: date.add(Duration(minutes: 8 * 60 + seq % 600)),
      );
    }

    for (final entry in _profile.entries) {
      final (min, max, perMonth) = entry.value;
      final count = (perMonth * days / 30).round();
      for (var i = 0; i < count; i++) {
        final daysAgo = random.nextInt(days);
        final date = DateTime(
          today.year,
          today.month,
          today.day - daysAgo,
        );
        // Skew towards the low end so a few large spends stand out.
        final r = random.nextDouble();
        final skewed = min + (max - min) * r * r;
        items.add(make(entry.key, date, skewed));
      }
    }

    // Rent lands on the 1st of every month covered by the window.
    var monthCursor = DateTime(today.year, today.month, 1);
    final earliest = DateTime(today.year, today.month, today.day - days);
    while (!monthCursor.isBefore(earliest)) {
      items.add(make(ExpenseCategory.rent, monthCursor, 48000));
      monthCursor = DateTime(monthCursor.year, monthCursor.month - 1, 1);
    }

    return items;
  }
}
