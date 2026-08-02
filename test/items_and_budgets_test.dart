import 'package:finance/core/csv_export.dart';
import 'package:finance/models/budget.dart';
import 'package:finance/models/expense.dart';
import 'package:finance/models/expense_category.dart';
import 'package:finance/models/income.dart';
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

  group('pay and savings', () {
    MonthMoney money(double? income, double spent) =>
        MonthMoney(month: DateTime(2026, 7), income: income, spent: spent);

    test('saved is pay minus spend, and the rate is its share', () {
      final m = money(120000, 84000);
      expect(m.saved, 36000);
      expect(m.savingsRate, closeTo(0.3, 0.0001));
      expect(m.spentFraction, closeTo(0.7, 0.0001));
      expect(m.overspent, isFalse);
    });

    test('spending more than the pay reads as overspent', () {
      final m = money(50000, 62000);
      expect(m.saved, -12000);
      expect(m.savingsRate, closeTo(-0.24, 0.0001));
      expect(m.overspent, isTrue);
      // The meter cannot run past its own track.
      expect(m.spentFraction, 1);
    });

    test('without a pay figure there is nothing to divide by', () {
      final m = money(null, 5000);
      expect(m.hasIncome, isFalse);
      expect(m.saved, isNull);
      expect(m.savingsRate, isNull);
      expect(m.spentFraction, 0);
      expect(m.overspent, isFalse);
    });

    test('comparison reports both directions against last month', () {
      final c = MonthComparison(
        current: money(120000, 84000), // saved 36,000
        previous: MonthMoney(
          month: DateTime(2026, 6),
          income: 120000,
          spent: 90000, // saved 30,000
        ),
      );
      // Spent less than last month, saved more.
      expect(c.spentDelta, closeTo(-6.667, 0.01));
      expect(c.savedDelta, closeTo(20, 0.01));
      expect(c.savedDifference, 6000);
      expect(c.spentDifference, -6000);
      expect(c.incomeDelta, 0);
    });

    test('no baseline means no percentage rather than a wrong one', () {
      final c = MonthComparison(
        current: money(120000, 84000),
        previous: money(null, 0),
      );
      expect(c.savedDelta, isNull);
      expect(c.spentDelta, isNull, reason: 'last month spent nothing');
      expect(c.incomeDelta, isNull);
    });
  });

  group('csv export', () {
    test('has a header and one row per expense, newest first as given', () {
      final csv = expensesToCsv([
        e('Chicken', 950, ExpenseCategory.groceries),
        e('Petrol', 2500, ExpenseCategory.fuel, daysAgo: 1),
      ]);
      final lines = csv.split('\n');
      expect(lines.first, 'Date,Item,Category,Amount,Note');
      expect(lines[1], '2026-07-30,Chicken,Groceries,950.00,');
      expect(lines[2], '2026-07-29,Petrol,Fuel & Transport,2500.00,');
      expect(lines.length, 3);
    });

    test('amounts stay unformatted so a spreadsheet reads them as numbers', () {
      final csv = expensesToCsv([e('Milk', 249.5, ExpenseCategory.groceries)]);
      expect(csv, contains(',249.50,'));
      expect(csv, isNot(contains('Rs')));
    });

    test('a comma or quote in a note cannot break the row', () {
      final expense = Expense(
        id: 'x',
        amount: 100,
        category: ExpenseCategory.other,
        date: DateTime(2026, 7, 30),
        item: 'Gift',
        note: 'for Ali, said "thanks"',
      );
      final row = expensesToCsv([expense]).split('\n')[1];
      expect(row, endsWith('"for Ali, said ""thanks"""'));
      // Five fields: the quoted note keeps its comma out of the split.
      expect(row.split(',').length, greaterThan(5));
      expect(row.startsWith('2026-07-30,Gift,Other,100.00,"'), isTrue);
    });

    test('an empty list still produces a usable header', () {
      expect(expensesToCsv(const []), 'Date,Item,Category,Amount,Note');
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
