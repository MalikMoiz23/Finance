import 'package:finance/core/formatters.dart';
import 'package:finance/models/analytics.dart';
import 'package:finance/models/expense.dart';
import 'package:finance/models/expense_category.dart';
import 'package:finance/models/period.dart';
import 'package:flutter_test/flutter_test.dart';

Expense e(String id, double amount, DateTime date, ExpenseCategory category) =>
    Expense(id: id, amount: amount, category: category, date: date);

void main() {
  group('Periods', () {
    test('anchors snap to the start of the period', () {
      final wednesday = DateTime(2026, 7, 29); // a Wednesday
      expect(
        Periods.normalizeAnchor(Period.week, wednesday),
        DateTime(2026, 7, 27), // Monday
      );
      expect(
        Periods.normalizeAnchor(Period.month, wednesday),
        DateTime(2026, 7, 1),
      );
      expect(
        Periods.normalizeAnchor(Period.year, wednesday),
        DateTime(2026, 1, 1),
      );
    });

    test('stepping a month never skips one', () {
      // Naive date maths on the 31st would land in the following month.
      var anchor = DateTime(2026, 3, 31);
      anchor = Periods.shift(Period.month, anchor, 1);
      expect(anchor, DateTime(2026, 4, 1));
      anchor = Periods.shift(Period.month, anchor, 1);
      expect(anchor, DateTime(2026, 5, 1));
    });

    test('ranges are half-open and sized correctly', () {
      final month = Periods.rangeOf(Period.month, DateTime(2026, 2, 10));
      expect(month.start, DateTime(2026, 2, 1));
      expect(month.endExclusive, DateTime(2026, 3, 1));
      expect(month.dayCount, 28);
      expect(month.contains(DateTime(2026, 2, 28)), isTrue);
      expect(month.contains(DateTime(2026, 3, 1)), isFalse);

      expect(Periods.rangeOf(Period.week, DateTime(2026, 7, 29)).dayCount, 7);
      expect(Periods.rangeOf(Period.year, DateTime(2026, 7, 29)).dayCount, 365);
    });
  });

  group('Analytics.summarize', () {
    final now = DateTime(2026, 7, 15, 10);
    final expenses = [
      e('1', 1000, DateTime(2026, 7, 2), ExpenseCategory.groceries),
      e('2', 3000, DateTime(2026, 7, 10), ExpenseCategory.fuel),
      e('3', 500, DateTime(2026, 7, 10), ExpenseCategory.groceries),
      e('4', 9000, DateTime(2026, 6, 20), ExpenseCategory.rent), // last month
      e('5', 250, DateTime(2026, 8, 1), ExpenseCategory.dining), // next month
    ];

    final summary = Analytics.summarize(
      all: expenses,
      period: Period.month,
      anchor: DateTime(2026, 7, 1),
      now: now,
    );

    test('totals only the selected period', () {
      expect(summary.total, 4500);
      expect(summary.count, 3);
      expect(summary.previousTotal, 9000);
    });

    test('delta compares against the previous period', () {
      expect(summary.deltaPercent, closeTo(-50, 0.001));
    });

    test('daily average uses elapsed days, not the whole month', () {
      expect(summary.dailyAverage, closeTo(4500 / 15, 0.001));
    });

    test('categories rank largest first with shares of the total', () {
      expect(summary.slices.first.category, ExpenseCategory.fuel);
      expect(summary.slices.first.share, closeTo(3000 / 4500, 0.001));
      expect(summary.slices[1].category, ExpenseCategory.groceries);
      expect(summary.slices[1].total, 1500);
      expect(summary.slices[1].count, 2);
    });

    test('a month buckets into 7-day chunks that cover every day', () {
      expect(summary.buckets.length, 5); // 1-7, 8-14, 15-21, 22-28, 29-31
      expect(summary.buckets[0].total, 1000);
      expect(summary.buckets[1].total, 3500);
      expect(summary.buckets[2].isCurrent, isTrue); // 15 July
      final bucketed = summary.buckets.fold<double>(0, (s, b) => s + b.total);
      expect(bucketed, summary.total);
    });

    test('weekday totals cover the range', () {
      expect(summary.weekdayTotals.length, 7);
      expect(
        summary.weekdayTotals.fold<double>(0, (s, v) => s + v),
        summary.total,
      );
    });

    test('an empty period reports zero rather than throwing', () {
      final empty = Analytics.summarize(
        all: const [],
        period: Period.week,
        anchor: DateTime(2026, 7, 27),
        now: now,
      );
      expect(empty.isEmpty, isTrue);
      expect(empty.total, 0);
      expect(empty.dailyAverage, 0);
      expect(empty.deltaPercent, isNull);
      expect(empty.buckets.length, 7);
    });
  });

  group('formatting', () {
    test('money uses PKR with no decimals', () {
      expect(Money.format(1250.4), 'Rs 1,250');
      expect(Money.format(0), 'Rs 0');
    });

    test('axis ticks stay exact', () {
      expect(Money.axisTick(0), '0');
      expect(Money.axisTick(5000), '5k');
      expect(Money.axisTick(1250), '1,250');
      expect(Money.axisTick(200000), '2L');
    });

    test('nice ceilings halve cleanly', () {
      expect(Analytics.niceCeiling(0), 1000);
      expect(Analytics.niceCeiling(4200), 5000);
      expect(Analytics.niceCeiling(12000), 15000);
      expect(Analytics.niceCeiling(26000), 30000);
    });
  });
}
