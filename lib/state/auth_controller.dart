import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/error_messages.dart';
import '../data/auth_gateway.dart';
import '../models/app_user.dart';

/// Holds the signed-in account plus the form state of the auth screen.
class AuthController extends ChangeNotifier {
  AuthController(this._gateway) {
    _user = _gateway.currentUser;
    _subscription = _gateway.changes.listen(
      _onUserChanged,
      onError: (Object error) {
        _error = describeError(error);
        notifyListeners();
      },
    );
  }

  final AuthGateway _gateway;
  late final StreamSubscription<AppUser?> _subscription;

  AppUser? _user;
  bool _busy = false;
  String? _error;
  String? _notice;

  AppUser? get user => _user;
  bool get isSignedIn => _user != null;
  bool get isBusy => _busy;

  /// Set when the last attempt failed; shown as a banner on the auth screen.
  String? get error => _error;

  /// Set when registration succeeded but the account still needs email
  /// confirmation.
  String? get notice => _notice;

  void _onUserChanged(AppUser? user) {
    if (user == _user) return;
    _user = user;
    if (user != null) {
      _error = null;
      _notice = null;
    }
    notifyListeners();
  }

  void clearMessages() {
    if (_error == null && _notice == null) return;
    _error = null;
    _notice = null;
    notifyListeners();
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) {
    return _run(() async {
      final outcome = await _gateway.register(
        name: name,
        email: email,
        password: password,
      );
      if (outcome == RegisterOutcome.needsEmailConfirmation) {
        _notice =
            'Account created. Open the confirmation link we emailed to '
            '${email.trim()}, then log in.';
      }
      return true;
    });
  }

  Future<bool> signIn({required String email, required String password}) {
    return _run(() async {
      await _gateway.signIn(email: email, password: password);
      return true;
    });
  }

  Future<void> signOut() async {
    await _run(() async {
      await _gateway.signOut();
      return true;
    });
  }

  Future<bool> _run(Future<bool> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      _error = describeError(error);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
