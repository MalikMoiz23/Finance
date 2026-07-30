import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/budget.dart';
import '../models/expense.dart';

/// On-device storage for two things only:
///
/// * the theme choice, and
/// * a **read cache** of the last expenses fetched for a user, so the dashboard
///   can paint instantly on launch and stay readable with no connection.
///
/// The cache is never the source of truth: writes always go to Supabase first.
class LocalPrefs {
  static const _themeKey = 'theme_mode_v1';
  static String _cacheKey(String userId) => 'cache_expenses_$userId';
  static String _budgetKey(String userId) => 'cache_budgets_$userId';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<ThemeMode> loadThemeMode() async {
    final name = (await _prefs).getString(_themeKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await (await _prefs).setString(_themeKey, mode.name);
  }

  Future<List<Expense>> readCache(String userId) async {
    final raw = (await _prefs).getString(_cacheKey(userId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Expense.fromJson)
          .whereType<Expense>()
          .toList();
    } on FormatException {
      await clearCache(userId);
      return const [];
    }
  }

  Future<void> writeCache(String userId, List<Expense> expenses) async {
    await (await _prefs).setString(
      _cacheKey(userId),
      jsonEncode(expenses.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearCache(String userId) async {
    await (await _prefs).remove(_cacheKey(userId));
    await (await _prefs).remove(_budgetKey(userId));
  }

  Future<List<Budget>> readBudgets(String userId) async {
    final raw = (await _prefs).getString(_budgetKey(userId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Budget.fromJson)
          .whereType<Budget>()
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> writeBudgets(String userId, List<Budget> budgets) async {
    await (await _prefs).setString(
      _budgetKey(userId),
      jsonEncode(budgets.map((b) => b.toJson()).toList()),
    );
  }
}
