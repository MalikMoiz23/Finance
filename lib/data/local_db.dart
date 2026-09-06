import 'dart:convert';

import '../models/budget.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/family_member.dart';
import '../models/income.dart';
import '../models/project.dart';

/// Which table a queued change belongs to.
enum SyncEntity { expense, budget, income, project, projectEntry, member }

/// What the queued change does.
enum SyncAction { upsert, delete, deleteAll }

/// One change made on this device that Supabase has not accepted yet.
///
/// The queue is the whole offline story: a write lands in the local database and
/// an op lands here, so the UI is instant and nothing depends on the network.
class PendingOp {
  const PendingOp({
    required this.entity,
    required this.action,
    required this.payload,
    this.id = 0,
    this.key = '',
  });

  /// Row id in the outbox; 0 before it is stored.
  final int id;

  final SyncEntity entity;
  final SyncAction action;

  /// The row, as JSON, for an upsert. Empty for deleteAll.
  final Map<String, dynamic> payload;

  /// Identifies the target row: expense id, category name, or month. Lets a
  /// later op for the same row replace an earlier queued one.
  final String key;

  Expense? get expense =>
      entity == SyncEntity.expense ? Expense.fromJson(payload) : null;

  Budget? get budget =>
      entity == SyncEntity.budget ? Budget.fromJson(payload) : null;

  MonthlyIncome? get income =>
      entity == SyncEntity.income ? MonthlyIncome.fromJson(payload) : null;

  Project? get project =>
      entity == SyncEntity.project ? Project.fromJson(payload) : null;

  ProjectEntry? get projectEntry =>
      entity == SyncEntity.projectEntry ? ProjectEntry.fromJson(payload) : null;

  FamilyMember? get member =>
      entity == SyncEntity.member ? FamilyMember.fromJson(payload) : null;

  ExpenseCategory get category =>
      ExpenseCategory.fromName(payload['category'] as String? ?? 'other');

  DateTime get month =>
      DateTime.tryParse(payload['month'] as String? ?? '') ?? DateTime.now();

  Map<String, dynamic> toRow() => {
    'entity': entity.name,
    'action': action.name,
    'row_key': key,
    'payload': jsonEncode(payload),
  };

  static PendingOp fromRow(Map<String, dynamic> row) {
    final decoded = jsonDecode(row['payload'] as String? ?? '{}');
    return PendingOp(
      id: (row['op_id'] as num?)?.toInt() ?? 0,
      entity: SyncEntity.values.firstWhere(
        (e) => e.name == row['entity'],
        orElse: () => SyncEntity.expense,
      ),
      action: SyncAction.values.firstWhere(
        (a) => a.name == row['action'],
        orElse: () => SyncAction.upsert,
      ),
      key: row['row_key'] as String? ?? '',
      payload: decoded is Map<String, dynamic> ? decoded : const {},
    );
  }
}

/// The device's own copy of the data, plus the outbox of unsynced changes.
///
/// Reads always come from here, so the app works with no connection at all.
/// Two implementations exist: SQLite on phone and desktop, and a preferences
/// backed one on web where SQLite is not available.
abstract interface class LocalDb {
  Future<void> open();

  Future<List<Expense>> readExpenses(String userId);
  Future<List<Budget>> readBudgets(String userId);
  Future<List<MonthlyIncome>> readIncomes(String userId);
  Future<List<Project>> readProjects(String userId);
  Future<List<ProjectEntry>> readProjectEntries(String userId);
  Future<List<FamilyMember>> readMembers(String userId);

  /// Applies a change locally. Used both for the user's own edits and for rows
  /// arriving from a pull.
  Future<void> putExpense(String userId, Expense expense);
  Future<void> removeExpense(String userId, String id);
  Future<void> putBudget(String userId, Budget budget);
  Future<void> removeBudget(String userId, ExpenseCategory category);
  Future<void> putIncome(String userId, MonthlyIncome income);
  Future<void> removeIncome(String userId, DateTime month);
  Future<void> putProject(String userId, Project project);

  /// Deletes the project **and every entry belonging to it**, matching the
  /// cascade on the server so the two copies cannot disagree.
  Future<void> removeProject(String userId, String projectId);
  Future<void> putProjectEntry(String userId, ProjectEntry entry);
  Future<void> removeProjectEntry(String userId, String entryId);
  Future<void> putMember(String userId, FamilyMember member);

  /// Deletes the member and clears them off every expense that named them,
  /// matching the `on delete set null` on the server so the two copies agree.
  Future<void> removeMember(String userId, String memberId);

  /// Replaces the local copy of a table with what the server just returned,
  /// while leaving rows named in [keepKeys] alone — those have unsynced edits
  /// and must not be clobbered by older server data.
  Future<void> replaceExpenses(
    String userId,
    List<Expense> rows, {
    Set<String> keepKeys,
  });
  Future<void> replaceBudgets(
    String userId,
    List<Budget> rows, {
    Set<String> keepKeys,
  });
  Future<void> replaceIncomes(
    String userId,
    List<MonthlyIncome> rows, {
    Set<String> keepKeys,
  });
  Future<void> replaceProjects(
    String userId,
    List<Project> rows, {
    Set<String> keepKeys,
  });
  Future<void> replaceProjectEntries(
    String userId,
    List<ProjectEntry> rows, {
    Set<String> keepKeys,
  });
  Future<void> replaceMembers(
    String userId,
    List<FamilyMember> rows, {
    Set<String> keepKeys,
  });

  /// Queues a change for Supabase. A newer op for the same row replaces an
  /// older queued one, so a row edited five times offline pushes once.
  Future<void> enqueue(String userId, PendingOp op);
  Future<List<PendingOp>> pendingOps(String userId);
  Future<void> completeOp(String userId, int opId);
  Future<int> pendingCount(String userId);

  /// Throws away queued ops for rows that no longer exist.
  ///
  /// Deleting a project is the case that needs it: its entries go too, and a
  /// queued *insert* for one of them would otherwise be pushed after the
  /// project row is gone and be rejected by the foreign key.
  Future<void> dropQueued(String userId, SyncEntity entity, Set<String> keys);

  /// Everything belonging to this user, including the outbox.
  Future<void> clearUser(String userId);
}
