import 'package:sqflite/sqflite.dart';

import '../models/budget.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/income.dart';
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

  @override
  Future<void> open() async {
    if (_db != null) return;
    _db = await openDatabase(
      // A relative name lands in the platform's databases directory.
      fileName,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
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
        await batch.commit(noResult: true);
      },
    );
  }

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

  static Expense _expenseFrom(Map<String, Object?> r) => Expense(
    id: r['id'] as String,
    amount: (r['amount'] as num).toDouble(),
    category: ExpenseCategory.fromName(r['category'] as String),
    date: DateTime.parse(r['spent_on'] as String),
    item: r['item'] as String? ?? '',
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
  Future<void> clearUser(String userId) async {
    await _database.transaction((txn) async {
      for (final table in ['expenses', 'budgets', 'incomes', 'outbox']) {
        await txn.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      }
    });
  }
}
