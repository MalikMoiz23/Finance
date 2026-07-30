import '../core/formatters.dart';
import 'expense_category.dart';

/// A single spend. Immutable; the store replaces entries rather than mutating.
class Expense {
  Expense({
    required this.id,
    required this.amount,
    required this.category,
    required DateTime date,
    this.note = '',
    DateTime? createdAt,
  }) : date = dayOnly(date),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final double amount;
  final ExpenseCategory category;

  /// Day the money was spent, normalised to midnight.
  final DateTime date;

  /// Free text ("Imtiaz weekly run"). May be empty.
  final String note;

  /// Entry time — only used to keep same-day ordering stable.
  final DateTime createdAt;

  String get title => note.trim().isEmpty ? category.label : note.trim();

  Expense copyWith({
    double? amount,
    ExpenseCategory? category,
    DateTime? date,
    String? note,
  }) {
    return Expense(
      id: id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      note: note ?? this.note,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'category': category.name,
    'date': date.toIso8601String(),
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };

  static Expense? fromJson(Map<String, dynamic> json) {
    final amount = (json['amount'] as num?)?.toDouble();
    final date = DateTime.tryParse(json['date'] as String? ?? '');
    final id = json['id'] as String?;
    if (amount == null || date == null || id == null) return null;
    return Expense(
      id: id,
      amount: amount,
      category: ExpenseCategory.fromName(json['category'] as String? ?? 'other'),
      date: date,
      note: json['note'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? date,
    );
  }
}
