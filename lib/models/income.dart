/// What was earned in one month.
class MonthlyIncome {
  const MonthlyIncome({required this.month, required this.amount, this.id});

  final String? id;

  /// Always the first of the month, at midnight.
  final DateTime month;

  final double amount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'month':
        '${month.year.toString().padLeft(4, '0')}-'
        '${month.month.toString().padLeft(2, '0')}-01',
    'amount': amount,
  };

  static MonthlyIncome? fromJson(Map<String, dynamic> json) {
    final amount = switch (json['amount']) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };
    final month = DateTime.tryParse(json['month'] as String? ?? '');
    if (amount == null || amount < 0 || month == null) return null;
    return MonthlyIncome(
      id: json['id'] as String?,
      month: DateTime(month.year, month.month),
      amount: amount,
    );
  }
}

/// Pay against spending for a single month, and what that leaves.
class MonthMoney {
  const MonthMoney({
    required this.month,
    required this.income,
    required this.spent,
    this.carriedForward = false,
  });

  final DateTime month;

  /// Null when no pay has ever been recorded on or before this month.
  final double? income;

  final double spent;

  /// True when the figure came from an earlier month rather than this one.
  final bool carriedForward;

  bool get hasIncome => income != null;

  /// Negative when more was spent than earned.
  double? get saved => income == null ? null : income! - spent;

  /// Share of pay kept, 0..1. Negative if overspent, null without pay.
  double? get savingsRate {
    final pay = income;
    if (pay == null || pay <= 0) return null;
    return (pay - spent) / pay;
  }

  /// Share of pay already spent, clamped for the meter.
  double get spentFraction {
    final pay = income;
    if (pay == null || pay <= 0) return 0;
    final ratio = spent / pay;
    return ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio);
  }

  bool get overspent => saved != null && saved! < 0;
}

/// This month set against the one before it.
class MonthComparison {
  const MonthComparison({required this.current, required this.previous});

  final MonthMoney current;
  final MonthMoney previous;

  /// Signed percentage change, or null when the baseline is zero/absent.
  static double? _delta(double? now, double? before) {
    if (now == null || before == null || before == 0) return null;
    return (now - before) / before.abs() * 100;
  }

  double? get spentDelta => _delta(current.spent, previous.spent);
  double? get savedDelta => _delta(current.saved, previous.saved);
  double? get incomeDelta => _delta(current.income, previous.income);

  /// Difference in rupees, positive when this month kept more.
  double? get savedDifference {
    final a = current.saved;
    final b = previous.saved;
    if (a == null || b == null) return null;
    return a - b;
  }

  double get spentDifference => current.spent - previous.spent;
}
