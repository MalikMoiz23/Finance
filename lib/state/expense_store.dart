import 'package:flutter/foundation.dart';

import '../core/formatters.dart';
import '../data/demo_data.dart';
import '../data/expense_repository.dart';
import '../models/analytics.dart';
import '../models/expense.dart';
import '../models/period.dart';

/// Single source of truth for the expense list and the period the whole UI is
/// scoped by. Every screen reads its numbers from [summary], so the dashboard,
/// insights and list can never disagree.
class ExpenseStore extends ChangeNotifier {
  ExpenseStore(this._repository) {
    _anchor = Periods.normalizeAnchor(_period, DateTime.now());
    _summary = _compute();
  }

  final ExpenseRepository _repository;

  final List<Expense> _expenses = [];
  Period _period = Period.month;
  late DateTime _anchor;
  late PeriodSummary _summary;
  bool _loading = true;

  bool get isLoading => _loading;
  Period get period => _period;
  DateTime get anchor => _anchor;
  PeriodSummary get summary => _summary;
  int get totalEntryCount => _expenses.length;

  /// Newest first.
  List<Expense> get allExpenses => List.unmodifiable(_expenses);

  String get rangeLabel => Periods.rangeLabel(_period, _anchor);

  String? get relativeRangeLabel =>
      Periods.relativeLabel(_period, _anchor, DateTime.now());

  /// False once the anchor has reached the period containing today — there is
  /// nothing to show in the future.
  bool get canGoForward {
    final next = Periods.rangeOf(_period, Periods.shift(_period, _anchor, 1));
    return !next.start.isAfter(dayOnly(DateTime.now()));
  }

  Future<void> initialize() async {
    final stored = await _repository.loadExpenses();
    _expenses
      ..clear()
      ..addAll(stored);

    if (_expenses.isEmpty && !await _repository.hasSeededDemoData()) {
      _expenses.addAll(DemoData.generate());
      await _repository.markDemoDataSeeded();
      await _repository.saveExpenses(_expenses);
    }

    _sort();
    _loading = false;
    _refresh();
  }

  void setPeriod(Period period) {
    if (period == _period) return;
    // Switching granularity keeps the reader where they were: today if the
    // window they were on includes it, otherwise the window's first day.
    // (Re-anchoring on the raw anchor would drop Year -> Month onto January.)
    final now = DateTime.now();
    final current = Periods.rangeOf(_period, _anchor);
    final reference = current.contains(now) ? now : current.start;
    _period = period;
    _anchor = Periods.normalizeAnchor(period, reference);
    _refresh();
  }

  void stepPeriod(int delta) {
    if (delta > 0 && !canGoForward) return;
    _anchor = Periods.shift(_period, _anchor, delta);
    _refresh();
  }

  void jumpToToday() {
    _anchor = Periods.normalizeAnchor(_period, DateTime.now());
    _refresh();
  }

  /// Moves the window onto [date] — used after saving an expense dated outside
  /// the period on screen, so the entry is never saved out of sight.
  void focusOn(DateTime date) {
    final anchor = Periods.normalizeAnchor(_period, date);
    if (anchor == _anchor) return;
    _anchor = anchor;
    _refresh();
  }

  /// Adds a new expense, or replaces the one with the same id.
  Future<void> save(Expense expense) async {
    final index = _expenses.indexWhere((e) => e.id == expense.id);
    if (index == -1) {
      _expenses.add(expense);
    } else {
      _expenses[index] = expense;
    }
    _sort();
    _refresh();
    await _persist();
  }

  Future<void> delete(String id) async {
    _expenses.removeWhere((e) => e.id == id);
    _refresh();
    await _persist();
  }

  Future<void> clearAll() async {
    _expenses.clear();
    _refresh();
    await _persist();
  }

  /// Next unused id. Microseconds keep it unique per entry.
  String newId() => 'e${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _persist() => _repository.saveExpenses(_expenses);

  void _sort() {
    _expenses.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
  }

  PeriodSummary _compute() => Analytics.summarize(
    all: _expenses,
    period: _period,
    anchor: _anchor,
    now: DateTime.now(),
  );

  void _refresh() {
    _summary = _compute();
    notifyListeners();
  }
}
