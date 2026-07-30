import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';

/// What sign-up produced. With "Confirm email" switched off in the Supabase
/// dashboard, registering returns a session and the user is in immediately;
/// with it on, Supabase returns no session until the link is clicked.
enum RegisterOutcome { signedIn, needsEmailConfirmation }

/// Auth as the app needs it. An interface so the widget tests can run against a
/// fake without a network or a Supabase project.
abstract interface class AuthGateway {
  AppUser? get currentUser;

  /// Emits on sign-in, sign-out, token refresh and session restore.
  Stream<AppUser?> get changes;

  Future<RegisterOutcome> register({
    required String name,
    required String email,
    required String password,
  });

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._auth);

  final GoTrueClient _auth;

  AppUser? _map(User? user) {
    if (user == null) return null;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      name: (metadata['full_name'] as String?)?.trim() ?? '',
    );
  }

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AppUser?> get changes =>
      _auth.onAuthStateChange.map((state) => _map(state.session?.user));

  @override
  Future<RegisterOutcome> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _auth.signUp(
      email: email.trim(),
      password: password,
      // Read back as user_metadata.full_name; no profiles table needed.
      data: {'full_name': name.trim()},
    );
    return response.session == null
        ? RegisterOutcome.needsEmailConfirmation
        : RegisterOutcome.signedIn;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithPassword(email: email.trim(), password: password);
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
