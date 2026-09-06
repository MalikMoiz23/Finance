import 'package:sqflite/sqflite.dart';

import '../models/budget.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/family_member.dart';
import '../models/income.dart';
import '../models/project.dart';
import 'local_db.dart';

/// SQLite copy of the account's data, plus the outbox. Used on Android, iOS and
/// desktop; the web build uses [PrefsLocalDb] instead.
class SqfliteLocalDb implements LocalDb {
  SqfliteLocalDb({this.fileName = 'fintrack.db'});

  final String fileName;
  Database? _db;

  Database get _database {
    final db = _db;
    if (db == null) throw StateError('LocalDb.open() was not awaited');
    return db;
  }

  /// Bumped whenever the tables below change. Every version needs a matching
  /// branch in [_upgradeTo], or an existing install breaks on the next launch.
  static const schemaVersion = 3;

  @override
  Future<void> open() async {
    if (_db != null) return;
    _db = await openDatabase(
      // A relative name lands in the platform's databases directory.
      fileName,
      version: schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, from, to) async {
        // Runs on a device that already has data. Each step is additive, so
        // nothing stored offline is lost on the way up.
        for (var version = from + 1; version <= to; version++) {
          await _upgradeTo(db, version);
        }
      },
      onCreate: (db, _) async {
        final batch = db.batch();
        batch.execute('''
          CREATE TABLE expenses (
            user_id    TEXT    NOT NULL,
            id         TEXT    NOT NULL,
            amount     REAL    NOT NULL,
            category   TEXT    NOT NULL,
            spent_on   TEXT    NOT NULL,
            item       TEXT    NOT NULL DEFAULT '',
            note       TEXT    NOT NULL DEFAULT '',
            created_at TEXT    NOT NULL,
            PRIMARY KEY (user_id, id)
          )
        ''');
        batch.execute(
          'CREATE INDEX expenses_user_date ON expenses (user_id, spent_on DESC)',
        );
        batch.execute('''
          CREATE TABLE budgets (
            user_id       TEXT NOT NULL,
            category      TEXT NOT NULL,
            monthly_limit REAL NOT NULL,
            remote_id     TEXT,
            PRIMARY KEY (user_id, category)
          )
        ''');
        batch.execute('''
          CREATE TABLE incomes (
            user_id   TEXT NOT NULL,
            month     TEXT NOT NULL,
            amount    REAL NOT NULL,
            remote_id TEXT,
            PRIMARY KEY (user_id, month)
          )
        ''');
        batch.execute('''
          CREATE TABLE outbox (
            op_id   INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            entity  TEXT NOT NULL,
            action  TEXT NOT NULL,
            row_key TEXT NOT NULL,
            payload TEXT NOT NULL
          )
        ''');
        batch.execute('CREATE INDEX outbox_user ON outbox (user_id, op_id)');
        for (final statement in [..._v2, ..._v3]) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
      },
    );
  }

  static Future<void> _upgradeTo(Database db, int version) async {
    final statements = switch (version) {
      // Projects: the separate ledger for one-off spending paid from savings.
      2 => _v2,
      // The family: who spent each expense.
      3 => _v3,
      _ => const <String>[],
    };
    if (statements.isEmpty) return;
    final batch = db.batch();
    for (final statement in statements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  /// Added in schema version 2. Written once and used by both [_upgradeTo] and
  /// the fresh-install path, so a new device and an upgraded one end up with
  /// byte-identical tables.
  ///
  /// `project_entries` carries no SQL foreign key to `projects`, on purpose.
  /// Every write here is `INSERT OR REPLACE`, and with a cascading key SQLite
  /// treats the replace as a delete — re-saving a project would silently take
  /// its entries with it. The cascade lives in [removeProject] instead, where
  /// it only fires when a project is genuinely deleted.
  static const _v2 = <String>[
    '''
    CREATE TABLE projects (
      user_id    TEXT NOT NULL,
      id         TEXT NOT NULL,
      name       TEXT NOT NULL,
      estimate   REAL,
      note       TEXT NOT NULL DEFAULT '',
      started_on TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (user_id, id)
    )
    ''',
    '''
    CREATE TABLE project_entries (
      user_id    TEXT NOT NULL,
      id         TEXT NOT NULL,
      project_id TEXT NOT NULL,
      stage      TEXT NOT NULL DEFAULT '',
      amount     REAL NOT NULL,
      quantity   REAL,
      unit       TEXT NOT NULL DEFAULT '',
      rate       REAL,
      spent_on   TEXT NOT NULL,
      note       TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      PRIMARY KEY (user_id, id)
    )
    ''',
    'CREATE INDEX project_entries_project '
        'ON project_entries (user_id, project_id, spent_on DESC)',
  ];

  /// Added in schema version 3: the household's people, and the column on
  /// `expenses` naming which of them spent it.
  ///
  /// The column is added by `ALTER` here rather than written into the `CREATE
  /// TABLE expenses` above, so a fresh install runs the identical statement an
  /// upgraded one does. Putting it in both places would make the ALTER fail on
  /// a new device with "duplicate column name".
  ///
  /// No foreign key, for the same reason `project_entries` has none: every
  /// write is `INSERT OR REPLACE`, which SQLite implements as a delete, so a
  /// key here would have re-saving a member wipe them off their own expenses.
  /// [removeMember] clears the column by hand instead.
  static const _v3 = <String>[
    '''
    CREATE TABLE family_members (
      user_id    TEXT NOT NULL,
      id         TEXT NOT NULL,
      name       TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (user_id, id)
    )
    ''',
    'ALTER TABLE expenses ADD COLUMN member_id TEXT',
    'CREATE INDEX expenses_user_member ON expenses (user_id, member_id)',
  ];

  // ------------------------------------------------------------------ reads ---

  @override
  Future<List<Expense>> readExpenses(String userId) async {
    final rows = await _database.query(
      'expenses',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'spent_on DESC, created_at DESC',
    );
    return rows.map(_expenseFrom).toList();
  }

  @override
  Future<List<Budget>> readBudgets(String userId) async {
    final rows = await _database.query(
      'budgets',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows
        .map(
          (r) => Budget(
            id: r['remote_id'] as String?,
            category: ExpenseCategory.fromName(r['category'] as String),
            monthlyLimit: (r['monthly_limit'] as num).toDouble(),
          ),
        )
        .toList();
  }

  @override
  Future<List<MonthlyIncome>> readIncomes(String userId) async {
    final rows = await _database.query(
      'incomes',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'month ASC',
    );
    return rows
        .map(
          (r) => MonthlyIncome(
            id: r['remote_id'] as String?,
            month: DateTime.parse(r['month'] as String),
            amount: (r['amount'] as num).toDouble(),
          ),
        )
        .toList();
  }

  @override
  Future<List<Project>> readProjects(String userId) async {
    final rows = await _database.query(
      'projects',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'started_on DESC, created_at DESC',
    );
    return rows.map(_projectFrom).toList();
  }

  @override
  Future<List<ProjectEntry>> readProjectEntries(String userId) async {
    final rows = await _database.query(
      'project_entries',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'spent_on DESC, created_at DESC',
    );
    return rows.map(_entryFrom).toList();
  }

  @override
  Future<List<FamilyMember>> readMembers(String userId) async {
    final rows = await _database.query(
      'family_members',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (r) => FamilyMember(
            id: r['id'] as String,
            name: r['name'] as String,
            createdAt: DateTime.parse(r['created_at'] as String),
          ),
        )
        .toList();
  }

  static Expense _expenseFrom(Map<String, Object?> r) => Expense(
    id: r['id'] as String,
    amount: (r['amount'] as num).toDouble(),
    category: ExpenseCategory.fromName(r['category'] as String),
    date: DateTime.parse(r['spent_on'] as String),
    item: r['item'] as String? ?? '',
    note: r['note'] as String? ?? '',
    memberId: r['member_id'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  static Project _projectFrom(Map<String, Object?> r) => Project(
    id: r['id'] as String,
    name: r['name'] as String,
    estimate: (r['estimate'] as num?)?.toDouble(),
    note: r['note'] as String? ?? '',
    startedOn: DateTime.parse(r['started_on'] as String),
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  static ProjectEntry _entryFrom(Map<String, Object?> r) => ProjectEntry(
    id: r['id'] as String,
    projectId: r['project_id'] as String,
    stage: r['stage'] as String? ?? '',
    amount: (r['amount'] as num).toDouble(),
    quantity: (r['quantity'] as num?)?.toDouble(),
    unit: r['unit'] as String? ?? '',
    rate: (r['rate'] as num?)?.toDouble(),
    date: DateTime.parse(r['spent_on'] as String),
    note: r['note'] as String? ?? '',
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  // ----------------------------------------------------------------- writes ---

  Map<String, Object?> _expenseRow(String userId, Expense e) => {
    'user_id': userId,
    'id': e.id,
    'amount': e.amount,
    'category': e.category.name,
    'spent_on': e.date.toIso8601String(),
    'item': e.item,
    'note': e.note,
    'member_id': e.memberId,
    'created_at': e.createdAt.toIso8601String(),
  };

  @override
  Future<void> putExpense(String userId, Expense expense) async {
    await _database.insert(
      'expenses',
      _expenseRow(userId, expense),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> removeExpense(String userId, String id) async {
    await _database.delete(
      'expenses',
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, id],
    );
  }

  @override
  Future<void> putBudget(String userId, Budget budget) async {
    await _database.insert('budgets', {
      'user_id': userId,
      'category': budget.category.name,
      'monthly_limit': budget.monthlyLimit,
      'remote_id': budget.id,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removeBudget(String userId, ExpenseCategory category) async {
    await _database.delete(
      'budgets',
      where: 'user_id = ? AND category = ?',
      whereArgs: [userId, category.name],
    );
  }

  @override
  Future<void> putIncome(String userId, MonthlyIncome income) async {
    await _database.insert('incomes', {
      'user_id': userId,
      'month': DateTime(
        income.month.year,
        income.month.month,
      ).toIso8601String(),
      'amount': income.amount,
      'remote_id': income.id,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removeIncome(String userId, DateTime month) async {
    await _database.delete(
      'incomes',
      where: 'user_id = ? AND month = ?',
      whereArgs: [userId, DateTime(month.year, month.month).toIso8601String()],
    );
  }

  Map<String, Object?> _projectRow(String userId, Project p) => {
    'user_id': userId,
    'id': p.id,
    'name': p.name,
    'estimate': p.estimate,
    'note': p.note,
    'started_on': p.startedOn.toIso8601String(),
    'created_at': p.createdAt.toIso8601String(),
  };

  Map<String, Object?> _entryRow(String userId, ProjectEntry e) => {
    'user_id': userId,
    'id': e.id,
    'project_id': e.projectId,
    'stage': e.stage,
    'amount': e.amount,
    'quantity': e.quantity,
    'unit': e.unit,
    'rate': e.rate,
    'spent_on': e.date.toIso8601String(),
    'note': e.note,
    'created_at': e.createdAt.toIso8601String(),
  };

  @override
  Future<void> putProject(String userId, Project project) async {
    await _database.insert(
      'projects',
      _projectRow(userId, project),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> removeProject(String userId, String projectId) async {
    await _database.transaction((txn) async {
      await txn.delete(
        'project_entries',
        where: 'user_id = ? AND project_id = ?',
        whereArgs: [userId, projectId],
      );
      await txn.delete(
        'projects',
        where: 'user_id = ? AND id = ?',
        whereArgs: [userId, projectId],
      );
    });
  }

  @override
  Future<void> putProjectEntry(String userId, ProjectEntry entry) async {
    await _database.insert(
      'project_entries',
      _entryRow(userId, entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> removeProjectEntry(String userId, String entryId) async {
    await _database.delete(
      'project_entries',
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, entryId],
    );
  }

  @override
  Future<void> putMember(String userId, FamilyMember member) async {
    await _database.insert('family_members', {
      'user_id': userId,
      'id': member.id,
      'name': member.name,
      'created_at': member.createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removeMember(String userId, String memberId) async {
    await _database.transaction((txn) async {
      // Their spending stays; it just stops being attributed to anyone. Wiping
      // the expenses too would lose real money from every total.
      await txn.update(
        'expenses',
        {'member_id': null},
        where: 'user_id = ? AND member_id = ?',
        whereArgs: [userId, memberId],
      );
      await txn.delete(
        'family_members',
        where: 'user_id = ? AND id = ?',
        whereArgs: [userId, memberId],
      );
    });
  }

  // ------------------------------------------------------------ pull merges ---

  @override
  Future<void> replaceExpenses(
    String userId,
    List<Expense> rows, {
    Set<String> keepKeys = const {},
  }) async {
    await _database.transaction((txn) async {
      final existing = await txn.query(
        'expenses',
        columns: ['id'],
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      for (final row in existing) {
        final id = row['id'] as String;
        if (keepKeys.contains(id)) continue;
        await txn.delete(
          'expenses',
          where: 'user_id = ? AND id = ?',
          whereArgs: [userId, id],
        );
      }
      for (final expense in rows) {
        if (keepKeys.contains(expense.id)) continue;
        await txn.insert(
          'expenses',
          _expenseRow(userId, expense),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> replaceBudgets(
    String userId,
    List<Budget> rows, {
    Set<String> keepKeys = const {},
  }) async {
    await _database.transaction((txn) async {
      await txn.delete('budgets', where: 'user_id = ?', whereArgs: [userId]);
      for (final budget in rows) {
        if (keepKeys.contains(budget.category.name)) continue;
        await txn.insert('budgets', {
          'user_id': userId,
          'category': budget.category.name,
          'monthly_limit': budget.monthlyLimit,
          'remote_id': budget.id,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    // Unsynced local budgets were deleted above; the store re-applies them from
    // the outbox, so nothing queued is lost.
  }

  @override
  Future<void> replaceIncomes(
    String userId,
    List<MonthlyIncome> rows, {
    Set<String> keepKeys = const {},
  }) async {
    await _database.transaction((txn) async {
      await txn.delete('incomes', where: 'user_id = ?', whereArgs: [userId]);
      for (final income in rows) {
        final key = DateTime(
          income.month.year,
          income.month.month,
        ).toIso8601String();
        if (keepKeys.contains(key)) continue;
        await txn.insert('incomes', {
          'user_id': userId,
          'month': key,
          'amount': income.amount,
          'remote_id': income.id,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<void> replaceProjects(
    String userId,
    List<Project> rows, {
    Set<String> keepKeys = const {},
  }) async {
    await _database.transaction((txn) async {
      final existing = await txn.query(
        'projects',
        columns: ['id'],
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      for (final row in existing) {
        final id = row['id'] as String;
        if (keepKeys.contains(id)) continue;
        await txn.delete(
          'projects',
          where: 'user_id = ? AND id = ?',
          whereArgs: [userId, id],
        );
      }
      for (final project in rows) {
        if (keepKeys.contains(project.id)) continue;
        await txn.insert(
          'projects',
          _projectRow(userId, project),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> replaceProjectEntries(
    String userId,
    List<ProjectEntry> rows, {
    Set<String> keepKeys = const {},
  }) async {
    await _database.transaction((txn) async {
      final existing = await txn.query(
        'project_entries',
        columns: ['id'],
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      for (final row in existing) {
        final id = row['id'] as String;
        if (keepKeys.contains(id)) continue;
        await txn.delete(
          'project_entries',
          where: 'user_id = ? AND id = ?',
          whereArgs: [userId, id],
        );
      }
      for (final entry in rows) {
        if (keepKeys.contains(entry.id)) continue;
        await txn.insert(
          'project_entries',
          _entryRow(userId, entry),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> replaceMembers(
    String userId,
    List<FamilyMember> rows, {
    Set<String> keepKeys = const {},
  }) async {
    await _database.transaction((txn) async {
      final existing = await txn.query(
        'family_members',
        columns: ['id'],
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      for (final row in existing) {
        final id = row['id'] as String;
        if (keepKeys.contains(id)) continue;
        await txn.delete(
          'family_members',
          where: 'user_id = ? AND id = ?',
          whereArgs: [userId, id],
        );
      }
      for (final member in rows) {
        if (keepKeys.contains(member.id)) continue;
        await txn.insert('family_members', {
          'user_id': userId,
          'id': member.id,
          'name': member.name,
          'created_at': member.createdAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ----------------------------------------------------------------- outbox ---

  @override
  Future<void> enqueue(String userId, PendingOp op) async {
    await _database.transaction((txn) async {
      // Collapse: a newer op for the same row supersedes anything queued for it.
      if (op.action == SyncAction.deleteAll) {
        await txn.delete(
          'outbox',
          where: 'user_id = ? AND entity = ?',
          whereArgs: [userId, op.entity.name],
        );
      } else if (op.key.isNotEmpty) {
        await txn.delete(
          'outbox',
          where: 'user_id = ? AND entity = ? AND row_key = ?',
          whereArgs: [userId, op.entity.name, op.key],
        );
      }
      await txn.insert('outbox', {'user_id': userId, ...op.toRow()});
    });
  }

  @override
  Future<List<PendingOp>> pendingOps(String userId) async {
    final rows = await _database.query(
      'outbox',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'op_id ASC',
    );
    return rows.map(PendingOp.fromRow).toList();
  }

  @override
  Future<void> completeOp(String userId, int opId) async {
    await _database.delete(
      'outbox',
      where: 'user_id = ? AND op_id = ?',
      whereArgs: [userId, opId],
    );
  }

  @override
  Future<int> pendingCount(String userId) async {
    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS n FROM outbox WHERE user_id = ?',
      [userId],
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> dropQueued(
    String userId,
    SyncEntity entity,
    Set<String> keys,
  ) async {
    if (keys.isEmpty) return;
    final slots = List.filled(keys.length, '?').join(', ');
    await _database.delete(
      'outbox',
      where: 'user_id = ? AND entity = ? AND row_key IN ($slots)',
      whereArgs: [userId, entity.name, ...keys],
    );
  }

  @override
  Future<void> clearUser(String userId) async {
    await _database.transaction((txn) async {
      for (final table in [
        'expenses',
        'budgets',
        'incomes',
        'projects',
        'project_entries',
        'family_members',
        'outbox',
      ]) {
        await txn.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      }
    });
  }
}
