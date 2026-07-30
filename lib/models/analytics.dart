import 'dart:math' as math;

import '../core/formatters.dart';
import 'expense.dart';
import 'expense_category.dart';
import 'period.dart';

/// One column of the trend chart.
class TrendBucket {
  const TrendBucket({
    required this.shortLabel,
    required this.fullLabel,
    required this.total,
    required this.isCurrent,
  });

  /// Axis tick — one or two characters so 12 columns still fit a phone.
  final String shortLabel;

  /// Shown in the tooltip / direct label.
  final String fullLabel;
  final double total;

  /// True for the bucket that contains today (emphasised by default).
  final bool isCurrent;
}

/// One row of the "where it went" ranking.
class CategorySlice {
  const CategorySlice({
    required this.category,
    required this.total,
    required this.share,
    required this.count,
    required this.previousTotal,
  });

  final ExpenseCategory category;
  final double total;

  /// 0..1 of the period total.
  final double share;
  final int count;
  final double previousTotal;

  double? get deltaPercent =>
      previousTotal <= 0 ? null : (total - previousTotal) / previousTotal * 100;
}

/// Everything the dashboard shows for one period, computed in one pass.
class PeriodSummary {
  const PeriodSummary({
    required this.period,
    required this.range,
    required this.total,
    required this.previousTotal,
    required this.count,
    required this.dailyAverage,
    required this.slices,
    required this.buckets,
    required this.expenses,
    required this.weekdayTotals,
  });

  final Period period;
  final DateRange range;
  final double total;
  final double previousTotal;
  final int count;

  /// Total / days elapsed (not days in period) when the period is still running.
  final double dailyAverage;

  /// Categories present in the period, largest first.
  final List<CategorySlice> slices;
  final List<TrendBucket> buckets;

  /// Expenses inside the range, newest first.
  final List<Expense> expenses;

  /// Mon..Sun totals inside the range.
  final List<double> weekdayTotals;

  bool get isEmpty => count == 0;

  CategorySlice? get topSlice => slices.isEmpty ? null : slices.first;

  /// Signed % change against the previous period, or null when there is no
  /// baseline to compare with.
  double? get deltaPercent =>
      previousTotal <= 0 ? null : (total - previousTotal) / previousTotal * 100;

  double get largestBucketTotal =>
      buckets.fold<double>(0, (m, b) => math.max(m, b.total));

  List<Expense> get biggest {
    final sorted = [...expenses]..sort((a, b) => b.amount.compareTo(a.amount));
    return sorted.take(5).toList();
  }
}

/// Pure aggregation — no Flutter, no I/O, so it is unit-testable.
abstract final class Analytics {
  static PeriodSummary summarize({
    required List<Expense> all,
    required Period period,
    required DateTime anchor,
    required DateTime now,
  }) {
    final range = Periods.rangeOf(period, anchor);
    final previousRange = Periods.rangeOf(
      period,
      Periods.shift(period, anchor, -1),
    );

    final inRange = all.where((e) => range.contains(e.date)).toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });

    final total = inRange.fold<double>(0, (s, e) => s + e.amount);
    final previousTotal = all
        .where((e) => previousRange.contains(e.date))
        .fold<double>(0, (s, e) => s + e.amount);

    // Per-category totals, plus the same categories in the previous period so
    // each row can carry its own delta.
    final totals = <ExpenseCategory, double>{};
    final counts = <ExpenseCategory, int>{};
    for (final e in inRange) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
      counts[e.category] = (counts[e.category] ?? 0) + 1;
    }
    final previousTotals = <ExpenseCategory, double>{};
    for (final e in all.where((e) => previousRange.contains(e.date))) {
      previousTotals[e.category] = (previousTotals[e.category] ?? 0) + e.amount;
    }

    final slices =
        totals.entries
            .map(
              (entry) => CategorySlice(
                category: entry.key,
                total: entry.value,
                share: total <= 0 ? 0 : entry.value / total,
                count: counts[entry.key] ?? 0,
                previousTotal: previousTotals[entry.key] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));

    final weekdayTotals = List<double>.filled(7, 0);
    for (final e in inRange) {
      weekdayTotals[e.date.weekday - 1] += e.amount;
    }

    final elapsedDays = _elapsedDays(range, now);
    return PeriodSummary(
      period: period,
      range: range,
      total: total,
      previousTotal: previousTotal,
      count: inRange.length,
      dailyAverage: elapsedDays <= 0 ? 0 : total / elapsedDays,
      slices: slices,
      buckets: _buckets(period, range, inRange, now),
      expenses: inRange,
      weekdayTotals: weekdayTotals,
    );
  }

  /// Days the period has actually covered — a month that is 10 days old
  /// averages over 10 days, not 31, otherwise every running period looks cheap.
  static int _elapsedDays(DateRange range, DateTime now) {
    final today = dayOnly(now);
    if (today.isBefore(range.start)) return 0;
    if (!today.isBefore(range.endExclusive)) return range.dayCount;
    return today.difference(range.start).inDays + 1;
  }

  static List<TrendBucket> _buckets(
    Period period,
    DateRange range,
    List<Expense> inRange,
    DateTime now,
  ) {
    final today = dayOnly(now);
    switch (period) {
      case Period.week:
        return List.generate(7, (i) {
          final day = DateTime(
            range.start.year,
            range.start.month,
            range.start.day + i,
          );
          final total = inRange
              .where((e) => e.date == day)
              .fold<double>(0, (s, e) => s + e.amount);
          return TrendBucket(
            shortLabel: Dates.weekdayShort(day).substring(0, 1),
            fullLabel: Dates.weekdayDayMonth(day),
            total: total,
            isCurrent: day == today,
          );
        });

      case Period.month:
        // Fixed 7-day chunks from the 1st: 1–7, 8–14, ... The last chunk keeps
        // whatever the month has left, so the labels are never ambiguous.
        final daysInMonth = range.dayCount;
        final chunks = (daysInMonth / 7).ceil();
        return List.generate(chunks, (i) {
          final firstDay = 1 + i * 7;
          final lastDay = math.min(firstDay + 6, daysInMonth);
          final from = DateTime(range.start.year, range.start.month, firstDay);
          final toExclusive = DateTime(
            range.start.year,
            range.start.month,
            lastDay + 1,
          );
          final total = inRange
              .where(
                (e) => !e.date.isBefore(from) && e.date.isBefore(toExclusive),
              )
              .fold<double>(0, (s, e) => s + e.amount);
          return TrendBucket(
            shortLabel: '$firstDay',
            fullLabel: '$firstDay–$lastDay ${Dates.monthShort(range.start)}',
            total: total,
            isCurrent: !today.isBefore(from) && today.isBefore(toExclusive),
          );
        });

      case Period.year:
        return List.generate(12, (i) {
          final month = DateTime(range.start.year, i + 1, 1);
          final nextMonth = DateTime(range.start.year, i + 2, 1);
          final total = inRange
              .where(
                (e) => !e.date.isBefore(month) && e.date.isBefore(nextMonth),
              )
              .fold<double>(0, (s, e) => s + e.amount);
          return TrendBucket(
            shortLabel: Dates.monthShort(month).substring(0, 1),
            fullLabel: '${Dates.monthShort(month)} ${range.start.year}',
            total: total,
            isCurrent: today.year == month.year && today.month == month.month,
          );
        });
    }
  }

  /// Rounds a maximum up to a clean axis top (1k, 2.5k, 5k, 10k ...). Every
  /// candidate halves cleanly, so the mid gridline is also a round number.
  static double niceCeiling(double raw) {
    if (raw <= 0) return 1000;
    final magnitude = math.pow(
      10,
      (math.log(raw) / math.ln10).floor(),
    ).toDouble();
    for (final step in const [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 10.0]) {
      final candidate = magnitude * step;
      if (candidate >= raw) return candidate;
    }
    return magnitude * 10;
  }
}
