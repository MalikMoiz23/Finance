import 'dart:math' as math;

import '../core/formatters.dart';

/// Sentinel for the `copyWith`s below, so "leave this alone" is distinguishable
/// from "set this back to null".
const Object _keep = Object();

/// What sort of vehicle it is. Decides which service presets are offered and
/// their default intervals — a bike wants fresh oil far sooner than a car.
enum VehicleKind {
  car('Car'),
  bike('Bike');

  const VehicleKind(this.label);

  final String label;

  static VehicleKind fromName(String? name) => VehicleKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => VehicleKind.car,
  );
}

/// A car or bike in the household, and the reading its odometer was last seen
/// at.
///
/// Vehicles are a **separate ledger**, like projects. Tuning and service costs
/// never count towards the monthly spending, a category budget or the month's
/// savings — this screen is a maintenance logbook, with its own totals.
class Vehicle {
  Vehicle({
    required this.id,
    required this.name,
    this.kind = VehicleKind.car,
    this.plate = '',
    this.odometer = 0,
    this.note = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Generated on the device, so a vehicle added offline keeps its identity —
  /// and its service records keep pointing at it — once it syncs.
  final String id;

  /// "Honda City", "CD 70". What the household calls it.
  final String name;

  final VehicleKind kind;

  /// Registration number. May be empty.
  final String plate;

  /// Last reading typed in for the vehicle itself, in km. The current reading
  /// is the larger of this and the newest service record — see
  /// [VehicleSummary.currentKm].
  final int odometer;

  final String note;
  final DateTime createdAt;

  Vehicle copyWith({
    String? name,
    VehicleKind? kind,
    String? plate,
    int? odometer,
    String? note,
  }) {
    return Vehicle(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      plate: plate ?? this.plate,
      odometer: odometer ?? this.odometer,
      note: note ?? this.note,
      createdAt: createdAt,
    );
  }

  /// Snake case, so one map serves both the device's database and the Supabase
  /// row without a second mapping step.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'plate': plate,
    'odometer': odometer,
    'note': note,
    'created_at': createdAt.toIso8601String(),
  };

  static Vehicle? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = (json['name'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) return null;
    return Vehicle(
      id: id,
      name: name,
      kind: VehicleKind.fromName(json['kind'] as String?),
      plate: json['plate'] as String? ?? '',
      odometer: _toInt(json['odometer']) ?? 0,
      note: json['note'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }
}

/// One visit to the workshop: what was done, on which day, at what reading,
/// for how much — and when the same job is due again.
///
/// The interval is stored **on the record**, not looked up from a preset, so
/// changing a default later never rewrites when an old service said the next
/// one was due. Either interval may be null; with both null the record is
/// history only and nothing is ever flagged as due.
class VehicleService {
  VehicleService({
    required this.id,
    required this.vehicleId,
    required this.service,
    required DateTime date,
    required this.odometer,
    this.cost = 0,
    this.intervalKm,
    this.intervalMonths,
    this.workshop = '',
    this.note = '',
    DateTime? createdAt,
  }) : date = dayOnly(date),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String vehicleId;

  /// What was done — "Tuning", "Engine oil change". Free text, so a household
  /// can name its own jobs; due dates are tracked per name, ignoring case.
  final String service;

  final DateTime date;

  /// Odometer reading at the time of the service, in km.
  final int odometer;

  /// What it cost. Zero is allowed: a free check-up under warranty is still a
  /// service worth recording.
  final double cost;

  /// Due again after this many km. Null when distance does not matter.
  final int? intervalKm;

  /// Due again after this many months. Null when time does not matter.
  final int? intervalMonths;

  /// Who did it. May be empty.
  final String workshop;

  final String note;
  final DateTime createdAt;

  String get title => service.trim().isEmpty ? 'Service' : service.trim();

  /// Key the due tracking groups on: "Tuning" and "tuning" are the same job.
  String get serviceKey => title.toLowerCase();

  bool get hasInterval => intervalKm != null || intervalMonths != null;

  int? get nextDueKm => intervalKm == null ? null : odometer + intervalKm!;

  DateTime? get nextDueDate =>
      intervalMonths == null ? null : addMonths(date, intervalMonths!);

  VehicleService copyWith({
    String? service,
    DateTime? date,
    int? odometer,
    double? cost,
    Object? intervalKm = _keep,
    Object? intervalMonths = _keep,
    String? workshop,
    String? note,
  }) {
    return VehicleService(
      id: id,
      vehicleId: vehicleId,
      service: service ?? this.service,
      date: date ?? this.date,
      odometer: odometer ?? this.odometer,
      cost: cost ?? this.cost,
      intervalKm: identical(intervalKm, _keep)
          ? this.intervalKm
          : intervalKm as int?,
      intervalMonths: identical(intervalMonths, _keep)
          ? this.intervalMonths
          : intervalMonths as int?,
      workshop: workshop ?? this.workshop,
      note: note ?? this.note,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicle_id': vehicleId,
    'service': service,
    'serviced_on': _dateOnly(date),
    'odometer': odometer,
    'cost': cost,
    'interval_km': intervalKm,
    'interval_months': intervalMonths,
    'workshop': workshop,
    'note': note,
    'created_at': createdAt.toIso8601String(),
  };

  static VehicleService? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final vehicleId = json['vehicle_id'] as String?;
    final date = DateTime.tryParse(json['serviced_on'] as String? ?? '');
    final odometer = _toInt(json['odometer']);
    if (id == null || vehicleId == null || date == null || odometer == null) {
      return null;
    }
    return VehicleService(
      id: id,
      vehicleId: vehicleId,
      service: json['service'] as String? ?? '',
      date: date,
      odometer: odometer,
      cost: _toDouble(json['cost']) ?? 0,
      intervalKm: _positive(_toInt(json['interval_km'])),
      intervalMonths: _positive(_toInt(json['interval_months'])),
      workshop: json['workshop'] as String? ?? '',
      note: json['note'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? date,
    );
  }

  /// [date] moved [months] forward, with the day clamped to the end of the
  /// target month: a service on 31 January with a one-month interval is due on
  /// 28 (or 29) February, not on 3 March.
  static DateTime addMonths(DateTime date, int months) {
    final firstOfTarget = DateTime(date.year, date.month + months);
    final lastDay = DateTime(
      firstOfTarget.year,
      firstOfTarget.month + 1,
      0,
    ).day;
    return DateTime(
      firstOfTarget.year,
      firstOfTarget.month,
      math.min(date.day, lastDay),
    );
  }
}

/// How urgent a job is, most urgent first so the enum order is the sort order.
enum DueStatus {
  overdue('Overdue'),
  dueSoon('Due soon'),
  ok('On schedule');

  const DueStatus(this.label);

  final String label;
}

/// When one job on one vehicle is due next, measured against today and the
/// vehicle's current reading. Whichever of distance or time runs out first
/// decides.
class ServiceDue {
  ServiceDue({
    required this.last,
    required this.currentKm,
    required DateTime today,
  }) : today = dayOnly(today);

  /// The most recent record of this job. Its interval is what is measured.
  final VehicleService last;
  final int currentKm;
  final DateTime today;

  /// Warn this many days ahead of a date-based due.
  static const soonDays = 14;

  /// Warn this share of the km interval ahead of a distance-based due, but
  /// never with less than [minSoonKm] to go — 10% of a 500 km chain interval
  /// is a single afternoon's riding.
  static const soonShare = 0.1;
  static const minSoonKm = 100;

  String get service => last.title;

  int? get dueKm => last.nextDueKm;

  DateTime? get dueDate => last.nextDueDate;

  /// Negative once the reading has passed the due km.
  int? get kmLeft => dueKm == null ? null : dueKm! - currentKm;

  /// Negative once the due date has passed.
  int? get daysLeft => dueDate?.difference(today).inDays;

  DueStatus get status {
    final km = kmLeft;
    final days = daysLeft;
    if ((km != null && km <= 0) || (days != null && days <= 0)) {
      return DueStatus.overdue;
    }
    final kmWarn = last.intervalKm == null
        ? 0
        : math.max(minSoonKm, (last.intervalKm! * soonShare).round());
    if ((km != null && km <= kmWarn) || (days != null && days <= soonDays)) {
      return DueStatus.dueSoon;
    }
    return DueStatus.ok;
  }

  /// "in 420 km or 3 weeks", "1,200 km overdue", "due today". Both limits are
  /// named when both exist, because either one can end up deciding.
  String get describe {
    final parts = <String>[];
    final km = kmLeft;
    final days = daysLeft;
    if (km != null) {
      parts.add(
        km <= 0
            ? '${Quantities.format(-km)} km over'
            : 'in ${Quantities.format(km)} km',
      );
    }
    if (days != null) {
      parts.add(switch (days) {
        0 => 'due today',
        < 0 => '${_span(-days)} late',
        _ => 'in ${_span(days)}',
      });
    }
    return parts.join(' · ');
  }

  /// Sort key inside a status: the nearer of the two limits, as a fraction of
  /// its own interval, so 300 km left of a 1,000 km interval sorts ahead of
  /// 2 months left of a 12 month one.
  double get _remainingShare {
    final shares = <double>[];
    if (kmLeft != null && last.intervalKm != null) {
      shares.add(kmLeft! / last.intervalKm!);
    }
    if (daysLeft != null && last.intervalMonths != null) {
      shares.add(daysLeft! / (last.intervalMonths! * 30.4));
    }
    return shares.isEmpty ? double.infinity : shares.reduce(math.min);
  }

  static int compare(ServiceDue a, ServiceDue b) {
    final byStatus = a.status.index.compareTo(b.status.index);
    if (byStatus != 0) return byStatus;
    return a._remainingShare.compareTo(b._remainingShare);
  }

  static String _span(int days) {
    if (days < 14) return '$days ${days == 1 ? 'day' : 'days'}';
    if (days < 60) return '${(days / 7).round()} weeks';
    final months = (days / 30.4).round();
    return '$months ${months == 1 ? 'month' : 'months'}';
  }
}

/// What one kind of job has cost on a vehicle so far.
class ServiceTotal {
  const ServiceTotal({
    required this.service,
    required this.total,
    required this.count,
  });

  final String service;
  final double total;
  final int count;

  double shareOf(double grandTotal) => grandTotal <= 0 ? 0 : total / grandTotal;
}

/// A vehicle with its service history, and everything the screens read off it.
class VehicleSummary {
  VehicleSummary({
    required this.vehicle,
    required List<VehicleService> services,
    required DateTime today,
  }) : services = List.unmodifiable(services),
       today = dayOnly(today);

  final Vehicle vehicle;

  /// Newest first.
  final List<VehicleService> services;

  final DateTime today;

  String get id => vehicle.id;
  String get name => vehicle.name;

  /// The furthest reading anyone has written down: the vehicle's own, or the
  /// one on its latest service. An odometer only goes up, so the larger is the
  /// truer one.
  int get currentKm => services.fold<int>(
    vehicle.odometer,
    (best, s) => math.max(best, s.odometer),
  );

  double get totalCost => services.fold<double>(0, (sum, s) => sum + s.cost);

  int get serviceCount => services.length;

  DateTime? get lastServiceDate =>
      services.isEmpty ? null : services.first.date;

  /// The latest record of every job that has an interval, most urgent first.
  /// Older records of the same job are history: the newest one restarted the
  /// clock.
  List<ServiceDue> get dues {
    final latest = <String, VehicleService>{};
    for (final record in services) {
      final seen = latest[record.serviceKey];
      if (seen == null || _isNewer(record, seen)) {
        latest[record.serviceKey] = record;
      }
    }
    return latest.values
        .where((r) => r.hasInterval)
        .map((r) => ServiceDue(last: r, currentKm: currentKm, today: today))
        .toList()
      ..sort(ServiceDue.compare);
  }

  /// The next thing to book, or null when nothing has an interval.
  ServiceDue? get nextDue {
    final all = dues;
    return all.isEmpty ? null : all.first;
  }

  int get attentionCount => dues.where((d) => d.status != DueStatus.ok).length;

  /// Cost per job, biggest first. Jobs differing only in case are one row.
  List<ServiceTotal> get byService {
    final byKey = <String, ({String label, double total, int count})>{};
    for (final record in services) {
      final seen = byKey[record.serviceKey];
      byKey[record.serviceKey] = (
        label: seen?.label ?? record.title,
        total: (seen?.total ?? 0) + record.cost,
        count: (seen?.count ?? 0) + 1,
      );
    }
    return byKey.values
        .map(
          (v) => ServiceTotal(service: v.label, total: v.total, count: v.count),
        )
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Same day: the higher reading is the later visit.
  static bool _isNewer(VehicleService a, VehicleService b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate > 0;
    final byKm = a.odometer.compareTo(b.odometer);
    if (byKm != 0) return byKm > 0;
    return a.createdAt.isAfter(b.createdAt);
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

int? _toInt(Object? value) => switch (value) {
  final num n => n.round(),
  final String s => num.tryParse(s)?.round(),
  _ => null,
};

int? _positive(int? value) => value != null && value > 0 ? value : null;
