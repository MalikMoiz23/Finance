import 'dart:async';

import 'package:finance/data/auth_gateway.dart';
import 'package:finance/data/budget_api.dart';
import 'package:finance/data/expense_api.dart';
import 'package:finance/data/income_api.dart';
import 'package:finance/data/project_api.dart';
import 'package:finance/models/app_user.dart';
import 'package:finance/models/budget.dart';
import 'package:finance/models/income.dart';
import 'package:finance/models/expense.dart';
import 'package:finance/models/expense_category.dart';
import 'package:finance/models/project.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

/// In-memory stand-ins for Supabase, so the widget tests exercise the real
/// screens, store and error handling without a network or a project.
class FakeAuthGateway implements AuthGateway {
  final _changes = StreamController<AppUser?>.broadcast();
  final Map<String, _Account> _accounts = {};
  AppUser? _current;
  int _nextId = 1;

  /// Mirrors the dashboard's "Confirm email" switch.
  bool requireEmailConfirmation = false;

  @override
  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> get changes => _changes.stream;

  @override
  Future<RegisterOutcome> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key)) {
      throw AuthException('User already registered');
    }
    if (password.length < 6) {
      throw AuthException('Password should be at least 6 characters');
    }
    _accounts[key] = _Account(
      id: 'user-${_nextId++}',
      name: name.trim(),
      password: password,
    );
    if (requireEmailConfirmation) return RegisterOutcome.needsEmailConfirmation;
    _emit(key);
    return RegisterOutcome.signedIn;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    final key = email.trim().toLowerCase();
    final account = _accounts[key];
    if (account == null || account.password != password) {
      throw AuthException('Invalid login credentials');
    }
    _emit(key);
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _changes.add(null);
  }

  void _emit(String email) {
    final account = _accounts[email]!;
    _current = AppUser(id: account.id, email: email, name: account.name);
    _changes.add(_current);
  }

  void dispose() => _changes.close();
}

class _Account {
  _Account({required this.id, required this.name, required this.password});

  final String id;
  final String name;
  final String password;
}

/// Rows are stored per user id, the way row level security scopes them on the
/// server, so account isolation is actually testable.
class FakeExpenseApi implements ExpenseApi {
  FakeExpenseApi(this._auth);

  final FakeAuthGateway _auth;
  final Map<String, List<Expense>> _rows = {};

  /// When true every call fails the way a dropped connection does.
  bool offline = false;

  /// Fails the next write once, then clears itself.
  bool failNextWrite = false;

  String get _userId {
    final id = _auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  List<Expense> rowsFor(String userId) =>
      List.unmodifiable(_rows[userId] ?? []);

  void seed(String userId, List<Expense> expenses) {
    _rows.putIfAbsent(userId, () => []).addAll(expenses);
  }

  void _guard({bool write = false}) {
    if (offline) {
      throw Exception('ClientException: Failed host lookup');
    }
    if (write && failNextWrite) {
      failNextWrite = false;
      throw Exception('ClientException: connection closed');
    }
  }

  @override
  Future<List<Expense>> fetchAll() async {
    _guard();
    final rows = [...?_rows[_userId]];
    rows.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
    return rows;
  }

  @override
  Future<void> upsert(Expense expense) async {
    _guard(write: true);
    final rows = _rows.putIfAbsent(_userId, () => []);
    final index = rows.indexWhere((e) => e.id == expense.id);
    if (index == -1) {
      rows.add(expense);
    } else {
      rows[index] = expense;
    }
  }

  @override
  Future<void> delete(String id) async {
    _guard(write: true);
    (_rows[_userId] ?? []).removeWhere((e) => e.id == id);
  }

  @override
  Future<void> deleteAll() async {
    _guard(write: true);
    _rows[_userId]?.clear();
  }
}

/// Budgets kept per user id, the way row level security scopes them.
class FakeBudgetApi implements BudgetApi {
  FakeBudgetApi(this._auth);

  final FakeAuthGateway _auth;
  final Map<String, List<Budget>> _rows = {};
  int _nextId = 1;

  bool offline = false;
  bool failNextWrite = false;

  String get _userId {
    final id = _auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  List<Budget> rowsFor(String userId) => List.unmodifiable(_rows[userId] ?? []);

  void _guard({bool write = false}) {
    if (offline) throw Exception('ClientException: Failed host lookup');
    if (write && failNextWrite) {
      failNextWrite = false;
      throw Exception('ClientException: connection closed');
    }
  }

  @override
  Future<List<Budget>> fetchAll() async {
    _guard();
    return [...?_rows[_userId]];
  }

  @override
  Future<void> save(ExpenseCategory category, double monthlyLimit) async {
    _guard(write: true);
    final rows = _rows.putIfAbsent(_userId, () => []);
    final index = rows.indexWhere((b) => b.category == category);
    final saved = Budget(
      id: index == -1 ? 'budget-${_nextId++}' : rows[index].id,
      category: category,
      monthlyLimit: monthlyLimit,
    );
    if (index == -1) {
      rows.add(saved);
    } else {
      rows[index] = saved;
    }
  }

  @override
  Future<void> remove(ExpenseCategory category) async {
    _guard(write: true);
    (_rows[_userId] ?? []).removeWhere((b) => b.category == category);
  }

  @override
  Future<void> removeAll() async {
    _guard(write: true);
    _rows[_userId]?.clear();
  }
}

/// Monthly pay per user id, matching how row level security scopes it.
class FakeIncomeApi implements IncomeApi {
  FakeIncomeApi(this._auth);

  final FakeAuthGateway _auth;
  final Map<String, List<MonthlyIncome>> _rows = {};
  int _nextId = 1;

  bool offline = false;
  bool failNextWrite = false;

  String get _userId {
    final id = _auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  List<MonthlyIncome> rowsFor(String userId) =>
      List.unmodifiable(_rows[userId] ?? []);

  void seed(String userId, List<MonthlyIncome> incomes) {
    _rows.putIfAbsent(userId, () => []).addAll(incomes);
  }

  void _guard({bool write = false}) {
    if (offline) throw Exception('ClientException: Failed host lookup');
    if (write && failNextWrite) {
      failNextWrite = false;
      throw Exception('ClientException: connection closed');
    }
  }

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

  @override
  Future<List<MonthlyIncome>> fetchAll() async {
    _guard();
    return [...?_rows[_userId]]..sort((a, b) => a.month.compareTo(b.month));
  }

  @override
  Future<void> save(DateTime month, double amount) async {
    _guard(write: true);
    final key = _monthOf(month);
    final rows = _rows.putIfAbsent(_userId, () => []);
    final index = rows.indexWhere((i) => i.month == key);
    final saved = MonthlyIncome(
      id: index == -1 ? 'income-${_nextId++}' : rows[index].id,
      month: key,
      amount: amount,
    );
    if (index == -1) {
      rows.add(saved);
    } else {
      rows[index] = saved;
    }
  }

  @override
  Future<void> remove(DateTime month) async {
    _guard(write: true);
    final key = _monthOf(month);
    (_rows[_userId] ?? []).removeWhere((i) => i.month == key);
  }
}

/// Projects and their entries per user id.
///
/// Enforces the server's foreign key: an entry whose project is not there is
/// rejected, and deleting a project takes its entries with it. Without that the
/// tests would happily pass on a queue ordering Postgres would refuse.
class FakeProjectApi implements ProjectApi {
  FakeProjectApi(this._auth);

  final FakeAuthGateway _auth;
  final Map<String, List<Project>> _projects = {};
  final Map<String, List<ProjectEntry>> _entries = {};

  bool offline = false;
  bool failNextWrite = false;

  String get _userId {
    final id = _auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in');
    return id;
  }

  List<Project> projectsFor(String userId) =>
      List.unmodifiable(_projects[userId] ?? []);

  List<ProjectEntry> entriesFor(String userId) =>
      List.unmodifiable(_entries[userId] ?? []);

  void _guard({bool write = false}) {
    if (offline) throw Exception('ClientException: Failed host lookup');
    if (write && failNextWrite) {
      failNextWrite = false;
      throw Exception('ClientException: connection closed');
    }
  }

  @override
  Future<List<Project>> fetchProjects() async {
    _guard();
    return [...?_projects[_userId]];
  }

  @override
  Future<List<ProjectEntry>> fetchEntries() async {
    _guard();
    return [...?_entries[_userId]];
  }

  @override
  Future<void> upsertProject(Project project) async {
    _guard(write: true);
    final rows = _projects.putIfAbsent(_userId, () => []);
    final index = rows.indexWhere((p) => p.id == project.id);
    if (index == -1) {
      rows.add(project);
    } else {
      rows[index] = project;
    }
  }

  @override
  Future<void> deleteProject(String id) async {
    _guard(write: true);
    (_projects[_userId] ?? []).removeWhere((p) => p.id == id);
    // `on delete cascade` on project_entries.project_id.
    (_entries[_userId] ?? []).removeWhere((e) => e.projectId == id);
  }

  @override
  Future<void> upsertEntry(ProjectEntry entry) async {
    _guard(write: true);
    final projects = _projects[_userId] ?? const <Project>[];
    if (!projects.any((p) => p.id == entry.projectId)) {
      // What Postgres answers with: 23503, foreign key violation.
      throw Exception(
        'PostgrestException: insert or update on table "project_entries" '
        'violates foreign key constraint',
      );
    }
    final rows = _entries.putIfAbsent(_userId, () => []);
    final index = rows.indexWhere((e) => e.id == entry.id);
    if (index == -1) {
      rows.add(entry);
    } else {
      rows[index] = entry;
    }
  }

  @override
  Future<void> deleteEntry(String id) async {
    _guard(write: true);
    (_entries[_userId] ?? []).removeWhere((e) => e.id == id);
  }
}
