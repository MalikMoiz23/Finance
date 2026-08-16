import 'package:finance/models/budget.dart';
import 'package:finance/models/project.dart';
import 'package:finance/models/project_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectEntry _entry({
  required String id,
  required String stage,
  required double amount,
  DateTime? date,
  double? quantity,
  String unit = '',
  double? rate,
}) {
  return ProjectEntry(
    id: id,
    projectId: 'p1',
    stage: stage,
    amount: amount,
    quantity: quantity,
    unit: unit,
    rate: rate,
    date: date ?? DateTime(2026, 8, 12),
  );
}

void main() {
  group('measured entries', () {
    test('the total is quantity times rate, to the paisa', () {
      expect(ProjectEntry.totalOf(5000, 18.5), 92500);
      expect(ProjectEntry.totalOf(40, 1300), 52000);
      // Rounded rather than left as 0.30000000000000004.
      expect(ProjectEntry.totalOf(3, 0.1), 0.3);
      expect(ProjectEntry.totalOf(1234, 56.78), 70066.52);
    });

    test('a measured entry spells out the arithmetic', () {
      final entry = ProjectEntry.measured(
        id: 'e1',
        projectId: 'p1',
        stage: 'Bricks',
        quantity: 5000,
        rate: 18.5,
        unit: 'pieces',
        date: DateTime(2026, 8, 12),
      );
      expect(entry.amount, 92500);
      expect(entry.isMeasured, isTrue);
      expect(entry.measure, '5,000 pieces × Rs 18.50');
    });

    test('a whole rate keeps no decimals, a fractional one keeps two', () {
      final whole = ProjectEntry.measured(
        id: 'e1',
        projectId: 'p1',
        stage: 'Cement',
        quantity: 40,
        rate: 1300,
        unit: 'bags',
        date: DateTime(2026, 8, 12),
      );
      expect(whole.measure, '40 bags × Rs 1,300');
    });

    test('a lump sum has no quantity, rate or arithmetic line', () {
      final entry = _entry(id: 'e2', stage: 'Mason labour', amount: 18900);
      expect(entry.isMeasured, isFalse);
      expect(entry.measure, isNull);
    });
  });

  group('project summary', () {
    Project house({double? estimate}) =>
        Project(id: 'p1', name: 'House', estimate: estimate);

    test('totals every entry regardless of shape', () {
      final summary = ProjectSummary(
        project: house(),
        entries: [
          _entry(
            id: 'e1',
            stage: 'Bricks',
            amount: 92500,
            quantity: 5000,
            rate: 18.5,
          ),
          _entry(id: 'e2', stage: 'Mason labour', amount: 18900),
        ],
      );
      expect(summary.total, 111400);
      expect(summary.entryCount, 2);
    });

    test('no estimate means no progress, not zero progress', () {
      final summary = ProjectSummary(
        project: house(),
        entries: [_entry(id: 'e1', stage: 'Bricks', amount: 92500)],
      );
      expect(summary.estimate, isNull);
      expect(summary.progress, isNull);
      expect(summary.remaining, isNull);
      expect(summary.overEstimate, isFalse);
      expect(summary.meterFraction, 0);
      expect(summary.band, BudgetBand.onTrack);
    });

    test('bands follow the same thresholds as a budget', () {
      ProjectSummary at(double spent) => ProjectSummary(
        project: house(estimate: 100000),
        entries: [_entry(id: 'e1', stage: 'Bricks', amount: spent)],
      );
      expect(at(50000).band, BudgetBand.onTrack);
      expect(at(79999).band, BudgetBand.onTrack);
      expect(at(80000).band, BudgetBand.closeToLimit);
      expect(at(99999).band, BudgetBand.closeToLimit);
      expect(at(100000).band, BudgetBand.overBudget);
      expect(at(140000).band, BudgetBand.overBudget);
    });

    test('past the estimate the remainder goes negative, the meter stays 1', () {
      final summary = ProjectSummary(
        project: house(estimate: 100000),
        entries: [_entry(id: 'e1', stage: 'Bricks', amount: 140000)],
      );
      expect(summary.remaining, -40000);
      expect(summary.overEstimate, isTrue);
      expect(summary.meterFraction, 1);
      expect(summary.progress, 1.4);
      expect(summary.bandLabel, 'Over the estimate');
    });

    test('stages group biggest first, ignoring case', () {
      final summary = ProjectSummary(
        project: house(),
        entries: [
          _entry(id: 'e1', stage: 'Bricks', amount: 60000),
          _entry(id: 'e2', stage: 'bricks', amount: 32500),
          _entry(id: 'e3', stage: 'Cement', amount: 24500),
          _entry(id: 'e4', stage: '', amount: 1000),
        ],
      );
      final stages = summary.byStage;
      expect(stages.map((s) => s.stage).toList(), [
        'Bricks',
        'Cement',
        'Other',
      ]);
      expect(stages.first.total, 92500);
      expect(stages.first.count, 2);
      expect(stages.first.shareOf(summary.total), closeTo(0.7838, 0.0001));
      expect(summary.usedStages.first, 'Bricks');
    });

    test('entries group by day, newest day first', () {
      final summary = ProjectSummary(
        project: house(),
        entries: [
          _entry(
            id: 'e1',
            stage: 'Bricks',
            amount: 1000,
            date: DateTime(2026, 8, 12),
          ),
          _entry(
            id: 'e2',
            stage: 'Cement',
            amount: 500,
            date: DateTime(2026, 8, 12),
          ),
          _entry(
            id: 'e3',
            stage: 'Sand',
            amount: 300,
            date: DateTime(2026, 8, 9),
          ),
        ],
      );
      final days = summary.byDay;
      expect(days.length, 2);
      expect(days.first.day, DateTime(2026, 8, 12));
      expect(days.first.total, 1500);
      expect(days.first.entries.length, 2);
      expect(days.last.total, 300);
    });

    test('an empty project totals zero rather than throwing', () {
      final summary = ProjectSummary(project: house(), entries: const []);
      expect(summary.total, 0);
      expect(summary.byStage, isEmpty);
      expect(summary.byDay, isEmpty);
      expect(summary.lastEntryDate, isNull);
    });
  });

  group('serialisation', () {
    test('a project survives a round trip', () {
      final original = Project(
        id: 'p1',
        name: 'Building a house',
        estimate: 2500000,
        note: '5 marla',
        startedOn: DateTime(2026, 3, 4),
      );
      final copy = Project.fromJson(original.toJson())!;
      expect(copy.id, original.id);
      expect(copy.name, original.name);
      expect(copy.estimate, original.estimate);
      expect(copy.note, original.note);
      expect(copy.startedOn, DateTime(2026, 3, 4));
    });

    test('an entry survives a round trip, keeping quantity and rate', () {
      final original = ProjectEntry.measured(
        id: 'e1',
        projectId: 'p1',
        stage: 'Bricks',
        quantity: 5000,
        rate: 18.5,
        unit: 'pieces',
        date: DateTime(2026, 8, 12),
        note: 'Awan bhatta',
      );
      final copy = ProjectEntry.fromJson(original.toJson())!;
      expect(copy.id, 'e1');
      expect(copy.projectId, 'p1');
      expect(copy.stage, 'Bricks');
      expect(copy.amount, 92500);
      expect(copy.quantity, 5000);
      expect(copy.unit, 'pieces');
      expect(copy.rate, 18.5);
      expect(copy.date, DateTime(2026, 8, 12));
      expect(copy.note, 'Awan bhatta');
    });

    test('numeric columns arriving as strings are still read', () {
      final entry = ProjectEntry.fromJson({
        'id': 'e1',
        'project_id': 'p1',
        'stage': 'Cement',
        'amount': '52000.00',
        'quantity': '40',
        'unit': 'bags',
        'rate': '1300.0000',
        'spent_on': '2026-08-12',
        'note': '',
        'created_at': '2026-08-12T10:00:00.000Z',
      })!;
      expect(entry.amount, 52000);
      expect(entry.quantity, 40);
      expect(entry.rate, 1300);
    });

    test('rows missing what a project needs are dropped, not guessed at', () {
      expect(Project.fromJson({'name': 'No id'}), isNull);
      expect(Project.fromJson({'id': 'p1', 'name': '   '}), isNull);
      expect(
        Project.fromJson({'id': 'p1', 'name': 'x', 'estimate': 0})?.estimate,
        isNull,
      );
      expect(
        ProjectEntry.fromJson({'id': 'e1', 'amount': 10}),
        isNull,
        reason: 'no project_id and no date',
      );
    });

    test('clearing an estimate is distinguishable from leaving it alone', () {
      final withEstimate = Project(id: 'p1', name: 'House', estimate: 100);
      expect(withEstimate.copyWith(name: 'Home').estimate, 100);
      expect(withEstimate.copyWith(estimate: null).estimate, isNull);
    });
  });

  group('stage suggestions', () {
    test('the project own stages come before the built-in list', () {
      final out = ProjectCatalog.suggestStages(
        query: 'c',
        used: ['Crane hire', 'Cement'],
      );
      expect(out.take(2).toList(), ['Crane hire', 'Cement']);
    });

    test('prefix matches outrank substring matches', () {
      final out = ProjectCatalog.suggestStages(query: 'pl', used: const []);
      expect(out.first, anyOf('Plaster', 'Plumbing', 'Plumber'));
      expect(out.contains('Slab / roof'), isFalse);
    });

    test('an empty query offers this project first, then the catalogue', () {
      final out = ProjectCatalog.suggestStages(
        query: '  ',
        used: ['Bricks'],
        limit: 3,
      );
      expect(out.first, 'Bricks');
      expect(out.length, 3);
      expect(out.toSet().length, 3, reason: 'no duplicate of Bricks');
    });

    test('common materials come with the unit they are bought in', () {
      expect(ProjectCatalog.unitFor('Cement'), 'bags');
      expect(ProjectCatalog.unitFor('bricks'), 'pieces');
      expect(ProjectCatalog.unitFor('Sand'), 'trips');
      expect(ProjectCatalog.unitFor('Mason labour'), 'days');
      expect(ProjectCatalog.unitFor('Something else'), isNull);
    });
  });
}
