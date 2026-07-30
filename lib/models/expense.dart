import '../core/formatters.dart';
import 'expense_category.dart';

/// A single spend. Immutable; the store replaces entries rather than mutating.
class Expense {
  Expense({
    required this.id,
    required this.amount,
    required this.category,
    required DateTime date,
    this.item = '',
    this.note = '',
    DateTime? createdAt,
  }) : date = dayOnly(date),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final double amount;
  final ExpenseCategory category;

  /// What was bought — "Chicken", "Petrol", "Electricity bill". This is what the
  /// autocomplete learns from, and what the item reports group by.
  final String item;

  /// Day the money was spent, normalised to midnight.
  final DateTime date;

  /// Anything extra ("weekend stock, Al-Fatah"). May be empty.
  final String note;

  /// Entry time — only used to keep same-day ordering stable.
  final DateTime createdAt;

  /// Best available name for a row: the item, else the note, else the category.
  String get title {
    if (item.trim().isNotEmpty) return item.trim();
    if (note.trim().isNotEmpty) return note.trim();
    return category.label;
  }

  /// Line under the title: whichever of category/note is not already the title.
  String subtitle({bool includeCategory = true}) {
    final parts = <String>[
      if (includeCategory) category.label,
      if (item.trim().isNotEmpty && note.trim().isNotEmpty) note.trim(),
    ];
    return parts.join(' · ');
  }

  Expense copyWith({
    double? amount,
    ExpenseCategory? category,
    DateTime? date,
    String? item,
    String? note,
  }) {
    return Expense(
      id: id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      item: item ?? this.item,
      note: note ?? this.note,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'category': category.name,
    'date': date.toIso8601String(),
    'item': item,
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
      category: ExpenseCategory.fromName(
        json['category'] as String? ?? 'other',
      ),
      date: date,
      item: json['item'] as String? ?? '',
      note: json['note'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? date,
    );
  }
}
