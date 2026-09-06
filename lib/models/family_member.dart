/// One person in the household.
///
/// The whole family shares a single login, so a member is **not** an account:
/// there is no password, no permissions, nothing to sign in as. It is a name
/// attached to an expense so "where did the money go" can also answer "who
/// spent it". Anyone holding the phone can add, rename or remove any of them.
class FamilyMember {
  FamilyMember({required this.id, required this.name, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();

  /// Generated on the device, so a member added offline keeps their identity —
  /// and the expenses pointing at them stay attached — once it syncs.
  final String id;

  final String name;
  final DateTime createdAt;

  /// `AM` for "Abdul Moiz", `Ab` for "Abba". Used on the avatar chips, where
  /// there is no room for the full name.
  ///
  /// A one-word name takes two of its own letters rather than one: in a house
  /// with an Abba and an Ammi, a lone `A` on both tells you nothing.
  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final only = words.first;
      if (only.length == 1) return only.toUpperCase();
      return only.substring(0, 1).toUpperCase() +
          only.substring(1, 2).toLowerCase();
    }
    return words.take(2).map((w) => w.substring(0, 1).toUpperCase()).join();
  }

  FamilyMember copyWith({String? name}) => FamilyMember(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
  );

  /// Snake case, so one map serves both the device's database and the Supabase
  /// row without a second mapping step.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_at': createdAt.toIso8601String(),
  };

  static FamilyMember? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = (json['name'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) return null;
    return FamilyMember(
      id: id,
      name: name,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }
}

/// What one person spent over some stretch of time.
///
/// [member] is null for the "Not set" row: expenses logged before the family
/// was set up, and any whose person was later removed. They are shown rather
/// than hidden, because a total that quietly leaves money out is worse than one
/// that admits it does not know whose it was.
class MemberSpend {
  const MemberSpend({
    required this.member,
    required this.total,
    required this.count,
  });

  final FamilyMember? member;
  final double total;
  final int count;

  bool get unassigned => member == null;

  String get name => member?.name ?? 'Not set';

  String get initials => member?.initials ?? '—';

  double shareOf(double grandTotal) => grandTotal <= 0 ? 0 : total / grandTotal;
}
