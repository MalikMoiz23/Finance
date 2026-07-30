/// The signed-in account, reduced to what the UI needs.
class AppUser {
  const AppUser({required this.id, required this.email, required this.name});

  final String id;
  final String email;

  /// Full name captured at registration (auth metadata `full_name`).
  final String name;

  /// "Abdul Moiz" -> "Abdul". Falls back to the part of the email before the @.
  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed.split(RegExp(r'\s+')).first;
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : 'there';
  }

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.email == email &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, email, name);
}
