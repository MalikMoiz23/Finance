import 'package:flutter/foundation.dart';

import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../data/budget_api.dart';
import '../data/expense_api.dart';
import '../data/local_prefs.dart';
import '../models/analytics.dart';
import '../models/app_user.dart';
import '../models/budget.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/item_catalog.dart';
import '../models/period.dart';

/// Single source of truth for the signed-in account's expenses, budgets, and the
/// period the whole UI is scoped by.
///
/// Reads: the on-device cache paints first, then Supabase overwrites it. If the
/// fetch fails, the cached list stays on screen and [syncError] is set, so the
/// app is readable offline even though writes need a connection.
///
/// Writes: straight to Supabase. Every mutating method throws on failure so the
/// calling screen can show the message and keep the user's input.
class ExpenseStore extends ChangeNotifier {
  ExpenseStore({
    required ExpenseApi api,
    required BudgetApi budgetApi,
    required LocalPrefs prefs,
  }) : _api = api,
       _budgetApi = budgetApi,
       _prefs = prefs {
    _anchor = Periods.normalizeAnchor(_period, DateTime.now());
    _summary = _compute();
  }

  final ExpenseApi _api;
  final BudgetApi _budgetApi;
  final LocalPrefs _prefs;

  final List<Expense> _expenses = [];
  final List<Budget> _budgets = [];
  Period _period = Period.month;
  late DateTime _anchor;
  late PeriodSummary _summary;

  String? _userId;
  bool _loading = false;
  bool _loadedFromServer = false;
  String? _syncError;
  bool _disposed = false;

  bool get isLoading => _loading;
  Period get period => _period;
  DateTime get anchor => _anchor;
  PeriodSummary get summary => _summary;
  int get totalEntryCount => _expenses.length;
  List<Expense> get allExpenses => List.unmodifiable(_expenses);
  List<Budget> get budgets => List.unmodifiable(_budgets);

  /// Why the last sync failed, or null when the data on screen is fresh.
  String? get syncError => _syncError;

  bool get isShowingCachedData => _syncError != null && !_loadedFromServer;

  String get rangeLabel => Periods.rangeLabel(_period, _anchor);

  String? get relativeRangeLabel =>
      Periods.relativeLabel(_period, _anchor, DateTime.now());

  bool get canGoForward {
    final next = Periods.rangeOf(_period, Periods.shift(_period, _anchor, 1));
    return !next.start.isAfter(dayOnly(DateTime.now()));
  }

  // ------------------------------------------------------------- budgets ---

  /// Budgets are monthly, so they always report against the current calendar
  /// month regardless of which period the dashboard is showing.
  DateRange get budgetMonth => Periods.rangeOf(Period.month, DateTime.now());

  String get budgetMonthLabel => Dates.monthYear(budgetMonth.start);

  /// Which month the calendar shows: the one containing today when the selected
  /// period includes it, otherwise the month the period starts in. (Anchoring
  /// straight on the anchor would show January whenever the period is a year.)
  DateTime get calendarMonth {
    final now = DateTime.now();
    final range = Periods.rangeOf(_period, _anchor);
    final reference = range.contains(now) ? now : range.start;
    return DateTime(reference.year, reference.month);
  }

  /// Total per day for [month], keyed by midnight — the calendar heatmap.
  Map<DateTime, double> dailyTotals(DateTime month) {
    final totals = <DateTime, double>{};
    for (final expense in _expenses) {
      if (expense.date.year == month.year &&
          expense.date.month == month.month) {
        totals[expense.date] = (totals[expense.date] ?? 0) + expense.amount;
      }
    }
    return totals;
  }

  List<Expense> expensesOn(DateTime day) {
    final target = dayOnly(day);
    return _expenses.where((e) => e.date == target).toList();
  }

  double spentThisMonth(ExpenseCategory category) => _expenses
      .where((e) => e.category == category && budgetMonth.contains(e.date))
      .fold<double>(0, (sum, e) => sum + e.amount);

  double get totalSpentThisMonth => _expenses
      .where((e) => budgetMonth.contains(e.date))
      .fold<double>(0, (sum, e) => sum + e.amount);

  int get daysLeftThisMonth {
    final today = dayOnly(DateTime.now());
    if (!budgetMonth.contains(today)) return 0;
    return budgetMonth.endExclusive.difference(today).inDays;
  }

  /// Worst first, so what needs attention is at the top.
  List<BudgetStatus> get budgetStatuses {
    final statuses = _budgets
        .map(
          (budget) => BudgetStatus(
            budget: budget,
            spent: spentThisMonth(budget.category),
            daysLeft: daysLeftThisMonth,
          ),
        )
        .toList();
    statuses.sort((a, b) => b.ratio.compareTo(a.ratio));
    return statuses;
  }

  Budget? budgetFor(ExpenseCategory category) =>
      _budgets.where((b) => b.category == category).firstOrNull;

  int get overBudgetCount =>
      budgetStatuses.where((s) => s.band == BudgetBand.overBudget).length;

  double get totalBudgeted =>
      _budgets.fold<double>(0, (sum, b) => sum + b.monthlyLimit);

  /// Spending inside categories that actually have a limit set.
  double get spentAgainstBudgets =>
      _budgets.fold<double>(0, (sum, b) => sum + spentThisMonth(b.category));

  Future<void> saveBudget(ExpenseCategory category, double monthlyLimit) async {
    final saved = await _budgetApi.save(category, monthlyLimit);
    final index = _budgets.indexWhere((b) => b.category == category);
    if (index == -1) {
      _budgets.add(saved);
    } else {
      _budgets[index] = saved;
    }
    _refresh();
    await _persistCache();
  }

  Future<void> removeBudget(ExpenseCategory category) async {
    await _budgetApi.remove(category);
    _budgets.removeWhere((b) => b.category == category);
    _refresh();
    await _persistCache();
  }

  // --------------------------------------------------------------- items ---

  /// Autocomplete for the item field: own history first, then the catalogue.
  List<ItemSuggestion> suggestItems(String query, {int limit = 6}) =>
      ItemCatalog.suggest(query: query, history: _expenses, limit: limit);

  /// One-tap "buy again" chips.
  List<ItemSuggestion> recentItems({int limit = 6}) =>
      ItemCatalog.recent(_expenses, limit: limit);

  // ---------------------------------------------------------- load / sync ---

  /// Points the store at an account, or clears it on sign-out.
  Future<void> bindUser(AppUser? user) async {
    if (user == null) {
      _userId = null;
      _expenses.clear();
      _budgets.clear();
      _loading = false;
      _loadedFromServer = false;
      _syncError = null;
      jumpToToday();
      return;
    }

    if (user.id == _userId) return;
    _userId = user.id;
    _expenses.clear();
    _budgets.clear();
    _loadedFromServer = false;
    _syncError = null;
    _anchor = Periods.normalizeAnchor(_period, DateTime.now());

    final cached = await _prefs.readCache(user.id);
    final cachedBudgets = await _prefs.readBudgets(user.id);
    if (_userId != user.id) return; // switched accounts mid-read
    if (cached.isNotEmpty) {
      _expenses.addAll(cached);
      _sort();
    }
    _budgets.addAll(cachedBudgets);
    _refresh();

    await refresh();
  }

  /// Re-fetches from Supabase. Keeps whatever is on screen if it fails.
  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;

    _loading = true;
    _refresh();
    try {
      final rows = await _api.fetchAll();
      if (_userId != userId) return;
      _expenses
        ..clear()
        ..addAll(rows);
      _sort();
      _loadedFromServer = true;
      _syncError = null;
    } catch (error) {
      if (_userId != userId) return;
      _syncError = describeError(error);
    }

    // Budgets are an optional layer: if that table is unreachable the expenses
    // above must still render, so this failure is kept out of syncError.
    try {
      final rows = await _budgetApi.fetchAll();
      if (_userId != userId) return;
      _budgets
        ..clear()
        ..addAll(rows);
    } catch (_) {
      // Keep whatever budgets the cache gave us.
    }

    if (_userId != userId) return;
    await _persistCache();
    _loading = false;
    _refresh();
  }

  // -------------------------------------------------------------- period ---

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

  // ------------------------------------------------------------- expenses ---

  Future<void> create({
    required double amount,
    required ExpenseCategory category,
    required DateTime date,
    required String item,
    required String note,
  }) async {
    final created = await _api.create(
      amount: amount,
      category: category,
      date: date,
      item: item,
      note: note,
    );
    _expenses.add(created);
    _sort();
    _syncError = null;
    _refresh();
    await _persistCache();
  }

  Future<void> update(Expense expense) async {
    final saved = await _api.update(expense);
    final index = _expenses.indexWhere((e) => e.id == saved.id);
    if (index == -1) {
      _expenses.add(saved);
    } else {
      _expenses[index] = saved;
    }
    _sort();
    _syncError = null;
    _refresh();
    await _persistCache();
  }

  Future<void> remove(String id) async {
    await _api.delete(id);
    _expenses.removeWhere((e) => e.id == id);
    _syncError = null;
    _refresh();
    await _persistCache();
  }

  /// The most recent entry, whatever period is on screen.
  Expense? get mostRecent => _expenses.firstOrNull;

  /// Logs the same thing again, dated today — the fastest possible entry for
  /// something bought repeatedly. Returns null when there is nothing to repeat.
  Future<Expense?> repeatMostRecent() async {
    final last = mostRecent;
    if (last == null) return null;
    await duplicate(last);
    return last;
  }

  /// Copies an existing expense onto today.
  Future<void> duplicate(Expense expense) => create(
    amount: expense.amount,
    category: expense.category,
    date: dayOnly(DateTime.now()),
    item: expense.item,
    note: expense.note,
  );

  /// Undo for a deleted expense: the row is gone, so this writes it back as a
  /// new row with the same values.
  Future<void> restore(Expense expense) => create(
    amount: expense.amount,
    category: expense.category,
    date: expense.date,
    item: expense.item,
    note: expense.note,
  );

  Future<void> clearAll() async {
    await _api.deleteAll();
    _expenses.clear();
    _syncError = null;
    _refresh();
    await _persistCache();
  }

  Future<void> _persistCache() async {
    final userId = _userId;
    if (userId == null) return;
    await _prefs.writeCache(userId, _expenses);
    await _prefs.writeBudgets(userId, _budgets);
  }

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
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
