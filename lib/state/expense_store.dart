import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../data/budget_api.dart';
import '../data/expense_api.dart';
import '../data/income_api.dart';
import '../data/local_db.dart';
import '../models/analytics.dart';
import '../models/app_user.dart';
import '../models/budget.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/income.dart';
import '../models/item_catalog.dart';
import '../models/period.dart';

/// Where the local copy stands against the server.
enum SyncState {
  /// Everything on this device has reached Supabase.
  synced,

  /// Pushing or pulling right now.
  syncing,

  /// Changes are waiting because there is no usable connection.
  waiting,
}

/// Single source of truth for the signed-in account's expenses, budgets, pay and
/// the period the UI is scoped by.
///
/// **Offline first.** Every read comes from the device's own database, and every
/// write lands there first and is queued in an outbox — so the app is fully
/// usable with no connection and the UI never waits on the network. The queue is
/// drained automatically whenever connectivity returns.
///
/// Conflicts resolve to the most recent edit: a queued local change wins over
/// server data for the same row (its edit is newer), and for every other row the
/// server's copy replaces the local one on each pull.
class ExpenseStore extends ChangeNotifier {
  ExpenseStore({
    required ExpenseApi api,
    required BudgetApi budgetApi,
    required IncomeApi incomeApi,
    required LocalDb localDb,
    Stream<bool>? onlineChanges,
  }) : _api = api,
       _budgetApi = budgetApi,
       _incomeApi = incomeApi,
       _local = localDb {
    _anchor = Periods.normalizeAnchor(_period, DateTime.now());
    _summary = _compute();
    // A regained connection drains the outbox without the user doing anything.
    _connection = (onlineChanges ?? _defaultOnlineChanges()).listen((online) {
      final wasOffline = !_online;
      _online = online;
      if (online && wasOffline) {
        sync();
      } else {
        _refresh();
      }
    });
  }

  static Stream<bool> _defaultOnlineChanges() => Connectivity()
      .onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));

  final ExpenseApi _api;
  final BudgetApi _budgetApi;
  final IncomeApi _incomeApi;
  final LocalDb _local;
  static const _uuid = Uuid();

  late final StreamSubscription<bool> _connection;

  final List<Expense> _expenses = [];
  final List<Budget> _budgets = [];
  final List<MonthlyIncome> _incomes = [];
  Period _period = Period.month;
  late DateTime _anchor;
  late PeriodSummary _summary;

  String? _userId;
  bool _loading = false;
  bool _online = true;
  bool _syncing = false;

  int _pending = 0;
  String? _syncError;
  bool _disposed = false;

  bool get isLoading => _loading;
  Period get period => _period;
  DateTime get anchor => _anchor;
  PeriodSummary get summary => _summary;
  int get totalEntryCount => _expenses.length;
  List<Expense> get allExpenses => List.unmodifiable(_expenses);
  List<Budget> get budgets => List.unmodifiable(_budgets);
  List<MonthlyIncome> get incomes => List.unmodifiable(_incomes);

  /// How many changes are still waiting to reach Supabase.
  int get pendingCount => _pending;

  bool get isOnline => _online;

  SyncState get syncState {
    if (_syncing) return SyncState.syncing;
    if (_pending > 0) return SyncState.waiting;
    return SyncState.synced;
  }

  /// Why the last sync attempt failed, if it did. Never blocks the UI: the local
  /// data is authoritative until the queue drains.
  String? get syncError => _syncError;

  String get rangeLabel => Periods.rangeLabel(_period, _anchor);

  String? get relativeRangeLabel =>
      Periods.relativeLabel(_period, _anchor, DateTime.now());

  bool get canGoForward {
    final next = Periods.rangeOf(_period, Periods.shift(_period, _anchor, 1));
    return !next.start.isAfter(dayOnly(DateTime.now()));
  }

  // ------------------------------------------------------------- budgets ---

  DateRange get budgetMonth => Periods.rangeOf(Period.month, DateTime.now());

  String get budgetMonthLabel => Dates.monthYear(budgetMonth.start);

  DateTime get calendarMonth {
    final now = DateTime.now();
    final range = Periods.rangeOf(_period, _anchor);
    final reference = range.contains(now) ? now : range.start;
    return DateTime(reference.year, reference.month);
  }

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

  double get spentAgainstBudgets =>
      _budgets.fold<double>(0, (sum, b) => sum + spentThisMonth(b.category));

  // ----------------------------------------------------------- monthly pay ---

  static DateTime _monthOf(DateTime date) => DateTime(date.year, date.month);

  MonthlyIncome? incomeRowFor(DateTime month) {
    final key = _monthOf(month);
    return _incomes.where((i) => i.month == key).firstOrNull;
  }

  ({double amount, bool carriedForward})? effectiveIncome(DateTime month) {
    final key = _monthOf(month);
    final exact = incomeRowFor(key);
    if (exact != null) return (amount: exact.amount, carriedForward: false);

    MonthlyIncome? best;
    for (final income in _incomes) {
      if (income.month.isAfter(key)) continue;
      if (best == null || income.month.isAfter(best.month)) best = income;
    }
    if (best == null) return null;
    return (amount: best.amount, carriedForward: true);
  }

  double spentInMonth(DateTime month) {
    final key = _monthOf(month);
    return _expenses
        .where((e) => e.date.year == key.year && e.date.month == key.month)
        .fold<double>(0, (sum, e) => sum + e.amount);
  }

  MonthMoney monthMoney(DateTime month) {
    final key = _monthOf(month);
    final pay = effectiveIncome(key);
    return MonthMoney(
      month: key,
      income: pay?.amount,
      spent: spentInMonth(key),
      carriedForward: pay?.carriedForward ?? false,
    );
  }

  MonthComparison get thisMonthVsLast {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    return MonthComparison(
      current: monthMoney(current),
      previous: monthMoney(DateTime(current.year, current.month - 1)),
    );
  }

  bool get hasAnyIncome => _incomes.isNotEmpty;

  // --------------------------------------------------------------- items ---

  List<ItemSuggestion> suggestItems(String query, {int limit = 6}) =>
      ItemCatalog.suggest(query: query, history: _expenses, limit: limit);

  List<ItemSuggestion> recentItems({int limit = 6}) =>
      ItemCatalog.recent(_expenses, limit: limit);

  Expense? get mostRecent => _expenses.firstOrNull;

  // ---------------------------------------------------------- load / sync ---

  Future<void> bindUser(AppUser? user) async {
    if (user == null) {
      _userId = null;
      _expenses.clear();
      _budgets.clear();
      _incomes.clear();
      _loading = false;
      _pending = 0;
      _syncError = null;
      jumpToToday();
      return;
    }

    if (user.id == _userId) return;
    _userId = user.id;
    _expenses.clear();
    _budgets.clear();
    _incomes.clear();
    _syncError = null;
    _anchor = Periods.normalizeAnchor(_period, DateTime.now());

    await _local.open();
    await _loadFromLocal(user.id);
    await sync();
  }

  Future<void> _loadFromLocal(String userId) async {
    final expenses = await _local.readExpenses(userId);
    final budgets = await _local.readBudgets(userId);
    final incomes = await _local.readIncomes(userId);
    final pending = await _local.pendingCount(userId);
    if (_userId != userId) return;
    _expenses
      ..clear()
      ..addAll(expenses);
    _budgets
      ..clear()
      ..addAll(budgets);
    _incomes
      ..clear()
      ..addAll(incomes);
    _sort();
    _pending = pending;
    _refresh();
  }

  /// Pull-to-refresh and the automatic reconnect both land here.
  Future<void> refresh() => sync();

  /// Pushes everything queued, then pulls the server's copy.
  ///
  /// Safe to call at any time: if the network is unavailable it records why and
  /// leaves the queue intact for the next attempt.
  Future<void> sync({int pass = 0}) async {
    final userId = _userId;
    if (userId == null) return;
    // A pass already running will re-check the queue when it finishes, so a
    // concurrent request can simply be dropped.
    if (_syncing) return;

    _syncing = true;
    _loading = _expenses.isEmpty;
    _refresh();
    try {
      await _pushPending(userId);
      await _pullFromServer(userId);
      if (_userId != userId) return;
      _syncError = null;
      _online = true;
    } catch (error) {
      if (_userId != userId) return;
      _syncError = describeError(error);
      _online = false;
    } finally {
      if (_userId == userId) {
        _pending = await _local.pendingCount(userId);
        _syncing = false;
        _loading = false;
        _refresh();
      }
    }

    // A burst of writes can queue ops after this pass read the outbox, so the
    // condition is the queue itself rather than a flag — that cannot race. A
    // failed push sets _online false, and every successful push removes its op,
    // so this terminates; the pass cap is a backstop, not the mechanism.
    final again = _online && _pending > 0 && pass < 4;
    if (again && _userId == userId) await sync(pass: pass + 1);
  }

  /// Drains the outbox oldest-first. Stops at the first failure so ordering is
  /// preserved and nothing is dropped.
  Future<void> _pushPending(String userId) async {
    final ops = await _local.pendingOps(userId);
    for (final op in ops) {
      if (_userId != userId) return;
      switch ((op.entity, op.action)) {
        case (SyncEntity.expense, SyncAction.upsert):
          final expense = op.expense;
          if (expense != null) await _api.upsert(expense);
        case (SyncEntity.expense, SyncAction.delete):
          await _api.delete(op.key);
        case (SyncEntity.expense, SyncAction.deleteAll):
          await _api.deleteAll();
        case (SyncEntity.budget, SyncAction.upsert):
          final budget = op.budget;
          if (budget != null) {
            await _budgetApi.save(budget.category, budget.monthlyLimit);
          }
        case (SyncEntity.budget, SyncAction.delete):
          await _budgetApi.remove(op.category);
        case (SyncEntity.budget, SyncAction.deleteAll):
          await _budgetApi.removeAll();
        case (SyncEntity.income, SyncAction.upsert):
          final income = op.income;
          if (income != null) {
            await _incomeApi.save(income.month, income.amount);
          }
        case (SyncEntity.income, SyncAction.delete):
          await _incomeApi.remove(op.month);
        case (SyncEntity.income, SyncAction.deleteAll):
          break; // no such operation for pay
      }
      await _local.completeOp(userId, op.id);
      _pending = await _local.pendingCount(userId);
      _refresh();
    }
  }

  /// Replaces the local copy with the server's, except for rows that still have
  /// a queued change — those edits are newer and must survive the pull.
  Future<void> _pullFromServer(String userId) async {
    final remoteExpenses = await _api.fetchAll();
    final remoteBudgets = await _budgetApi.fetchAll();
    final remoteIncomes = await _incomeApi.fetchAll();
    if (_userId != userId) return;

    final ops = await _local.pendingOps(userId);
    Set<String> keys(SyncEntity entity) => ops
        .where((o) => o.entity == entity && o.key.isNotEmpty)
        .map((o) => o.key)
        .toSet();

    await _local.replaceExpenses(
      userId,
      remoteExpenses,
      keepKeys: keys(SyncEntity.expense),
    );
    await _local.replaceBudgets(
      userId,
      remoteBudgets,
      keepKeys: keys(SyncEntity.budget),
    );
    await _local.replaceIncomes(
      userId,
      remoteIncomes,
      keepKeys: keys(SyncEntity.income),
    );
    await _loadFromLocal(userId);
  }

  /// Best-effort push after a local write. Never throws: the change is already
  /// safe on the device.
  void _syncSoon() {
    if (_userId == null) return;
    Future.microtask(sync);
  }

  // -------------------------------------------------------------- period ---

  void setPeriod(Period period) {
    if (period == _period) return;
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

  void focusOn(DateTime date) {
    final anchor = Periods.normalizeAnchor(_period, date);
    if (anchor == _anchor) return;
    _anchor = anchor;
    _refresh();
  }

  // ------------------------------------------------------------- expenses ---

  /// Saves locally and queues the push. Returns as soon as the device has it,
  /// so this succeeds with no connection.
  Future<void> create({
    required double amount,
    required ExpenseCategory category,
    required DateTime date,
    required String item,
    required String note,
  }) async {
    // The id is generated here, not by the server, so an expense created offline
    // keeps its identity when it finally syncs.
    final expense = Expense(
      id: _uuid.v4(),
      amount: amount,
      category: category,
      date: date,
      item: item.trim(),
      note: note.trim(),
    );
    await update(expense);
  }

  Future<void> update(Expense expense) async {
    final userId = _requireUser();
    await _local.putExpense(userId, expense);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.expense,
        action: SyncAction.upsert,
        key: expense.id,
        payload: expense.toJson(),
      ),
    );
    final index = _expenses.indexWhere((e) => e.id == expense.id);
    if (index == -1) {
      _expenses.add(expense);
    } else {
      _expenses[index] = expense;
    }
    _sort();
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  Future<void> remove(String id) async {
    final userId = _requireUser();
    await _local.removeExpense(userId, id);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.expense,
        action: SyncAction.delete,
        key: id,
        payload: {'id': id},
      ),
    );
    _expenses.removeWhere((e) => e.id == id);
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  /// Undo for a deleted expense: written back as a new row.
  Future<void> restore(Expense expense) => create(
    amount: expense.amount,
    category: expense.category,
    date: expense.date,
    item: expense.item,
    note: expense.note,
  );

  /// Copies an existing expense onto today.
  Future<void> duplicate(Expense expense) => create(
    amount: expense.amount,
    category: expense.category,
    date: dayOnly(DateTime.now()),
    item: expense.item,
    note: expense.note,
  );

  Future<Expense?> repeatMostRecent() async {
    final last = mostRecent;
    if (last == null) return null;
    await duplicate(last);
    return last;
  }

  Future<void> clearAll() async {
    final userId = _requireUser();
    for (final expense in [..._expenses]) {
      await _local.removeExpense(userId, expense.id);
    }
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.expense,
        action: SyncAction.deleteAll,
        payload: const {},
      ),
    );
    _expenses.clear();
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  // -------------------------------------------------------------- budgets ---

  Future<void> saveBudget(ExpenseCategory category, double monthlyLimit) async {
    final userId = _requireUser();
    final budget = Budget(category: category, monthlyLimit: monthlyLimit);
    await _local.putBudget(userId, budget);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.budget,
        action: SyncAction.upsert,
        key: category.name,
        payload: budget.toJson(),
      ),
    );
    final index = _budgets.indexWhere((b) => b.category == category);
    if (index == -1) {
      _budgets.add(budget);
    } else {
      _budgets[index] = budget;
    }
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  Future<void> removeBudget(ExpenseCategory category) async {
    final userId = _requireUser();
    await _local.removeBudget(userId, category);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.budget,
        action: SyncAction.delete,
        key: category.name,
        payload: {'category': category.name},
      ),
    );
    _budgets.removeWhere((b) => b.category == category);
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  /// Clears every monthly limit. Expenses are untouched.
  Future<void> clearAllBudgets() async {
    final userId = _requireUser();
    for (final budget in [..._budgets]) {
      await _local.removeBudget(userId, budget.category);
    }
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.budget,
        action: SyncAction.deleteAll,
        payload: const {},
      ),
    );
    _budgets.clear();
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  // ------------------------------------------------------------ monthly pay ---

  Future<void> saveIncome(DateTime month, double amount) async {
    final userId = _requireUser();
    final income = MonthlyIncome(month: _monthOf(month), amount: amount);
    await _local.putIncome(userId, income);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.income,
        action: SyncAction.upsert,
        key: income.toJson()['month'] as String,
        payload: income.toJson(),
      ),
    );
    final index = _incomes.indexWhere((i) => i.month == income.month);
    if (index == -1) {
      _incomes.add(income);
    } else {
      _incomes[index] = income;
    }
    _incomes.sort((a, b) => a.month.compareTo(b.month));
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  Future<void> removeIncome(DateTime month) async {
    final userId = _requireUser();
    final key = _monthOf(month);
    await _local.removeIncome(userId, key);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.income,
        action: SyncAction.delete,
        key: MonthlyIncome(month: key, amount: 0).toJson()['month'] as String,
        payload: {'month': key.toIso8601String(), 'amount': 0},
      ),
    );
    _incomes.removeWhere((i) => i.month == key);
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  // --------------------------------------------------------------- internals ---

  String _requireUser() {
    final userId = _userId;
    if (userId == null) {
      throw StateError('No account is signed in, so there is nowhere to save.');
    }
    return userId;
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
    _connection.cancel();
    super.dispose();
  }
}
