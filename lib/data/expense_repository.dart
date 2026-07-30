import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense.dart';

/// Local-only persistence: the expense list is stored as one JSON string in
/// shared preferences. No database, but data survives a restart.
class ExpenseRepository {
  static const _expensesKey = 'expenses_v1';
  static const _seededKey = 'demo_seeded_v1';
  static const _themeKey = 'theme_mode_v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<Expense>> loadExpenses() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_expensesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Expense.fromJson)
          .whereType<Expense>()
          .toList();
    } on FormatException {
      // Corrupt payload: start clean rather than crash on launch.
      await prefs.remove(_expensesKey);
      return [];
    }
  }

  Future<void> saveExpenses(List<Expense> expenses) async {
    final prefs = await _prefs;
    await prefs.setString(
      _expensesKey,
      jsonEncode(expenses.map((e) => e.toJson()).toList()),
    );
  }

  Future<bool> hasSeededDemoData() async => (await _prefs).getBool(_seededKey) ?? false;

  Future<void> markDemoDataSeeded() async {
    await (await _prefs).setBool(_seededKey, true);
  }

  Future<ThemeMode> loadThemeMode() async {
    final name = (await _prefs).getString(_themeKey);
    return ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await (await _prefs).setString(_themeKey, mode.name);
  }
}
