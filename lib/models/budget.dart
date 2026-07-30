import 'dart:math' as math;

import 'expense_category.dart';

/// A monthly spending limit for one category.
class Budget {
  const Budget({required this.category, required this.monthlyLimit, this.id});

  final String? id;
  final ExpenseCategory category;
  final double monthlyLimit;

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category.name,
    'monthly_limit': monthlyLimit,
  };

  static Budget? fromJson(Map<String, dynamic> json) {
    final limit = switch (json['monthly_limit']) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };
    if (limit == null || limit <= 0) return null;
    return Budget(
      id: json['id'] as String?,
      category: ExpenseCategory.fromName(
        json['category'] as String? ?? 'other',
      ),
      monthlyLimit: limit,
    );
  }
}

/// How a budget is doing. The band drives colour *and* wording, so the state
/// never rests on colour alone.
enum BudgetBand {
  onTrack('On track'),
  closeToLimit('Close to limit'),
  overBudget('Over budget');

  const BudgetBand(this.label);

  final String label;
}

class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.spent,
    required this.daysLeft,
  });

  final Budget budget;
  final double spent;

  /// Days remaining in the month, including today.
  final int daysLeft;

  ExpenseCategory get category => budget.category;
  double get limit => budget.monthlyLimit;
  double get remaining => limit - spent;

  /// 0..1 for the meter; the raw ratio can exceed 1 when over budget.
  double get ratio => limit <= 0 ? 0 : spent / limit;
  double get meterFraction => math.min(1, math.max(0, ratio));

  BudgetBand get band => switch (ratio) {
    >= 1 => BudgetBand.overBudget,
    >= 0.8 => BudgetBand.closeToLimit,
    _ => BudgetBand.onTrack,
  };

  /// What is safe to spend per remaining day to stay inside the limit.
  double get dailyAllowance =>
      daysLeft <= 0 || remaining <= 0 ? 0 : remaining / daysLeft;
}
