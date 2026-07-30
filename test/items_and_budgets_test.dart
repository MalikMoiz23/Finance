import 'package:finance/models/budget.dart';
import 'package:finance/models/expense.dart';
import 'package:finance/models/expense_category.dart';
import 'package:finance/models/item_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

Expense e(
  String item,
  double amount,
  ExpenseCategory category, {
  int daysAgo = 0,
}) {
  final now = DateTime(2026, 7, 30);
  return Expense(
    id: '$item-$daysAgo-$amount',
    amount: amount,
    category: category,
    date: DateTime(now.year, now.month, now.day - daysAgo),
    item: item,
    createdAt: DateTime(now.year, now.month, now.day - daysAgo, 12),
  );
}

void main() {
  group('item suggestions', () {
    final history = [
      e('Chicken', 800, ExpenseCategory.groceries, daysAgo: 6),
      e('Chicken', 950, ExpenseCategory.groceries, daysAgo: 1),
      e('Chai', 120, ExpenseCategory.dining, daysAgo: 2),
      e('Petrol', 2500, ExpenseCategory.fuel, daysAgo: 3),
    ];

    test('typing "chick" offers the account\'s own Chicken first', () {
      final results = ItemCatalog.suggest(query: 'chick', history: history);
      expect(results.first.name, 'Chicken');
      expect(results.first.category, ExpenseCategory.groceries);
      expect(results.first.uses, 2);
      // The newest price is the one offered, not the first ever paid.
      expect(results.first.typicalAmount, 950);
    });

    test('a substring match still matches, after prefix matches', () {
      final results = ItemCatalog.suggest(query: 'ai', history: history);
      final names = results.map((r) => r.name).toList();
      expect(names, contains('Chai'));
    });

    test('an empty account still gets catalogue completions', () {
      final results = ItemCatalog.suggest(query: 'petr', history: const []);
      expect(results.map((r) => r.name), contains('Petrol'));
      expect(results.first.category, ExpenseCategory.fuel);
      expect(results.first.typicalAmount, isNull, reason: 'no price history');
      expect(results.first.fromHistory, isFalse);
    });

    test('history is not duplicated by the catalogue', () {
      final results = ItemCatalog.suggest(query: 'chicken', history: history);
      final chickens = results.where((r) => r.name.toLowerCase() == 'chicken');
      expect(chickens.length, 1);
      expect(chickens.first.fromHistory, isTrue);
    });

    test('recent items are newest first', () {
      final recent = ItemCatalog.recent(history);
      expect(recent.map((r) => r.name).take(3), ['Chicken', 'Chai', 'Petrol']);
    });

    test('top items rank by total spend and count repeats', () {
      final top = ItemCatalog.topItems(history);
      // Petrol 2,500 outranks Chicken's two purchases totalling 1,750.
      expect(top.first.name, 'Petrol');
      expect(top.first.total, 2500);
      expect(top[1].name, 'Chicken');
      expect(top[1].total, 1750);
      expect(top[1].count, 2);
      expect(top.last.name, 'Chai');
    });

    test('expenses with no item name are ignored', () {
      final withBlank = [
        ...history,
        Expense(
          id: 'blank',
          amount: 500,
          category: ExpenseCategory.other,
          date: DateTime(2026, 7, 30),
        ),
      ];
      expect(ItemCatalog.topItems(withBlank).length, 3);
    });
  });

  group('budget status', () {
    BudgetStatus status(
      double spent, {
      double limit = 10000,
      int daysLeft = 10,
    }) {
      return BudgetStatus(
        budget: Budget(
          category: ExpenseCategory.groceries,
          monthlyLimit: limit,
        ),
        spent: spent,
        daysLeft: daysLeft,
      );
    }

    test('bands switch at 80% and 100%', () {
      expect(status(5000).band, BudgetBand.onTrack);
      expect(status(7999).band, BudgetBand.onTrack);
      expect(status(8000).band, BudgetBand.closeToLimit);
      expect(status(9999).band, BudgetBand.closeToLimit);
      expect(status(10000).band, BudgetBand.overBudget);
      expect(status(14000).band, BudgetBand.overBudget);
    });

    test('every band has wording, so colour never carries it alone', () {
      for (final band in BudgetBand.values) {
        expect(band.label, isNotEmpty);
      }
    });

    test('the meter never overflows even when spending does', () {
      expect(status(14000).ratio, closeTo(1.4, 0.001));
      expect(status(14000).meterFraction, 1);
      expect(status(0).meterFraction, 0);
    });

    test('remaining goes negative and the daily allowance stops at zero', () {
      expect(status(4000).remaining, 6000);
      expect(status(4000).dailyAllowance, 600);
      expect(status(12000).remaining, -2000);
      expect(status(12000).dailyAllowance, 0);
    });

    test('a finished month does not divide by zero', () {
      expect(status(4000, daysLeft: 0).dailyAllowance, 0);
    });
  });
}
