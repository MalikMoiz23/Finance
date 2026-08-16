import 'package:intl/intl.dart';

/// Grouped, with a fraction only when the value has one: `5,000`, `18.5`.
final NumberFormat _upToTwo = NumberFormat('#,##0.##', 'en_US');

/// Grouped, always two decimals: `18.50`.
final NumberFormat _exactlyTwo = NumberFormat('#,##0.00', 'en_US');

/// Currency is PKR, displayed without decimals (Rs 1,250).
abstract final class Money {
  static final NumberFormat _grouped = NumberFormat('#,##0', 'en_US');
  static const symbol = 'Rs';

  /// `Rs 12,480`
  static String format(num value) =>
      '$symbol ${_grouped.format(value.round())}';

  /// `12,480` — for places where the symbol is already on screen.
  static String plain(num value) => _grouped.format(value.round());

  /// `Rs 12.5k` — stat tiles and axis ticks, where width is tight.
  static String compact(num value, {bool withSymbol = true}) {
    final prefix = withSymbol ? '$symbol ' : '';
    final abs = value.abs();
    if (abs >= 10000000) {
      return '$prefix${(value / 10000000).toStringAsFixed(1)}cr';
    }
    if (abs >= 100000) return '$prefix${(value / 100000).toStringAsFixed(1)}L';
    if (abs >= 1000) {
      final k = value / 1000;
      final digits = abs >= 10000 ? 0 : 1;
      return '$prefix${k.toStringAsFixed(digits)}k';
    }
    return '$prefix${_grouped.format(value.round())}';
  }

  /// `Rs 18.50` — a per-unit rate keeps its paisa. Rounding Rs 18.50 to Rs 19
  /// on a five-thousand-brick order misstates the total by Rs 2,500, so rates
  /// are the one place the app shows decimals. A whole rate stays whole:
  /// `Rs 1,300`, not `Rs 1,300.00`.
  static String rate(num value) {
    final v = value.toDouble();
    if (v == v.roundToDouble()) return '$symbol ${_grouped.format(v)}';
    return '$symbol ${_exactlyTwo.format(v)}';
  }

  /// Axis ticks: no symbol, exact (never rounded — a tick that says 1.3k when
  /// the gridline is at 1,250 misstates the scale).
  static String axisTick(num value) {
    final v = value.toDouble();
    if (v == 0) return '0';
    if (v >= 100000 && v % 100000 == 0) {
      return '${(v / 100000).toStringAsFixed(0)}L';
    }
    if (v >= 1000 && v % 1000 == 0) return '${(v / 1000).toStringAsFixed(0)}k';
    return _grouped.format(v);
  }
}

/// Counts of things bought — bricks, bags, trips. Not money, so no symbol, and
/// a fraction only when there is one (`5,000`, but `2.5` trips).
abstract final class Quantities {
  static String format(num value) => _upToTwo.format(value);
}

abstract final class Dates {
  static final _dayMonth = DateFormat('d MMM');
  static final _dayMonthYear = DateFormat('d MMM yyyy');
  static final _weekdayDayMonth = DateFormat('EEE, d MMM');
  static final _monthYear = DateFormat('MMMM yyyy');
  static final _monthShort = DateFormat('MMM');
  static final _weekdayShort = DateFormat('EEE');
  static final _weekdayFull = DateFormat('EEEE');

  static String dayMonth(DateTime d) => _dayMonth.format(d);
  static String dayMonthYear(DateTime d) => _dayMonthYear.format(d);
  static String weekdayDayMonth(DateTime d) => _weekdayDayMonth.format(d);
  static String monthYear(DateTime d) => _monthYear.format(d);
  static String monthShort(DateTime d) => _monthShort.format(d);
  static String weekdayShort(DateTime d) => _weekdayShort.format(d);
  static String weekdayFull(DateTime d) => _weekdayFull.format(d);

  /// `Today`, `Yesterday`, or `Mon, 12 Jul`.
  static String relativeDay(DateTime day, {DateTime? now}) {
    final today = dayOnly(now ?? DateTime.now());
    final target = dayOnly(day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff == -1) return 'Tomorrow';
    if (target.year == today.year) return weekdayDayMonth(target);
    return dayMonthYear(target);
  }
}

/// Midnight of [d] — every expense is stored on a day boundary.
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
