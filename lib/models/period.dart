import '../core/formatters.dart';

/// The three windows the whole dashboard is scoped by. One filter row drives
/// every chart, stat and list below it.
enum Period {
  week('Week', 'week'),
  month('Month', 'month'),
  year('Year', 'year');

  const Period(this.label, this.noun);

  final String label;
  final String noun;
}

/// Half-open day range: [start, endExclusive).
class DateRange {
  const DateRange(this.start, this.endExclusive);

  final DateTime start;
  final DateTime endExclusive;

  DateTime get lastDay =>
      DateTime(endExclusive.year, endExclusive.month, endExclusive.day - 1);

  bool contains(DateTime day) {
    final d = dayOnly(day);
    return !d.isBefore(start) && d.isBefore(endExclusive);
  }

  /// Whole days in the range, safe against clock shifts.
  int get dayCount =>
      (endExclusive.difference(start).inHours / 24).round();

  @override
  bool operator ==(Object other) =>
      other is DateRange &&
      other.start == start &&
      other.endExclusive == endExclusive;

  @override
  int get hashCode => Object.hash(start, endExclusive);
}

/// Range maths kept in one place so the aggregations and the labels can never
/// disagree about where a period starts.
abstract final class Periods {
  /// Snaps an arbitrary date to the canonical anchor of its period: Monday for
  /// a week, the 1st for a month, 1 January for a year. Anchors are always
  /// normalised before being stored, which keeps `+/- 1 period` stepping exact
  /// (stepping from the 31st would otherwise skip a month).
  static DateTime normalizeAnchor(Period period, DateTime date) {
    final d = dayOnly(date);
    return switch (period) {
      Period.week => DateTime(d.year, d.month, d.day - (d.weekday - 1)),
      Period.month => DateTime(d.year, d.month, 1),
      Period.year => DateTime(d.year, 1, 1),
    };
  }

  static DateRange rangeOf(Period period, DateTime anchor) {
    final a = normalizeAnchor(period, anchor);
    return switch (period) {
      Period.week => DateRange(a, DateTime(a.year, a.month, a.day + 7)),
      Period.month => DateRange(a, DateTime(a.year, a.month + 1, 1)),
      Period.year => DateRange(a, DateTime(a.year + 1, 1, 1)),
    };
  }

  /// Steps the anchor by [delta] whole periods.
  static DateTime shift(Period period, DateTime anchor, int delta) {
    final a = normalizeAnchor(period, anchor);
    return switch (period) {
      Period.week => DateTime(a.year, a.month, a.day + 7 * delta),
      Period.month => DateTime(a.year, a.month + delta, 1),
      Period.year => DateTime(a.year + delta, 1, 1),
    };
  }

  /// `12 – 18 Jul 2026` / `July 2026` / `2026`.
  static String rangeLabel(Period period, DateTime anchor) {
    final range = rangeOf(period, anchor);
    switch (period) {
      case Period.week:
        final from = range.start;
        final to = range.lastDay;
        if (from.month == to.month) {
          return '${from.day} – ${Dates.dayMonthYear(to)}';
        }
        if (from.year == to.year) {
          return '${Dates.dayMonth(from)} – ${Dates.dayMonthYear(to)}';
        }
        return '${Dates.dayMonthYear(from)} – ${Dates.dayMonthYear(to)}';
      case Period.month:
        return Dates.monthYear(range.start);
      case Period.year:
        return '${range.start.year}';
    }
  }

  /// `This month`, `Last month`, or null when it is further back.
  static String? relativeLabel(Period period, DateTime anchor, DateTime now) {
    final current = normalizeAnchor(period, now);
    final a = normalizeAnchor(period, anchor);
    if (a == current) return 'This ${period.noun}';
    if (a == shift(period, current, -1)) return 'Last ${period.noun}';
    return null;
  }
}
