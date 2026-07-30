import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../state/expense_store.dart';
import 'auth_screen.dart';
import 'home_shell.dart';

/// Decides what the app shows, and keeps the expense store pointed at whichever
/// account is signed in.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _boundUserId;
  bool _bound = false;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;

    if (!_bound || user?.id != _boundUserId) {
      _bound = true;
      _boundUserId = user?.id;
      final store = context.read<ExpenseStore>();
      // After the frame: bindUser notifies listeners, which must not happen
      // while this build is still running.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) store.bindUser(user);
      });
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: user == null
          ? const AuthScreen(key: ValueKey('auth'))
          : const HomeShell(key: ValueKey('home')),
    );
  }
}
