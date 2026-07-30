import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/budget.dart';
import '../models/expense_category.dart';

/// Monthly limits for the signed-in account. Row level security scopes every
/// call, so no method takes a user id.
abstract interface class BudgetApi {
  Future<List<Budget>> fetchAll();

  /// Creates or replaces the limit for a category.
  Future<Budget> save(ExpenseCategory category, double monthlyLimit);

  Future<void> remove(ExpenseCategory category);
}

class SupabaseBudgetApi implements BudgetApi {
  SupabaseBudgetApi(this._client);

  static const table = 'budgets';

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Not signed in — no user id for the budgets request.');
    }
    return id;
  }

  @override
  Future<List<Budget>> fetchAll() async {
    final rows = await _client.from(table).select();
    return rows.map(Budget.fromJson).whereType<Budget>().toList();
  }

  @override
  Future<Budget> save(ExpenseCategory category, double monthlyLimit) async {
    final row = await _client
        .from(table)
        .upsert({
          'user_id': _userId,
          'category': category.name,
          'monthly_limit': monthlyLimit,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,category')
        .select()
        .single();
    final budget = Budget.fromJson(row);
    if (budget == null) {
      throw StateError('The server returned a budget row we could not read.');
    }
    return budget;
  }

  @override
  Future<void> remove(ExpenseCategory category) async {
    await _client
        .from(table)
        .delete()
        .eq('user_id', _userId)
        .eq('category', category.name);
  }
}
