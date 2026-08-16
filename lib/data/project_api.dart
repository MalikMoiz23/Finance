import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/project.dart';

/// Remote store for one account's projects and their entries. Row level
/// security scopes every call, so no method takes a user id.
///
/// Every write is an **upsert keyed on the row's own id**, generated on the
/// device — replaying a queued change after a dropped connection can never
/// create a duplicate.
abstract interface class ProjectApi {
  Future<List<Project>> fetchProjects();
  Future<List<ProjectEntry>> fetchEntries();

  Future<void> upsertProject(Project project);

  /// Removes the project. The server cascades its entries.
  Future<void> deleteProject(String id);

  Future<void> upsertEntry(ProjectEntry entry);
  Future<void> deleteEntry(String id);
}

class SupabaseProjectApi implements ProjectApi {
  SupabaseProjectApi(this._client);

  static const projectsTable = 'projects';
  static const entriesTable = 'project_entries';

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Not signed in — no user id for the projects request.');
    }
    return id;
  }

  @override
  Future<List<Project>> fetchProjects() async {
    final rows = await _client
        .from(projectsTable)
        .select()
        .order('started_on', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(Project.fromJson).whereType<Project>().toList();
  }

  @override
  Future<List<ProjectEntry>> fetchEntries() async {
    final rows = await _client
        .from(entriesTable)
        .select()
        .order('spent_on', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(ProjectEntry.fromJson).whereType<ProjectEntry>().toList();
  }

  @override
  Future<void> upsertProject(Project project) async {
    await _client.from(projectsTable).upsert({
      ...project.toJson(),
      'user_id': _userId,
      'created_at': project.createdAt.toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  @override
  Future<void> deleteProject(String id) async {
    await _client.from(projectsTable).delete().eq('id', id);
  }

  @override
  Future<void> upsertEntry(ProjectEntry entry) async {
    await _client.from(entriesTable).upsert({
      ...entry.toJson(),
      'user_id': _userId,
      'created_at': entry.createdAt.toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  @override
  Future<void> deleteEntry(String id) async {
    await _client.from(entriesTable).delete().eq('id', id);
  }
}
