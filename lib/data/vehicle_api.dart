import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vehicle.dart';

/// Remote store for one account's vehicles and their service history. Row
/// level security scopes every call, so no method takes a user id.
///
/// Every write is an **upsert keyed on the row's own id**, generated on the
/// device — replaying a queued change after a dropped connection can never
/// create a duplicate.
abstract interface class VehicleApi {
  Future<List<Vehicle>> fetchVehicles();
  Future<List<VehicleService>> fetchServices();

  Future<void> upsertVehicle(Vehicle vehicle);

  /// Removes the vehicle. The server cascades its service records.
  Future<void> deleteVehicle(String id);

  Future<void> upsertService(VehicleService service);
  Future<void> deleteService(String id);
}

class SupabaseVehicleApi implements VehicleApi {
  SupabaseVehicleApi(this._client);

  static const vehiclesTable = 'vehicles';
  static const servicesTable = 'vehicle_services';

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Not signed in — no user id for the vehicles request.');
    }
    return id;
  }

  @override
  Future<List<Vehicle>> fetchVehicles() async {
    final rows = await _client.from(vehiclesTable).select().order('created_at');
    return rows.map(Vehicle.fromJson).whereType<Vehicle>().toList();
  }

  @override
  Future<List<VehicleService>> fetchServices() async {
    final rows = await _client
        .from(servicesTable)
        .select()
        .order('serviced_on', ascending: false)
        .order('odometer', ascending: false);
    return rows
        .map(VehicleService.fromJson)
        .whereType<VehicleService>()
        .toList();
  }

  @override
  Future<void> upsertVehicle(Vehicle vehicle) async {
    await _client.from(vehiclesTable).upsert({
      ...vehicle.toJson(),
      'user_id': _userId,
      'created_at': vehicle.createdAt.toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  @override
  Future<void> deleteVehicle(String id) async {
    await _client.from(vehiclesTable).delete().eq('id', id);
  }

  @override
  Future<void> upsertService(VehicleService service) async {
    await _client.from(servicesTable).upsert({
      ...service.toJson(),
      'user_id': _userId,
      'created_at': service.createdAt.toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  @override
  Future<void> deleteService(String id) async {
    await _client.from(servicesTable).delete().eq('id', id);
  }
}
