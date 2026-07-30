/// Supabase connection details.
///
/// The key below is the **publishable** (a.k.a. `anon public`) key: it is meant
/// to ship inside client apps and is safe to commit. What keeps one account's
/// expenses away from another is row level security on the table
/// (see `supabase/schema.sql`) — never the secrecy of this key.
///
/// The `service_role` key must never appear in this app: it bypasses every
/// policy.
abstract final class SupabaseConfig {
  /// PASTE THE KEY HERE — Supabase dashboard → Project Settings → API Keys →
  /// `anon public` / `Publishable key`. Leave it empty to pass the key at run
  /// time instead:
  ///
  ///   flutter run --dart-define=SUPABASE_ANON_KEY=eyJ...
  static const _pastedKey = 'sb_publishable_rXEudl0IN9O22IQkgSNoKg_EcYadj_B';

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qhlxxvzqdspimjrzsrez.supabase.co',
  );

  static const _definedKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// A `--dart-define` wins over the pasted constant, so a build can override
  /// the key without editing source.
  static String get publishableKey =>
      _definedKey.trim().isNotEmpty ? _definedKey.trim() : _pastedKey.trim();

  /// False until the key is filled in; the app then shows setup instructions
  /// instead of failing on the first request.
  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.length > 20;
}
