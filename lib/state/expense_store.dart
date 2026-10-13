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
import '../data/member_api.dart';
import '../data/project_api.dart';
import '../data/vehicle_api.dart';
import '../models/analytics.dart';
import '../models/app_user.dart';
import '../models/budget.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/family_member.dart';
import '../models/income.dart';
import '../models/item_catalog.dart';
import '../models/period.dart';
import '../models/project.dart';
import '../models/vehicle.dart';

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
    required ProjectApi projectApi,
    required MemberApi memberApi,
    required VehicleApi vehicleApi,
    required LocalDb localDb,
    Stream<bool>? onlineChanges,
  }) : _api = api,
       _budgetApi = budgetApi,
       _incomeApi = incomeApi,
       _projectApi = projectApi,
       _memberApi = memberApi,
       _vehicleApi = vehicleApi,
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
  final ProjectApi _projectApi;
  final MemberApi _memberApi;
  final VehicleApi _vehicleApi;
  final LocalDb _local;
  static const _uuid = Uuid();

  late final StreamSubscription<bool> _connection;

  final List<Expense> _expenses = [];
  final List<Budget> _budgets = [];
  final List<MonthlyIncome> _incomes = [];
  final List<Project> _projects = [];
  final List<ProjectEntry> _projectEntries = [];
  final List<FamilyMember> _members = [];
  final List<Vehicle> _vehicles = [];
  final List<VehicleService> _vehicleServices = [];
  Period _period = Period.month;
  late DateTime _anchor;
  late PeriodSummary _summary;
  List<ProjectSummary> _projectSummaries = const [];
  List<VehicleSummary> _vehicleSummaries = const [];

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

  // -------------------------------------------------------------- projects ---
  //
  // A separate ledger, on purpose. None of the figures above look at a project:
  // this money left the savings that earlier months built up, so counting a
  // Rs 92,500 brick order as March spending would make an ordinary month read
  // as a disaster and would blow every category budget at once.

  /// Every project with its entries, most recently worked on first.
  List<ProjectSummary> get projects => _projectSummaries;

  bool get hasProjects => _projectSummaries.isNotEmpty;

  ProjectSummary? projectById(String id) =>
      _projectSummaries.where((p) => p.id == id).firstOrNull;

  /// Everything spent across every project, ever. Counted off the summaries so
  /// an entry orphaned by a pull cannot inflate a total nothing displays.
  double get projectsTotal =>
      _projectSummaries.fold<double>(0, (sum, p) => sum + p.total);

  int get projectEntryCount =>
      _projectSummaries.fold<int>(0, (sum, p) => sum + p.entryCount);

  /// Creates a project and returns it, so the caller can open it straight away.
  Future<Project> createProject({
    required String name,
    double? estimate,
    String note = '',
    DateTime? startedOn,
  }) async {
    final project = Project(
      // Generated here, not by the server, so a project started offline keeps
      // its identity — and its entries keep pointing at it — once it syncs.
      id: _uuid.v4(),
      name: name.trim(),
      estimate: estimate != null && estimate > 0 ? estimate : null,
      note: note.trim(),
      startedOn: startedOn,
    );
    await saveProject(project);
    return project;
  }

  Future<void> saveProject(Project project) async {
    final userId = _requireUser();
    await _local.putProject(userId, project);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.project,
        action: SyncAction.upsert,
        key: project.id,
        payload: project.toJson(),
      ),
    );
    final index = _projects.indexWhere((p) => p.id == project.id);
    if (index == -1) {
      _projects.add(project);
    } else {
      _projects[index] = project;
    }
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  /// Deletes a project and everything logged against it.
  Future<void> deleteProject(String projectId) async {
    final userId = _requireUser();
    final entryIds = _projectEntries
        .where((e) => e.projectId == projectId)
        .map((e) => e.id)
        .toSet();

    await _local.removeProject(userId, projectId);
    // Those entries are gone. A queued insert for one of them would be pushed
    // after the project row is deleted and rejected by the foreign key, so the
    // op is thrown away rather than left to poison the queue. A queued *project*
    // op needs no such care: the delete below replaces it by key.
    await _local.dropQueued(userId, SyncEntity.projectEntry, entryIds);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.project,
        action: SyncAction.delete,
        key: projectId,
        payload: {'id': projectId},
      ),
    );

    _projects.removeWhere((p) => p.id == projectId);
    _projectEntries.removeWhere((e) => e.projectId == projectId);
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  /// Adds a line to a project.
  ///
  /// Pass [quantity] and [rate] together for a measured buy — 5,000 bricks at
  /// Rs 18.50 — and the amount is recomputed from them. Pass neither for a lump
  /// sum, where [amount] is what was paid.
  Future<ProjectEntry> addProjectEntry({
    required String projectId,
    required String stage,
    required double amount,
    required DateTime date,
    double? quantity,
    String unit = '',
    double? rate,
    String note = '',
  }) async {
    final measured = quantity != null && rate != null;
    final entry = ProjectEntry(
      id: _uuid.v4(),
      projectId: projectId,
      stage: stage.trim(),
      // Recomputed rather than taken on trust, so the stored amount can never
      // disagree with the quantity and rate shown beside it.
      amount: measured ? ProjectEntry.totalOf(quantity, rate) : amount,
      quantity: measured ? quantity : null,
      unit: measured ? unit.trim() : '',
      rate: measured ? rate : null,
      date: date,
      note: note.trim(),
    );
    await saveProjectEntry(entry);
    return entry;
  }

  Future<void> saveProjectEntry(ProjectEntry entry) async {
    final userId = _requireUser();
    await _local.putProjectEntry(userId, entry);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.projectEntry,
        action: SyncAction.upsert,
        key: entry.id,
        payload: entry.toJson(),
      ),
    );
    final index = _projectEntries.indexWhere((e) => e.id == entry.id);
    if (index == -1) {
      _projectEntries.add(entry);
    } else {
      _projectEntries[index] = entry;
    }
    _sortProjectEntries();
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  Future<void> deleteProjectEntry(String entryId) async {
    final userId = _requireUser();
    await _local.removeProjectEntry(userId, entryId);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.projectEntry,
        action: SyncAction.delete,
        key: entryId,
        payload: {'id': entryId},
      ),
    );
    _projectEntries.removeWhere((e) => e.id == entryId);
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  /// Undo for a deleted entry: written back as a new row.
  Future<void> restoreProjectEntry(ProjectEntry entry) => addProjectEntry(
    projectId: entry.projectId,
    stage: entry.stage,
    amount: entry.amount,
    date: entry.date,
    quantity: entry.quantity,
    unit: entry.unit,
    rate: entry.rate,
    note: entry.note,
  );

  // ------------------------------------------------------------- vehicles ---
  //
  // The third ledger. Tuning and service costs are deliberately kept out of
  // every figure above, the same way projects are: this is a maintenance
  // logbook whose job is to say what was done, at what reading, and when it is
  // due again — not to make the month of a big service look like a disaster.

  /// Every vehicle with its history, in the order they were added.
  List<VehicleSummary> get vehicles => _vehicleSummaries;

  bool get hasVehicles => _vehicleSummaries.isNotEmpty;

  VehicleSummary? vehicleById(String id) =>
      _vehicleSummaries.where((v) => v.id == id).firstOrNull;

  /// Everything spent on every vehicle's servicing, ever.
  double get vehiclesTotalCost =>
      _vehicleSummaries.fold<double>(0, (sum, v) => sum + v.totalCost);

  int get vehicleServiceCount =>
      _vehicleSummaries.fold<int>(0, (sum, v) => sum + v.serviceCount);

  /// Jobs that are overdue or close to it, across every vehicle, most urgent
  /// first. What the Overview reminder lists.
  List<({VehicleSummary vehicle, ServiceDue due})> get vehicleAttention {
    final out = [
      for (final vehicle in _vehicleSummaries)
        for (final due in vehicle.dues)
          if (due.status != DueStatus.ok) (vehicle: vehicle, due: due),
    ];
    out.sort((a, b) => ServiceDue.compare(a.due, b.due));
    return out;
  }

  Future<Vehicle> createVehicle({
    required String name,
    required VehicleKind kind,
    String plate = '',
    int odometer = 0,
    String note = '',
  }) async {
    final vehicle = Vehicle(
      // Generated here so a vehicle added offline keeps its identity — and its
      // service records keep pointing at it — once it syncs.
      id: _uuid.v4(),
      name: name.trim(),
      kind: kind,
      plate: plate.trim(),
      odometer: odometer < 0 ? 0 : odometer,
      note: note.trim(),
    );
    await saveVehicle(vehicle);
    return vehicle;
  }

  Future<void> saveVehicle(Vehicle vehicle) async {
    final userId = _requireUser();
    await _local.putVehicle(userId, vehicle);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.vehicle,
        action: SyncAction.upsert,
        key: vehicle.id,
        payload: vehicle.toJson(),
      ),
    );
    final index = _vehicles.indexWhere((v) => v.id == vehicle.id);
    if (index == -1) {
      _vehicles.add(vehicle);
    } else {
      _vehicles[index] = vehicle;
    }
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  /// Deletes a vehicle and its whole service history.
  Future<void> deleteVehicle(String vehicleId) async {
    final userId = _requireUser();
    final serviceIds = _vehicleServices
        .where((s) => s.vehicleId == vehicleId)
        .map((s) => s.id)
        .toSet();

    await _local.removeVehicle(userId, vehicleId);
    // Same reasoning as deleteProject: a queued insert for one of these would
    // reach the server after the vehicle is gone and be refused by the key.
    await _local.dropQueued(userId, SyncEntity.vehicleService, serviceIds);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.vehicle,
        action: SyncAction.delete,
        key: vehicleId,
        payload: {'id': vehicleId},
      ),
    );

    _vehicles.removeWhere((v) => v.id == vehicleId);
    _vehicleServices.removeWhere((s) => s.vehicleId == vehicleId);
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  Future<VehicleService> addVehicleService({
    required String vehicleId,
    required String service,
    required DateTime date,
    required int odometer,
    double cost = 0,
    int? intervalKm,
    int? intervalMonths,
    String workshop = '',
    String note = '',
  }) async {
    final record = VehicleService(
      id: _uuid.v4(),
      vehicleId: vehicleId,
      service: service.trim(),
      date: date,
      odometer: odometer,
      cost: cost < 0 ? 0 : cost,
      intervalKm: intervalKm != null && intervalKm > 0 ? intervalKm : null,
      intervalMonths: intervalMonths != null && intervalMonths > 0
          ? intervalMonths
          : null,
      workshop: workshop.trim(),
      note: note.trim(),
    );
    await saveVehicleService(record);
    return record;
  }

  Future<void> saveVehicleService(VehicleService record) async {
    final userId = _requireUser();
    await _local.putVehicleService(userId, record);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.vehicleService,
        action: SyncAction.upsert,
        key: record.id,
        payload: record.toJson(),
      ),
    );
    final index = _vehicleServices.indexWhere((s) => s.id == record.id);
    if (index == -1) {
      _vehicleServices.add(record);
    } else {
      _vehicleServices[index] = record;
    }
    _sortVehicleServices();
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  Future<void> deleteVehicleService(String serviceId) async {
    final userId = _requireUser();
    await _local.removeVehicleService(userId, serviceId);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.vehicleService,
        action: SyncAction.delete,
        key: serviceId,
        payload: {'id': serviceId},
      ),
    );
    _vehicleServices.removeWhere((s) => s.id == serviceId);
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  /// Undo for a deleted record: written back as it was.
  Future<void> restoreVehicleService(VehicleService record) =>
      saveVehicleService(record);

  // --------------------------------------------------------------- family ---
  //
  // One login for the whole house, so a member is a label rather than an
  // account. Nothing here is a security boundary: whoever holds the phone can
  // add, rename or remove any of them, and can log spending as any of them.
  // That is the point — it answers "who spent it", not "who is allowed to".

  List<FamilyMember> get members => List.unmodifiable(_members);

  bool get hasMembers => _members.isNotEmpty;

  FamilyMember? memberById(String? id) =>
      id == null ? null : _members.where((m) => m.id == id).firstOrNull;

  /// Name for a row in a list. Falls back rather than showing a raw id when the
  /// member has been deleted out from under an expense.
  String memberNameFor(String? id) => memberById(id)?.name ?? 'Not set';

  /// True when [name] is already taken, ignoring case and surrounding spaces.
  /// [exceptId] lets a rename keep its own name.
  bool memberNameTaken(String name, {String? exceptId}) {
    final key = name.trim().toLowerCase();
    return _members.any((m) => m.id != exceptId && m.name.toLowerCase() == key);
  }

  /// Who spent what over [expenses], biggest first, with the unattributed
  /// total last. Pass `summary.expenses` for the selected period, or
  /// [allExpenses] for all time.
  List<MemberSpend> spendByMember(List<Expense> expenses) {
    final totals = <String, ({double total, int count})>{};
    var unassignedTotal = 0.0;
    var unassignedCount = 0;

    for (final expense in expenses) {
      final id = expense.memberId;
      // An id pointing at a member who no longer exists counts as unattributed
      // rather than conjuring a row with no name.
      if (id == null || memberById(id) == null) {
        unassignedTotal += expense.amount;
        unassignedCount++;
        continue;
      }
      final seen = totals[id];
      totals[id] = (
        total: (seen?.total ?? 0) + expense.amount,
        count: (seen?.count ?? 0) + 1,
      );
    }

    final rows =
        totals.entries
            .map(
              (e) => MemberSpend(
                member: memberById(e.key),
                total: e.value.total,
                count: e.value.count,
              ),
            )
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));

    if (unassignedCount > 0) {
      rows.add(
        MemberSpend(
          member: null,
          total: unassignedTotal,
          count: unassignedCount,
        ),
      );
    }
    return rows;
  }

  /// The per-person split for the period currently on screen.
  List<MemberSpend> get spendByMemberThisPeriod =>
      spendByMember(_summary.expenses);

  /// How many expenses have nobody attached — the ones logged before the family
  /// was set up.
  int get unassignedExpenseCount => _expenses
      .where((e) => e.memberId == null || memberById(e.memberId) == null)
      .length;

  Future<FamilyMember> addMember(String name) async {
    final member = FamilyMember(id: _uuid.v4(), name: name.trim());
    await saveMember(member);
    return member;
  }

  Future<void> saveMember(FamilyMember member) async {
    final userId = _requireUser();
    await _local.putMember(userId, member);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.member,
        action: SyncAction.upsert,
        key: member.id,
        payload: member.toJson(),
      ),
    );
    final index = _members.indexWhere((m) => m.id == member.id);
    if (index == -1) {
      _members.add(member);
    } else {
      _members[index] = member;
    }
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  /// Removes a member. Their expenses stay, with nobody attached.
  Future<void> deleteMember(String memberId) async {
    final userId = _requireUser();

    // Clear the member off their expenses first, and re-queue each one, so the
    // server is told the new value by an op that is already ahead of the member
    // delete in the queue. Relying on the server's own `on delete set null`
    // would not be enough: a queued upsert still carrying the old member id
    // would be rejected by the foreign key once the member row is gone.
    final theirs = _expenses.where((e) => e.memberId == memberId).toList();
    for (final expense in theirs) {
      final cleared = expense.copyWith(memberId: null);
      await _local.putExpense(userId, cleared);
      await _local.enqueue(
        userId,
        PendingOp(
          entity: SyncEntity.expense,
          action: SyncAction.upsert,
          key: cleared.id,
          payload: cleared.toJson(),
        ),
      );
      _expenses[_expenses.indexWhere((e) => e.id == expense.id)] = cleared;
    }

    await _local.removeMember(userId, memberId);
    await _local.enqueue(
      userId,
      PendingOp(
        entity: SyncEntity.member,
        action: SyncAction.delete,
        key: memberId,
        payload: {'id': memberId},
      ),
    );
    _members.removeWhere((m) => m.id == memberId);
    _pending = await _local.pendingCount(userId);
    _refresh();
    _syncSoon();
  }

  /// How many expenses name this member — what a delete confirmation needs.
  int expenseCountFor(String memberId) =>
      _expenses.where((e) => e.memberId == memberId).length;

  double spentBy(String memberId) => _expenses
      .where((e) => e.memberId == memberId)
      .fold<double>(0, (sum, e) => sum + e.amount);

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
      _projects.clear();
      _projectEntries.clear();
      _members.clear();
      _vehicles.clear();
      _vehicleServices.clear();
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
    _projects.clear();
    _projectEntries.clear();
    _members.clear();
    _vehicles.clear();
    _vehicleServices.clear();
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
    final projects = await _local.readProjects(userId);
    final projectEntries = await _local.readProjectEntries(userId);
    final members = await _local.readMembers(userId);
    final vehicles = await _local.readVehicles(userId);
    final vehicleServices = await _local.readVehicleServices(userId);
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
    _projects
      ..clear()
      ..addAll(projects);
    _projectEntries
      ..clear()
      ..addAll(projectEntries);
    _members
      ..clear()
      ..addAll(members);
    _vehicles
      ..clear()
      ..addAll(vehicles);
    _vehicleServices
      ..clear()
      ..addAll(vehicleServices);
    _sort();
    _sortProjectEntries();
    _sortVehicleServices();
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
    final queued = await _local.pendingOps(userId);
    // Rows other rows point at go first, and their deletes go last; everything
    // in between keeps its queued order.
    //
    // Both halves are needed. Collapsing a repeated edit moves that row's op to
    // the back of the queue, so editing a project *after* adding an entry to it
    // would push the entry first and the server would reject it — the project
    // it names is not there yet. And a member delete has to come after the
    // expense upserts that clear them off, or those upserts arrive still
    // naming a member the server has already dropped.
    bool isParent(PendingOp op) =>
        op.entity == SyncEntity.project ||
        op.entity == SyncEntity.member ||
        op.entity == SyncEntity.vehicle;
    final ops = [
      ...queued.where((o) => isParent(o) && o.action != SyncAction.delete),
      ...queued.where((o) => !isParent(o)),
      ...queued.where((o) => isParent(o) && o.action == SyncAction.delete),
    ];
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
        case (SyncEntity.project, SyncAction.upsert):
          final project = op.project;
          if (project != null) await _projectApi.upsertProject(project);
        case (SyncEntity.project, SyncAction.delete):
          await _projectApi.deleteProject(op.key);
        case (SyncEntity.projectEntry, SyncAction.upsert):
          final entry = op.projectEntry;
          if (entry != null) await _projectApi.upsertEntry(entry);
        case (SyncEntity.projectEntry, SyncAction.delete):
          await _projectApi.deleteEntry(op.key);
        case (SyncEntity.member, SyncAction.upsert):
          final member = op.member;
          if (member != null) await _memberApi.upsert(member);
        case (SyncEntity.member, SyncAction.delete):
          await _memberApi.delete(op.key);
        case (SyncEntity.vehicle, SyncAction.upsert):
          final vehicle = op.vehicle;
          if (vehicle != null) await _vehicleApi.upsertVehicle(vehicle);
        case (SyncEntity.vehicle, SyncAction.delete):
          await _vehicleApi.deleteVehicle(op.key);
        case (SyncEntity.vehicleService, SyncAction.upsert):
          final record = op.vehicleService;
          if (record != null) await _vehicleApi.upsertService(record);
        case (SyncEntity.vehicleService, SyncAction.delete):
          await _vehicleApi.deleteService(op.key);
        case (SyncEntity.project, SyncAction.deleteAll):
        case (SyncEntity.projectEntry, SyncAction.deleteAll):
        case (SyncEntity.member, SyncAction.deleteAll):
        case (SyncEntity.vehicle, SyncAction.deleteAll):
        case (SyncEntity.vehicleService, SyncAction.deleteAll):
          break; // projects, people and vehicles are removed one at a time
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
    final remoteProjects = await _projectApi.fetchProjects();
    final remoteEntries = await _projectApi.fetchEntries();
    final remoteMembers = await _memberApi.fetchAll();
    final remoteVehicles = await _vehicleApi.fetchVehicles();
    final remoteServices = await _vehicleApi.fetchServices();
    if (_userId != userId) return;

    final ops = await _local.pendingOps(userId);
    Set<String> keys(SyncEntity entity) => ops
        .where((o) => o.entity == entity && o.key.isNotEmpty)
        .map((o) => o.key)
        .toSet();

    // People before expenses, so a pulled expense never briefly names someone
    // the local copy has not heard of.
    await _local.replaceMembers(
      userId,
      remoteMembers,
      keepKeys: keys(SyncEntity.member),
    );
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
    // Projects before their entries, so the local copy is never briefly a set
    // of lines with nothing to belong to.
    await _local.replaceProjects(
      userId,
      remoteProjects,
      keepKeys: keys(SyncEntity.project),
    );
    await _local.replaceProjectEntries(
      userId,
      remoteEntries,
      keepKeys: keys(SyncEntity.projectEntry),
    );
    // Vehicles before their history, for the same reason as projects.
    await _local.replaceVehicles(
      userId,
      remoteVehicles,
      keepKeys: keys(SyncEntity.vehicle),
    );
    await _local.replaceVehicleServices(
      userId,
      remoteServices,
      keepKeys: keys(SyncEntity.vehicleService),
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
    String? memberId,
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
      memberId: memberId,
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
    memberId: expense.memberId,
  );

  /// Copies an existing expense onto today.
  Future<void> duplicate(Expense expense) => create(
    amount: expense.amount,
    category: expense.category,
    date: dayOnly(DateTime.now()),
    item: expense.item,
    note: expense.note,
    memberId: expense.memberId,
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

  void _sortProjectEntries() {
    _projectEntries.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
  }

  void _sortVehicleServices() {
    _vehicleServices.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      final byKm = b.odometer.compareTo(a.odometer);
      return byKm != 0 ? byKm : b.createdAt.compareTo(a.createdAt);
    });
  }

  PeriodSummary _compute() => Analytics.summarize(
    all: _expenses,
    period: _period,
    anchor: _anchor,
    now: DateTime.now(),
  );

  /// Pairs each project with its entries. Built once per change rather than per
  /// `build`, the same way the period summary is.
  List<ProjectSummary> _computeProjects() {
    if (_projects.isEmpty) return const [];
    final byProject = <String, List<ProjectEntry>>{};
    for (final entry in _projectEntries) {
      byProject.putIfAbsent(entry.projectId, () => []).add(entry);
    }
    final summaries = [
      for (final project in _projects)
        ProjectSummary(
          project: project,
          entries: byProject[project.id] ?? const [],
        ),
    ];
    // Most recently worked on first — the one being built is the one you open.
    summaries.sort((a, b) {
      final aWhen = a.lastEntryDate ?? a.project.startedOn;
      final bWhen = b.lastEntryDate ?? b.project.startedOn;
      final byWhen = bWhen.compareTo(aWhen);
      if (byWhen != 0) return byWhen;
      return b.project.createdAt.compareTo(a.project.createdAt);
    });
    return summaries;
  }

  /// Pairs each vehicle with its history, measured against today.
  List<VehicleSummary> _computeVehicles() {
    if (_vehicles.isEmpty) return const [];
    final byVehicle = <String, List<VehicleService>>{};
    for (final record in _vehicleServices) {
      byVehicle.putIfAbsent(record.vehicleId, () => []).add(record);
    }
    final today = DateTime.now();
    return [
      for (final vehicle in _vehicles)
        VehicleSummary(
          vehicle: vehicle,
          services: byVehicle[vehicle.id] ?? const [],
          today: today,
        ),
    ];
  }

  void _refresh() {
    _summary = _compute();
    _projectSummaries = _computeProjects();
    _vehicleSummaries = _computeVehicles();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connection.cancel();
    super.dispose();
  }
}
