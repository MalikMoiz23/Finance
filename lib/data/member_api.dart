import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family_member.dart';

/// The household's list of people. Row level security scopes every call, so no
/// method takes a user id: one account, one family.
///
/// Every write is an **upsert keyed on the row's own id**, generated on the
/// device — replaying a queued change after a dropped connection can never
/// create a duplicate member.
abstract interface class MemberApi {
  Future<List<FamilyMember>> fetchAll();

  Future<void> upsert(FamilyMember member);

  /// Removes the member. Expenses that pointed at them are left in place with
  /// no person attached — the server does that with `on delete set null`, so a
  /// deleted member never takes spending history down with them.
  Future<void> delete(String id);
}

class SupabaseMemberApi implements MemberApi {
  SupabaseMemberApi(this._client);

  static const table = 'family_members';

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Not signed in — no user id for the members request.');
    }
    return id;
  }

  @override
  Future<List<FamilyMember>> fetchAll() async {
    final rows = await _client.from(table).select().order('created_at');
    return rows.map(FamilyMember.fromJson).whereType<FamilyMember>().toList();
  }

  @override
  Future<void> upsert(FamilyMember member) async {
    await _client.from(table).upsert({
      ...member.toJson(),
      'user_id': _userId,
      'created_at': member.createdAt.toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  @override
  Future<void> delete(String id) async {
    await _client.from(table).delete().eq('id', id);
  }
}
