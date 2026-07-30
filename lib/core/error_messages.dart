import 'package:supabase_flutter/supabase_flutter.dart';

const _noNetwork = 'No internet connection. Check your network and try again.';

/// Turns a Supabase / transport error into one sentence a person can act on.
///
/// Deliberately avoids `dart:io` (SocketException) so the same code runs on web:
/// network failures are recognised from the exception type and text instead.
String describeError(Object error) {
  if (error is AuthRetryableFetchException) return _noNetwork;

  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirm your email address first — check your inbox.';
    }
    if (message.contains('user already registered') ||
        message.contains('already been registered')) {
      return 'That email already has an account. Try logging in.';
    }
    if (message.contains('password should be at least')) {
      return 'Password is too short — use at least 6 characters.';
    }
    if (message.contains('unable to validate email') ||
        message.contains('invalid email')) {
      return 'That email address does not look valid.';
    }
    if (message.contains('rate limit') ||
        message.contains('too many requests')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    return error.message;
  }

  if (error is PostgrestException) {
    final code = error.code ?? '';
    final message = error.message.toLowerCase();
    // A missing table or column means the schema has not been applied yet.
    if (code == '42P01' ||
        code == 'PGRST205' ||
        code == 'PGRST204' ||
        message.contains('could not find the table') ||
        message.contains('does not exist')) {
      return 'The database is missing a table or column. Run '
          'supabase/schema.sql in the Supabase SQL Editor.';
    }
    if (code == '42501' || code.startsWith('PGRST')) {
      return 'The server refused that request. Check the table policies in '
          'supabase/schema.sql.';
    }
    if (code == '23514') return 'That value is not allowed by the database.';
    return error.message;
  }

  final text = error.toString().toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('clientexception') ||
      text.contains('xmlhttprequest') ||
      text.contains('connection closed') ||
      text.contains('timeout')) {
    return _noNetwork;
  }

  return 'Something went wrong. Please try again.';
}
