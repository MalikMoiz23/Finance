import 'dart:math' as math;

import '../core/formatters.dart';
import 'budget.dart';

/// Sentinel for the `copyWith`s below, so "leave this alone" is distinguishable
/// from "set this back to null".
const Object _keep = Object();

/// A one-off undertaking paid for out of savings — building a house, a wedding,
/// buying a car.
///
/// Projects are a **separate ledger**. Nothing here counts towards the daily
/// spending totals, a category budget, or the month's savings figure: this money
/// was put aside long before, so folding a Rs 92,500 brick order into March
/// would make an ordinary month look like a disaster.
class Project {
  Project({
    required this.id,
    required this.name,
    this.estimate,
    this.note = '',
    DateTime? startedOn,
    DateTime? createdAt,
  }) : startedOn = dayOnly(startedOn ?? DateTime.now()),
       createdAt = createdAt ?? DateTime.now();

  /// Generated on the device, so a project created offline keeps its identity
  /// when it finally reaches Supabase.
  final String id;

  final String name;

  /// What the whole job is expected to cost. Null when no target was given —
  /// the progress meter is then hidden rather than measured against a guess.
  final double? estimate;

  final String note;

  /// Day the work started, normalised to midnight.
  final DateTime startedOn;

  final DateTime createdAt;

  bool get hasEstimate => estimate != null && estimate! > 0;

  Project copyWith({
    String? name,
    Object? estimate = _keep,
    String? note,
    DateTime? startedOn,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      // Through `num`, so `copyWith(estimate: 250000)` — an int literal — is
      // accepted rather than failing the cast at run time.
      estimate: identical(estimate, _keep)
          ? this.estimate
          : (estimate as num?)?.toDouble(),
      note: note ?? this.note,
      startedOn: startedOn ?? this.startedOn,
      createdAt: createdAt,
    );
  }

  /// Snake case throughout, so one map serves both the device's database and
  /// the Supabase row without a second mapping step.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'estimate': estimate,
    'note': note,
    'started_on': _dateOnly(startedOn),
    'created_at': createdAt.toIso8601String(),
  };

  static Project? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = (json['name'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) return null;
    final estimate = _toDouble(json['estimate']);
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    return Project(
      id: id,
      name: name,
      estimate: estimate != null && estimate > 0 ? estimate : null,
      note: json['note'] as String? ?? '',
      startedOn:
          DateTime.tryParse(json['started_on'] as String? ?? '') ?? createdAt,
      createdAt: createdAt,
    );
  }
}

/// One line in a project's ledger.
///
/// Two shapes, one row. A **measured** buy — 5,000 bricks at Rs 18.50 — carries
/// quantity, unit and rate, and its amount is the product of the two. A **lump
/// sum** — the mason's wages for the week — carries only an amount. [amount] is
/// always stored either way, so every total is a plain sum and no report has to
/// know which shape it is reading.
class ProjectEntry {
  ProjectEntry({
    required this.id,
    required this.projectId,
    required this.stage,
    required this.amount,
    required DateTime date,
    this.quantity,
    this.unit = '',
    this.rate,
    this.note = '',
    DateTime? createdAt,
  }) : date = dayOnly(date),
       createdAt = createdAt ?? DateTime.now();

  /// A measured buy, with the amount derived rather than typed.
  factory ProjectEntry.measured({
    required String id,
    required String projectId,
    required String stage,
    required double quantity,
    required double rate,
    required DateTime date,
    String unit = '',
    String note = '',
    DateTime? createdAt,
  }) {
    return ProjectEntry(
      id: id,
      projectId: projectId,
      stage: stage,
      amount: totalOf(quantity, rate),
      quantity: quantity,
      unit: unit,
      rate: rate,
      date: date,
      note: note,
      createdAt: createdAt,
    );
  }

  final String id;
  final String projectId;

  /// Which part of the job this is — "Bricks", "Cement", "Mason labour". Free
  /// text, so a project can name its own stages; the breakdown groups on it.
  final String stage;

  final double amount;

  /// How many were bought. Null on a lump sum.
  final double? quantity;

  /// What [quantity] counts — "pieces", "bags", "trips". May be empty.
  final String unit;

  /// Price of one unit. Null on a lump sum.
  final double? rate;

  final DateTime date;
  final String note;
  final DateTime createdAt;

  /// Quantity times rate, rounded to the paisa so 3 x 0.1 cannot drift.
  static double totalOf(double quantity, double rate) =>
      (quantity * rate * 100).roundToDouble() / 100;

  bool get isMeasured => quantity != null && rate != null;

  /// `5,000 pieces × Rs 18.50`, or null for a lump sum.
  String? get measure {
    if (!isMeasured) return null;
    final count = Quantities.format(quantity!);
    final named = unit.trim().isEmpty ? count : '$count ${unit.trim()}';
    return '$named × ${Money.rate(rate!)}';
  }

  String get title => stage.trim().isEmpty ? 'Other' : stage.trim();

  ProjectEntry copyWith({
    String? stage,
    double? amount,
    Object? quantity = _keep,
    String? unit,
    Object? rate = _keep,
    DateTime? date,
    String? note,
  }) {
    return ProjectEntry(
      id: id,
      projectId: projectId,
      stage: stage ?? this.stage,
      amount: amount ?? this.amount,
      quantity: identical(quantity, _keep)
          ? this.quantity
          : (quantity as num?)?.toDouble(),
      unit: unit ?? this.unit,
      rate: identical(rate, _keep) ? this.rate : (rate as num?)?.toDouble(),
      date: date ?? this.date,
      note: note ?? this.note,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'stage': stage,
    'amount': amount,
    'quantity': quantity,
    'unit': unit,
    'rate': rate,
    'spent_on': _dateOnly(date),
    'note': note,
    'created_at': createdAt.toIso8601String(),
  };

  static ProjectEntry? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final projectId = json['project_id'] as String?;
    final amount = _toDouble(json['amount']);
    final date = DateTime.tryParse(json['spent_on'] as String? ?? '');
    if (id == null || projectId == null || amount == null || date == null) {
      return null;
    }
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    return ProjectEntry(
      id: id,
      projectId: projectId,
      stage: json['stage'] as String? ?? '',
      amount: amount,
      quantity: _toDouble(json['quantity']),
      unit: json['unit'] as String? ?? '',
      rate: _toDouble(json['rate']),
      date: date,
      note: json['note'] as String? ?? '',
      createdAt: createdAt ?? date,
    );
  }
}

/// What one stage of a project has cost so far.
class StageTotal {
  const StageTotal({
    required this.stage,
    required this.total,
    required this.count,
  });

  final String stage;
  final double total;
  final int count;

  double shareOf(double grandTotal) => grandTotal <= 0 ? 0 : total / grandTotal;
}

/// A project with its entries, and everything the screens read off them.
class ProjectSummary {
  ProjectSummary({required this.project, required List<ProjectEntry> entries})
    : entries = List.unmodifiable(entries);

  final Project project;

  /// Newest first.
  final List<ProjectEntry> entries;

  String get id => project.id;
  String get name => project.name;

  double get total => entries.fold<double>(0, (sum, e) => sum + e.amount);

  int get entryCount => entries.length;

  DateTime? get lastEntryDate => entries.isEmpty ? null : entries.first.date;

  double? get estimate => project.hasEstimate ? project.estimate : null;

  /// What is left of the estimate; negative once it is passed. Null when no
  /// estimate was set.
  double? get remaining {
    final target = estimate;
    return target == null ? null : target - total;
  }

  /// Share of the estimate used. Null without an estimate — an unset target
  /// must not read as 0% done.
  double? get progress {
    final target = estimate;
    return target == null ? null : total / target;
  }

  double get meterFraction => math.min(1, math.max(0, progress ?? 0));

  bool get overEstimate => (remaining ?? 0) < 0;

  /// Reuses the budget bands, so a project meter reads exactly like a budget
  /// meter — same thresholds, same colours, same icons.
  BudgetBand get band => switch (progress) {
    null => BudgetBand.onTrack,
    final p when p >= 1 => BudgetBand.overBudget,
    final p when p >= 0.8 => BudgetBand.closeToLimit,
    _ => BudgetBand.onTrack,
  };

  /// Wording for [band] in project terms: a project passes an *estimate*, not a
  /// monthly limit.
  String get bandLabel => switch (band) {
    BudgetBand.onTrack => 'Within the estimate',
    BudgetBand.closeToLimit => 'Close to the estimate',
    BudgetBand.overBudget => 'Over the estimate',
  };

  /// Totals per stage, biggest first. Stages differing only in case are one
  /// row, labelled the way they were first written.
  List<StageTotal> get byStage {
    final byKey = <String, ({String label, double total, int count})>{};
    for (final entry in entries) {
      final label = entry.title;
      final key = label.toLowerCase();
      final seen = byKey[key];
      byKey[key] = (
        label: seen?.label ?? label,
        total: (seen?.total ?? 0) + entry.amount,
        count: (seen?.count ?? 0) + 1,
      );
    }
    return byKey.values
        .map((v) => StageTotal(stage: v.label, total: v.total, count: v.count))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Stage names already used here, biggest spend first — offered before the
  /// built-in list when adding an entry.
  List<String> get usedStages => byStage.map((s) => s.stage).toList();

  /// Entries grouped by day, newest day first, for the ledger list.
  List<({DateTime day, List<ProjectEntry> entries, double total})>
  get byDay {
    final byDate = <DateTime, List<ProjectEntry>>{};
    for (final entry in entries) {
      byDate.putIfAbsent(entry.date, () => []).add(entry);
    }
    final days = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        (
          day: day,
          entries: byDate[day]!,
          total: byDate[day]!.fold<double>(0, (sum, e) => sum + e.amount),
        ),
    ];
  }
}

String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// PostgREST serialises `numeric` as a number or a string depending on the
/// driver; accept both, and treat anything else as absent.
double? _toDouble(Object? value) => switch (value) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};
