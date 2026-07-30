import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/supabase_config.dart';

/// Shown instead of the app when the Supabase anon key has not been filled in,
/// so the first run fails with instructions rather than a stack trace.
class SetupNoticeScreen extends StatelessWidget {
  const SetupNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: viz.surface,
                  borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                  border: Border.all(color: viz.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.key_off_rounded, color: viz.critical),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Supabase key missing',
                            style: context.text.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'The app is pointed at:',
                      style: context.text.bodySmall?.copyWith(
                        color: viz.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      SupabaseConfig.url,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _Step(
                      number: 1,
                      text:
                          'Supabase dashboard → Project Settings → API Keys → '
                          'copy the "anon public" key.',
                    ),
                    _Step(
                      number: 2,
                      text:
                          'Paste it into _pastedKey in '
                          'lib/core/supabase_config.dart, or run with '
                          '--dart-define=SUPABASE_ANON_KEY=eyJ…',
                    ),
                    _Step(
                      number: 3,
                      text:
                          'Run supabase/schema.sql once in the SQL Editor to '
                          'create the expenses table and its policies.',
                    ),
                    _Step(
                      number: 4,
                      text:
                          'Authentication → Sign In / Providers → turn off '
                          '"Confirm email" so registering logs you straight in.',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Never put the service_role key in this app — it bypasses '
                      'row level security.',
                      style: context.text.bodySmall?.copyWith(
                        color: viz.critical,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: viz.series.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$number',
              style: context.text.labelSmall?.copyWith(
                color: viz.series,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: context.text.bodyMedium?.copyWith(
                color: viz.inkSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
