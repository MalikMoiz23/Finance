import 'package:finance/models/service_catalog.dart';
import 'package:finance/models/vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

VehicleService _service({
  required String id,
  String service = 'Tuning',
  DateTime? date,
  int odometer = 10000,
  double cost = 0,
  int? intervalKm,
  int? intervalMonths,
}) {
  return VehicleService(
    id: id,
    vehicleId: 'v1',
    service: service,
    date: date ?? DateTime(2026, 6, 1),
    odometer: odometer,
    cost: cost,
    intervalKm: intervalKm,
    intervalMonths: intervalMonths,
  );
}

VehicleSummary _summary(
  List<VehicleService> services, {
  int odometer = 0,
  DateTime? today,
}) {
  return VehicleSummary(
    vehicle: Vehicle(id: 'v1', name: 'City', odometer: odometer),
    services: services,
    today: today ?? DateTime(2026, 7, 1),
  );
}

void main() {
  group('next due', () {
    test('distance and time are both counted from the service', () {
      final record = _service(
        id: 's1',
        odometer: 42000,
        intervalKm: 5000,
        intervalMonths: 6,
      );
      expect(record.nextDueKm, 47000);
      expect(record.nextDueDate, DateTime(2026, 12, 1));
    });

    test('a month interval clamps to the end of a shorter month', () {
      expect(
        VehicleService.addMonths(DateTime(2026, 1, 31), 1),
        DateTime(2026, 2, 28),
      );
      expect(
        VehicleService.addMonths(DateTime(2028, 1, 31), 1),
        DateTime(2028, 2, 29),
      );
      expect(
        VehicleService.addMonths(DateTime(2026, 11, 15), 3),
        DateTime(2027, 2, 15),
      );
    });

    test('with no interval nothing is ever due', () {
      final record = _service(id: 's1');
      expect(record.hasInterval, isFalse);
      expect(record.nextDueKm, isNull);
      expect(record.nextDueDate, isNull);
      expect(_summary([record]).dues, isEmpty);
    });
  });

  group('due status', () {
    test('whichever limit runs out first decides', () {
      // Plenty of time left, but the km are used up.
      final byKm = _summary([
        _service(
          id: 's1',
          odometer: 10000,
          intervalKm: 3000,
          intervalMonths: 12,
        ),
      ], odometer: 13100).nextDue!;
      expect(byKm.kmLeft, -100);
      expect(byKm.status, DueStatus.overdue);

      // Hardly driven, but the months are up.
      final byDate = _summary(
        [
          _service(
            id: 's1',
            date: DateTime(2026, 1, 1),
            intervalKm: 3000,
            intervalMonths: 6,
          ),
        ],
        odometer: 10200,
        today: DateTime(2026, 7, 2),
      ).nextDue!;
      expect(byDate.daysLeft, -1);
      expect(byDate.status, DueStatus.overdue);
    });

    test('due soon inside 10% of the km interval or two weeks', () {
      DueStatus at(int km, DateTime today) => _summary(
        [_service(id: 's1', intervalKm: 5000, intervalMonths: 6)],
        odometer: km,
        today: today,
      ).nextDue!.status;

      expect(at(14400, DateTime(2026, 7, 1)), DueStatus.ok);
      expect(at(14500, DateTime(2026, 7, 1)), DueStatus.dueSoon);
      expect(at(11000, DateTime(2026, 11, 17)), DueStatus.dueSoon);
      expect(at(11000, DateTime(2026, 12, 1)), DueStatus.overdue);
    });

    test('a short interval still warns at least 100 km ahead', () {
      final due = _summary([
        _service(id: 's1', odometer: 1000, intervalKm: 500),
      ], odometer: 1420).nextDue!;
      expect(due.kmLeft, 80);
      expect(due.status, DueStatus.dueSoon);
    });

    test('the description names both limits', () {
      final due = _summary([
        _service(id: 's1', intervalKm: 5000, intervalMonths: 6),
      ], odometer: 12000).nextDue!;
      expect(due.describe, 'in 3,000 km · in 5 months');

      final late = _summary([
        _service(id: 's1', intervalKm: 1000),
      ], odometer: 11250).nextDue!;
      expect(late.describe, '250 km over');
    });
  });

  group('vehicle summary', () {
    test('the current reading is the highest one written down', () {
      expect(
        _summary([
          _service(id: 's1', odometer: 52000),
        ], odometer: 50000).currentKm,
        52000,
      );
      expect(
        _summary([
          _service(id: 's1', odometer: 52000),
        ], odometer: 53500).currentKm,
        53500,
      );
    });

    test('only the latest record of a job restarts its clock', () {
      final summary = _summary([
        _service(
          id: 'new',
          service: 'tuning',
          date: DateTime(2026, 6, 1),
          odometer: 20000,
          intervalKm: 3000,
        ),
        _service(
          id: 'old',
          service: 'Tuning',
          date: DateTime(2026, 1, 1),
          odometer: 17000,
          intervalKm: 3000,
        ),
      ], odometer: 20500);
      expect(summary.dues, hasLength(1));
      expect(summary.nextDue!.last.id, 'new');
      expect(summary.nextDue!.dueKm, 23000);
    });

    test('the most urgent job comes first', () {
      final summary = _summary([
        _service(id: 'a', service: 'Air filter', intervalKm: 10000),
        _service(id: 'o', service: 'Oil', intervalKm: 1000),
        _service(id: 't', service: 'Tuning', intervalKm: 3000),
      ], odometer: 10950);
      expect(summary.dues.map((d) => d.service), [
        'Oil',
        'Tuning',
        'Air filter',
      ]);
      expect(summary.attentionCount, 1);
    });

    test('cost is totalled per job, biggest first', () {
      final summary = _summary([
        _service(id: '1', service: 'Tuning', cost: 2500),
        _service(id: '2', service: 'Oil', cost: 1800),
        _service(id: '3', service: 'tuning', cost: 3000),
      ]);
      expect(summary.totalCost, 7300);
      expect(summary.byService.first.service, 'Tuning');
      expect(summary.byService.first.total, 5500);
      expect(summary.byService.first.count, 2);
    });
  });

  group('serialisation', () {
    test('a service record survives a round trip', () {
      final record = _service(
        id: 's1',
        service: 'Engine oil change',
        odometer: 42150,
        cost: 4800,
        intervalKm: 5000,
        intervalMonths: 6,
      ).copyWith(workshop: 'Al-Madina Autos', note: 'Shell Helix');
      final back = VehicleService.fromJson(record.toJson())!;
      expect(back.service, 'Engine oil change');
      expect(back.odometer, 42150);
      expect(back.cost, 4800);
      expect(back.intervalKm, 5000);
      expect(back.intervalMonths, 6);
      expect(back.workshop, 'Al-Madina Autos');
      expect(back.date, DateTime(2026, 6, 1));
    });

    test('numbers arriving as strings are accepted', () {
      final back = VehicleService.fromJson({
        'id': 's1',
        'vehicle_id': 'v1',
        'service': 'Tuning',
        'serviced_on': '2026-06-01',
        'odometer': '42150',
        'cost': '2500.00',
        'interval_km': 0,
      })!;
      expect(back.odometer, 42150);
      expect(back.cost, 2500);
      // Zero is "no interval", not "due immediately".
      expect(back.intervalKm, isNull);
    });

    test('a vehicle keeps its kind', () {
      final bike = Vehicle(
        id: 'v2',
        name: 'CD 70',
        kind: VehicleKind.bike,
        plate: 'LEB-1234',
        odometer: 18000,
      );
      final back = Vehicle.fromJson(bike.toJson())!;
      expect(back.kind, VehicleKind.bike);
      expect(back.plate, 'LEB-1234');
      expect(back.odometer, 18000);
    });
  });

  group('catalog', () {
    test('a bike gets bike intervals', () {
      expect(
        ServiceCatalog.find(VehicleKind.bike, 'engine oil change')!.intervalKm,
        1000,
      );
      expect(
        ServiceCatalog.find(VehicleKind.car, 'Engine oil change')!.intervalKm,
        5000,
      );
    });

    test('suggestions put the vehicle\'s own jobs first, once each', () {
      final out = ServiceCatalog.suggestions(VehicleKind.car, [
        _service(id: '1', service: 'Gearbox oil'),
        _service(id: '2', service: 'tuning'),
      ]);
      expect(out.take(2), ['Gearbox oil', 'tuning']);
      expect(out.where((s) => s.toLowerCase() == 'tuning'), hasLength(1));
    });
  });
}
