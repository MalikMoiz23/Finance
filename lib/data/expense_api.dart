import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/expense.dart';
import '../models/expense_category.dart';

/// Remote store for one account's expenses. Row level security scopes every
/// call, so no method takes a user id.
///
/// Every write is an **upsert keyed on the row's own id**, which is generated on
/// the device. That makes each operation safe to retry: replaying a queued
/// change after a dropped connection can never create a duplicate.
abstract interface class ExpenseApi {
  Future<List<Expense>> fetchAll();

  Future<void> upsert(Expense expense);

  Future<void> delete(String id);

  /// Removes every expense belonging to the signed-in user.
  Future<void> deleteAll();
}

class SupabaseExpenseApi implements ExpenseApi {
  SupabaseExpenseApi(this._client);

  static const table = 'expenses';

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Not signed in — no user id for the expenses request.');
    }
    return id;
  }

  @override
  Future<List<Expense>> fetchAll() async {
    final rows = await _client
        .from(table)
        .select()
        .order('spent_on', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> upsert(Expense expense) async {
    await _client.from(table).upsert({
      'id': expense.id,
      'user_id': _userId,
      'amount': expense.amount,
      'category': expense.category.name,
      'spent_on': _dateOnly(expense.date),
      'item': expense.item.trim(),
      'note': expense.note.trim(),
      'created_at': expense.createdAt.toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  @override
  Future<void> delete(String id) async {
    await _client.from(table).delete().eq('id', id);
  }

  @override
  Future<void> deleteAll() async {
    await _client.from(table).delete().eq('user_id', _userId);
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// PostgREST may serialise `numeric` as a number or a string; accept both.
  static double _toDouble(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s) ?? 0,
    _ => 0,
  };

  static Expense _fromRow(Map<String, dynamic> row) {
    final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
    return Expense(
      id: row['id'] as String,
      amount: _toDouble(row['amount']),
      category: ExpenseCategory.fromName(row['category'] as String? ?? 'other'),
      date: DateTime.parse(row['spent_on'] as String),
      item: row['item'] as String? ?? '',
      note: row['note'] as String? ?? '',
      createdAt: createdAt?.toLocal(),
    );
  }
}
