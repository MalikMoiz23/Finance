import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/budget.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/family_member.dart';
import '../models/income.dart';
import '../models/project.dart';
import '../models/vehicle.dart';
import 'local_db.dart';

/// Somewhere to put strings. Lets the same LocalDb logic run on preferences
/// (web) or in memory (tests).
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class PrefsKeyValueStore implements KeyValueStore {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _prefs).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await _prefs).setString(key, value);

  @override
  Future<void> remove(String key) async => (await _prefs).remove(key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}

/// JSON-document implementation of [LocalDb], for platforms without SQLite
/// (web) and for tests. Same contract, same outbox semantics — the storage
/// medium is the only difference.
class JsonLocalDb implements LocalDb {
  JsonLocalDb(this._store);

  final KeyValueStore _store;
  int _nextOpId = 1;

  /// Every operation here is read-modify-write on a whole JSON document, so two
  /// overlapping calls would lose one of the changes. Sync runs concurrently
  /// with user writes, so the calls are queued through this chain and applied
  /// one at a time — the equivalent of SQLite's transactions.
  Future<void> _gate = Future.value();

  Future<T> _serial<T>(Future<T> Function() body) {
    final result = _gate.then((_) => body());
    // Swallow errors on the gate only; the caller still sees them via [result].
    _gate = result.then((_) {}, onError: (_) {});
    return result;
  }

  String _key(String userId, String table) => 'ldb_${table}_$userId';

  Future<List<Map<String, dynamic>>> _list(String userId, String table) async {
    final raw = await _store.read(_key(userId, table));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> _save(
    String userId,
    String table,
    List<Map<String, dynamic>> rows,
  ) => _store.write(_key(userId, table), jsonEncode(rows));

  @override
  Future<void> open() async {
    // Nothing to open; keep the outbox ids ahead of anything already stored.
    _nextOpId = 1;
  }

  // ------------------------------------------------------------------ reads ---

  @override
  Future<List<Expense>> readExpenses(String userId) async {
    final rows = await _list(userId, 'expenses');
    final out = rows.map(Expense.fromJson).whereType<Expense>().toList();
    out.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
    return out;
  }

  @override
  Future<List<Budget>> readBudgets(String userId) async => (await _list(
    userId,
    'budgets',
  )).map(Budget.fromJson).whereType<Budget>().toList();

  @override
  Future<List<MonthlyIncome>> readIncomes(String userId) async {
    final out = (await _list(
      userId,
      'incomes',
    )).map(MonthlyIncome.fromJson).whereType<MonthlyIncome>().toList();
    out.sort((a, b) => a.month.compareTo(b.month));
    return out;
  }

  @override
  Future<List<Project>> readProjects(String userId) async {
    final out = (await _list(
      userId,
      'projects',
    )).map(Project.fromJson).whereType<Project>().toList();
    out.sort((a, b) {
      final byStart = b.startedOn.compareTo(a.startedOn);
      return byStart != 0 ? byStart : b.createdAt.compareTo(a.createdAt);
    });
    return out;
  }

  @override
  Future<List<ProjectEntry>> readProjectEntries(String userId) async {
    final out = (await _list(
      userId,
      'project_entries',
    )).map(ProjectEntry.fromJson).whereType<ProjectEntry>().toList();
    out.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
    return out;
  }

  @override
  Future<List<FamilyMember>> readMembers(String userId) async {
    final out = (await _list(
      userId,
      'family_members',
    )).map(FamilyMember.fromJson).whereType<FamilyMember>().toList();
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  @override
  Future<List<Vehicle>> readVehicles(String userId) async {
    final out = (await _list(
      userId,
      'vehicles',
    )).map(Vehicle.fromJson).whereType<Vehicle>().toList();
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  @override
  Future<List<VehicleService>> readVehicleServices(String userId) async {
    final out = (await _list(
      userId,
      'vehicle_services',
    )).map(VehicleService.fromJson).whereType<VehicleService>().toList();
    out.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.odometer.compareTo(a.odometer);
    });
    return out;
  }

  // ----------------------------------------------------------------- writes ---

  @override
  Future<void> putExpense(String userId, Expense expense) =>
      _serial(() => _putExpense(userId, expense));

  Future<void> _putExpense(String userId, Expense expense) async {
    final rows = await _list(userId, 'expenses')
      ..removeWhere((r) => r['id'] == expense.id);
    rows.add(expense.toJson());
    await _save(userId, 'expenses', rows);
  }

  @override
  Future<void> removeExpense(String userId, String id) =>
      _serial(() => _removeExpense(userId, id));

  Future<void> _removeExpense(String userId, String id) async {
    final rows = await _list(userId, 'expenses')
      ..removeWhere((r) => r['id'] == id);
    await _save(userId, 'expenses', rows);
  }

  @override
  Future<void> putBudget(String userId, Budget budget) =>
      _serial(() => _putBudget(userId, budget));

  Future<void> _putBudget(String userId, Budget budget) async {
    final rows = await _list(userId, 'budgets')
      ..removeWhere((r) => r['category'] == budget.category.name);
    rows.add(budget.toJson());
    await _save(userId, 'budgets', rows);
  }

  @override
  Future<void> removeBudget(String userId, ExpenseCategory category) =>
      _serial(() => _removeBudget(userId, category));

  Future<void> _removeBudget(String userId, ExpenseCategory category) async {
    final rows = await _list(userId, 'budgets')
      ..removeWhere((r) => r['category'] == category.name);
    await _save(userId, 'budgets', rows);
  }

  static String _monthKey(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}-01';

  @override
  Future<void> putIncome(String userId, MonthlyIncome income) =>
      _serial(() => _putIncome(userId, income));

  Future<void> _putIncome(String userId, MonthlyIncome income) async {
    final key = _monthKey(income.month);
    final rows = await _list(userId, 'incomes')
      ..removeWhere((r) => r['month'] == key);
    rows.add(income.toJson());
    await _save(userId, 'incomes', rows);
  }

  @override
  Future<void> removeIncome(String userId, DateTime month) =>
      _serial(() => _removeIncome(userId, month));

  Future<void> _removeIncome(String userId, DateTime month) async {
    final key = _monthKey(month);
    final rows = await _list(userId, 'incomes')
      ..removeWhere((r) => r['month'] == key);
    await _save(userId, 'incomes', rows);
  }

  @override
  Future<void> putProject(String userId, Project project) =>
      _serial(() => _putProject(userId, project));

  Future<void> _putProject(String userId, Project project) async {
    final rows = await _list(userId, 'projects')
      ..removeWhere((r) => r['id'] == project.id);
    rows.add(project.toJson());
    await _save(userId, 'projects', rows);
  }

  @override
  Future<void> removeProject(String userId, String projectId) =>
      _serial(() => _removeProject(userId, projectId));

  Future<void> _removeProject(String userId, String projectId) async {
    final projects = await _list(userId, 'projects')
      ..removeWhere((r) => r['id'] == projectId);
    await _save(userId, 'projects', projects);
    // Same cascade the SQLite side does by hand, for the same reason: an entry
    // whose project is gone would never be reachable or countable again.
    final entries = await _list(userId, 'project_entries')
      ..removeWhere((r) => r['project_id'] == projectId);
    await _save(userId, 'project_entries', entries);
  }

  @override
  Future<void> putProjectEntry(String userId, ProjectEntry entry) =>
      _serial(() => _putProjectEntry(userId, entry));

  Future<void> _putProjectEntry(String userId, ProjectEntry entry) async {
    final rows = await _list(userId, 'project_entries')
      ..removeWhere((r) => r['id'] == entry.id);
    rows.add(entry.toJson());
    await _save(userId, 'project_entries', rows);
  }

  @override
  Future<void> removeProjectEntry(String userId, String entryId) =>
      _serial(() => _removeProjectEntry(userId, entryId));

  Future<void> _removeProjectEntry(String userId, String entryId) async {
    final rows = await _list(userId, 'project_entries')
      ..removeWhere((r) => r['id'] == entryId);
    await _save(userId, 'project_entries', rows);
  }

  @override
  Future<void> putMember(String userId, FamilyMember member) =>
      _serial(() => _putMember(userId, member));

  Future<void> _putMember(String userId, FamilyMember member) async {
    final rows = await _list(userId, 'family_members')
      ..removeWhere((r) => r['id'] == member.id);
    rows.add(member.toJson());
    await _save(userId, 'family_members', rows);
  }

  @override
  Future<void> removeMember(String userId, String memberId) =>
      _serial(() => _removeMember(userId, memberId));

  Future<void> _removeMember(String userId, String memberId) async {
    final members = await _list(userId, 'family_members')
      ..removeWhere((r) => r['id'] == memberId);
    await _save(userId, 'family_members', members);
    // The same `on delete set null` the server does: their spending stays, it
    // just stops being attributed to anyone.
    final expenses = await _list(userId, 'expenses');
    var touched = false;
    for (final row in expenses) {
      if (row['memberId'] == memberId) {
        row['memberId'] = null;
        touched = true;
      }
    }
    if (touched) await _save(userId, 'expenses', expenses);
  }

  @override
  Future<void> putVehicle(String userId, Vehicle vehicle) =>
      _serial(() => _putRow(userId, 'vehicles', vehicle.toJson()));

  @override
  Future<void> removeVehicle(String userId, String vehicleId) =>
      _serial(() => _removeVehicle(userId, vehicleId));

  Future<void> _removeVehicle(String userId, String vehicleId) async {
    final vehicles = await _list(userId, 'vehicles')
      ..removeWhere((r) => r['id'] == vehicleId);
    await _save(userId, 'vehicles', vehicles);
    // The cascade the server does: a service record with no vehicle would
    // never be reachable again.
    final services = await _list(userId, 'vehicle_services')
      ..removeWhere((r) => r['vehicle_id'] == vehicleId);
    await _save(userId, 'vehicle_services', services);
  }

  @override
  Future<void> putVehicleService(String userId, VehicleService service) =>
      _serial(() => _putRow(userId, 'vehicle_services', service.toJson()));

  @override
  Future<void> removeVehicleService(String userId, String serviceId) =>
      _serial(() async {
        final rows = await _list(userId, 'vehicle_services')
          ..removeWhere((r) => r['id'] == serviceId);
        await _save(userId, 'vehicle_services', rows);
      });

  /// Insert-or-replace by `id`, for the tables keyed that way.
  Future<void> _putRow(
    String userId,
    String table,
    Map<String, dynamic> row,
  ) async {
    final rows = await _list(userId, table)
      ..removeWhere((r) => r['id'] == row['id']);
    rows.add(row);
    await _save(userId, table, rows);
  }

  // ------------------------------------------------------------ pull merges ---

  @override
  Future<void> replaceExpenses(
    String userId,
    List<Expense> rows, {
    Set<String> keepKeys = const {},
  }) => _serial(() => _replaceExpenses(userId, rows, keepKeys: keepKeys));

  Future<void> _replaceExpenses(
    String userId,
    List<Expense> rows, {
    Set<String> keepKeys = const {},
  }) async {
    final existing = await _list(userId, 'expenses');
    final kept = existing
        .where((r) => keepKeys.contains(r['id'] as String? ?? ''))
        .toList();
    final incoming = rows
        .where((e) => !keepKeys.contains(e.id))
        .map((e) => e.toJson());
    await _save(userId, 'expenses', [...kept, ...incoming]);
  }

  @override
  Future<void> replaceBudgets(
    String userId,
    List<Budget> rows, {
    Set<String> keepKeys = const {},
  }) => _serial(() => _replaceBudgets(userId, rows, keepKeys: keepKeys));

  Future<void> _replaceBudgets(
    String userId,
    List<Budget> rows, {
    Set<String> keepKeys = const {},
  }) async {
    final existing = await _list(userId, 'budgets');
    final kept = existing
        .where((r) => keepKeys.contains(r['category'] as String? ?? ''))
        .toList();
    final incoming = rows
        .where((b) => !keepKeys.contains(b.category.name))
        .map((b) => b.toJson());
    await _save(userId, 'budgets', [...kept, ...incoming]);
  }

  @override
  Future<void> replaceIncomes(
    String userId,
    List<MonthlyIncome> rows, {
    Set<String> keepKeys = const {},
  }) => _serial(() => _replaceIncomes(userId, rows, keepKeys: keepKeys));

  Future<void> _replaceIncomes(
    String userId,
    List<MonthlyIncome> rows, {
    Set<String> keepKeys = const {},
  }) async {
    final existing = await _list(userId, 'incomes');
    final kept = existing
        .where((r) => keepKeys.contains(r['month'] as String? ?? ''))
        .toList();
    final incoming = rows
        .where((i) => !keepKeys.contains(_monthKey(i.month)))
        .map((i) => i.toJson());
    await _save(userId, 'incomes', [...kept, ...incoming]);
  }

  @override
  Future<void> replaceProjects(
    String userId,
    List<Project> rows, {
    Set<String> keepKeys = const {},
  }) => _serial(() => _replaceProjects(userId, rows, keepKeys: keepKeys));

  Future<void> _replaceProjects(
    String userId,
    List<Project> rows, {
    Set<String> keepKeys = const {},
  }) async {
    final existing = await _list(userId, 'projects');
    final kept = existing
        .where((r) => keepKeys.contains(r['id'] as String? ?? ''))
        .toList();
    final incoming = rows
        .where((p) => !keepKeys.contains(p.id))
        .map((p) => p.toJson());
    await _save(userId, 'projects', [...kept, ...incoming]);
  }

  @override
  Future<void> replaceProjectEntries(
    String userId,
    List<ProjectEntry> rows, {
    Set<String> keepKeys = const {},
  }) => _serial(() => _replaceProjectEntries(userId, rows, keepKeys: keepKeys));

  Future<void> _replaceProjectEntries(
    String userId,
    List<ProjectEntry> rows, {
    Set<String> keepKeys = const {},
  }) async {
    final existing = await _list(userId, 'project_entries');
    final kept = existing
        .where((r) => keepKeys.contains(r['id'] as String? ?? ''))
        .toList();
    final incoming = rows
        .where((e) => !keepKeys.contains(e.id))
        .map((e) => e.toJson());
    await _save(userId, 'project_entries', [...kept, ...incoming]);
  }

  @override
  Future<void> replaceMembers(
    String userId,
    List<FamilyMember> rows, {
    Set<String> keepKeys = const {},
  }) => _serial(() => _replaceMembers(userId, rows, keepKeys: keepKeys));

  Future<void> _replaceMembers(
    String userId,
    List<FamilyMember> rows, {
    Set<String> keepKeys = const {},
  }) async {
    final existing = await _list(userId, 'family_members');
    final kept = existing
        .where((r) => keepKeys.contains(r['id'] as String? ?? ''))
        .toList();
    final incoming = rows
        .where((m) => !keepKeys.contains(m.id))
        .map((m) => m.toJson());
    await _save(userId, 'family_members', [...kept, ...incoming]);
  }

  @override
  Future<void> replaceVehicles(
    String userId,
    List<Vehicle> rows, {
    Set<String> keepKeys = const {},
  }) => _serial(
    () => _replaceById(
      userId,
      'vehicles',
      rows.map((v) => v.toJson()).toList(),
      keepKeys,
    ),
  );

  @override
  Future<void> replaceVehicleServices(
    String userId,
    List<VehicleService> rows, {
    Set<String> keepKeys = const {},
  }) => _serial(
    () => _replaceById(
      userId,
      'vehicle_services',
      rows.map((s) => s.toJson()).toList(),
      keepKeys,
    ),
  );

  /// The pull merge for tables keyed by `id`: server rows replace local ones,
  /// except those named in [keepKeys], which have newer unsynced edits.
  Future<void> _replaceById(
    String userId,
    String table,
    List<Map<String, dynamic>> incoming,
    Set<String> keepKeys,
  ) async {
    final existing = await _list(userId, table);
    final kept = existing
        .where((r) => keepKeys.contains(r['id'] as String? ?? ''))
        .toList();
    final fresh = incoming.where((r) => !keepKeys.contains(r['id']));
    await _save(userId, table, [...kept, ...fresh]);
  }

  // ----------------------------------------------------------------- outbox ---

  @override
  Future<void> enqueue(String userId, PendingOp op) =>
      _serial(() => _enqueue(userId, op));

  Future<void> _enqueue(String userId, PendingOp op) async {
    final rows = await _list(userId, 'outbox');
    if (op.action == SyncAction.deleteAll) {
      rows.removeWhere((r) => r['entity'] == op.entity.name);
    } else if (op.key.isNotEmpty) {
      rows.removeWhere(
        (r) => r['entity'] == op.entity.name && r['row_key'] == op.key,
      );
    }
    final highest = rows.fold<int>(
      0,
      (m, r) => ((r['op_id'] as num?)?.toInt() ?? 0) > m
          ? (r['op_id'] as num).toInt()
          : m,
    );
    _nextOpId = highest + 1;
    rows.add({'op_id': _nextOpId, ...op.toRow()});
    await _save(userId, 'outbox', rows);
  }

  @override
  Future<List<PendingOp>> pendingOps(String userId) async {
    final rows = await _list(userId, 'outbox')
      ..sort(
        (a, b) => ((a['op_id'] as num?)?.toInt() ?? 0).compareTo(
          (b['op_id'] as num?)?.toInt() ?? 0,
        ),
      );
    return rows.map(PendingOp.fromRow).toList();
  }

  @override
  Future<void> completeOp(String userId, int opId) =>
      _serial(() => _completeOp(userId, opId));

  Future<void> _completeOp(String userId, int opId) async {
    final rows = await _list(userId, 'outbox')
      ..removeWhere((r) => ((r['op_id'] as num?)?.toInt() ?? 0) == opId);
    await _save(userId, 'outbox', rows);
  }

  @override
  Future<int> pendingCount(String userId) async =>
      (await _list(userId, 'outbox')).length;

  @override
  Future<void> dropQueued(String userId, SyncEntity entity, Set<String> keys) =>
      _serial(() => _dropQueued(userId, entity, keys));

  Future<void> _dropQueued(
    String userId,
    SyncEntity entity,
    Set<String> keys,
  ) async {
    if (keys.isEmpty) return;
    final rows = await _list(userId, 'outbox')
      ..removeWhere(
        (r) =>
            r['entity'] == entity.name &&
            keys.contains(r['row_key'] as String? ?? ''),
      );
    await _save(userId, 'outbox', rows);
  }

  @override
  Future<void> clearUser(String userId) async {
    for (final table in [
      'expenses',
      'budgets',
      'incomes',
      'projects',
      'project_entries',
      'family_members',
      'vehicles',
      'vehicle_services',
      'outbox',
    ]) {
      await _store.remove(_key(userId, table));
    }
  }
}
