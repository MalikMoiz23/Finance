import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../state/auth_controller.dart';

/// Login and registration on one screen: a segmented toggle swaps between them
/// so nobody has to hunt for a second page.
///
/// Register captures name, email and password; login takes email and password.
/// Each account only ever sees its own expenses — that is enforced by row level
/// security on the server, not by this screen.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _registering = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _switchMode(bool registering) {
    if (_registering == registering) return;
    setState(() => _registering = registering);
    context.read<AuthController>().clearMessages();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final auth = context.read<AuthController>();
    if (_registering) {
      final ok = await auth.register(
        name: _name.text,
        email: _email.text,
        password: _password.text,
      );
      // Email confirmation on: the account exists but there is no session yet.
      if (ok && mounted && auth.notice != null) {
        setState(() => _registering = false);
      }
    } else {
      await auth.signIn(email: _email.text, password: _password.text);
    }
  }

  String? _validateEmail(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter your email';
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
    return valid ? null : 'That does not look like an email address';
  }

  String? _validatePassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Enter your password';
    if (_registering && text.length < 6) {
      return 'Use at least 6 characters';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final auth = context.watch<AuthController>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.gutter,
              vertical: 28,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Brand(),
                  const SizedBox(height: 26),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: viz.surfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        _ModeTab(
                          label: 'Log in',
                          selected: !_registering,
                          onTap: () => _switchMode(false),
                        ),
                        _ModeTab(
                          label: 'Register',
                          selected: _registering,
                          onTap: () => _switchMode(true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: viz.surface,
                      borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                      border: Border.all(color: viz.hairline),
                      boxShadow: context.isDarkMode
                          ? null
                          : const [
                              BoxShadow(
                                color: Color(0x0F0B0B0B),
                                blurRadius: 18,
                                offset: Offset(0, 6),
                              ),
                            ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _registering
                                ? 'Create your account'
                                : 'Welcome back',
                            style: context.text.titleMedium?.copyWith(
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _registering
                                ? 'Your expenses stay private to this account.'
                                : 'Log in to see your expenses.',
                            style: context.text.bodySmall?.copyWith(
                              color: viz.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Only the name field differs between the two modes.
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: _registering
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _Field(
                                        label: 'Name',
                                        controller: _name,
                                        icon: Icons.person_outline_rounded,
                                        hint: 'Abdul Moiz',
                                        textCapitalization:
                                            TextCapitalization.words,
                                        autofillHints: const [
                                          AutofillHints.name,
                                        ],
                                        validator: (value) =>
                                            (value ?? '').trim().isEmpty
                                            ? 'Enter your name'
                                            : null,
                                      ),
                                      const SizedBox(height: 14),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                          _Field(
                            label: 'Email',
                            controller: _email,
                            icon: Icons.alternate_email_rounded,
                            hint: 'you@example.com',
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 14),
                          _Field(
                            label: 'Password',
                            controller: _password,
                            icon: Icons.lock_outline_rounded,
                            hint: _registering ? 'At least 6 characters' : '',
                            obscure: _obscure,
                            autofillHints: _registering
                                ? const [AutofillHints.newPassword]
                                : const [AutofillHints.password],
                            onSubmitted: (_) => _submit(),
                            validator: _validatePassword,
                            trailing: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 19,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          if (auth.error != null) ...[
                            const SizedBox(height: 16),
                            _Banner(
                              message: auth.error!,
                              icon: Icons.error_outline_rounded,
                              tone: viz.critical,
                            ),
                          ],
                          if (auth.notice != null) ...[
                            const SizedBox(height: 16),
                            _Banner(
                              message: auth.notice!,
                              icon: Icons.mark_email_unread_outlined,
                              tone: viz.successText,
                            ),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: auth.isBusy ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: viz.series,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: viz.series.withValues(
                                  alpha: 0.5,
                                ),
                                disabledForegroundColor: Colors.white70,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: auth.isBusy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _registering
                                          ? 'Create account'
                                          : 'Log in',
                                      style: context.text.titleSmall?.copyWith(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: TextButton(
                      onPressed: () => _switchMode(!_registering),
                      child: Text(
                        _registering
                            ? 'Already have an account? Log in'
                            : 'New here? Create an account',
                        style: context.text.bodySmall?.copyWith(
                          color: viz.series,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    return Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: dark
                  ? const [Color(0xFF184F95), Color(0xFF0D366B)]
                  : const [Color(0xFF1C5CAB), Color(0xFF104281)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(
            Icons.account_balance_wallet_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Finance',
          style: context.text.titleMedium?.copyWith(
            fontSize: 24,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Know where the money goes',
          style: context.text.bodySmall?.copyWith(color: context.viz.inkMuted),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? viz.series : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: context.text.labelLarge?.copyWith(
                color: selected ? Colors.white : viz.inkSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.icon,
    required this.validator,
    this.hint = '',
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.trailing,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? Function(String?) validator;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: context.text.labelSmall?.copyWith(
            color: viz.inkMuted,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          autofillHints: autofillHints,
          validator: validator,
          onFieldSubmitted: onSubmitted,
          textInputAction: onSubmitted == null
              ? TextInputAction.next
              : TextInputAction.done,
          style: context.text.bodyLarge?.copyWith(color: viz.inkPrimary),
          decoration: InputDecoration(
            hintText: hint.isEmpty ? null : hint,
            prefixIcon: Icon(icon, size: 19, color: viz.inkMuted),
            suffixIcon: trailing,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.icon,
    required this.tone,
  });

  final String message;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
