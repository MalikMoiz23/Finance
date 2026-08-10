import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/income.dart';

/// Monthly pay for the signed-in account. Row level security scopes every call.
abstract interface class IncomeApi {
  Future<List<MonthlyIncome>> fetchAll();

  /// Sets (or replaces) the pay recorded for [month]. Safe to retry.
  Future<void> save(DateTime month, double amount);

  Future<void> remove(DateTime month);
}

class SupabaseIncomeApi implements IncomeApi {
  SupabaseIncomeApi(this._client);

  static const table = 'monthly_income';

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Not signed in — no user id for the income request.');
    }
    return id;
  }

  static String _firstOfMonth(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}-01';

  @override
  Future<List<MonthlyIncome>> fetchAll() async {
    final rows = await _client.from(table).select().order('month');
    return rows.map(MonthlyIncome.fromJson).whereType<MonthlyIncome>().toList();
  }

  @override
  Future<void> save(DateTime month, double amount) async {
    await _client.from(table).upsert({
      'user_id': _userId,
      'month': _firstOfMonth(month),
      'amount': amount,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,month');
  }

  @override
  Future<void> remove(DateTime month) async {
    await _client
        .from(table)
        .delete()
        .eq('user_id', _userId)
        .eq('month', _firstOfMonth(month));
  }
}
