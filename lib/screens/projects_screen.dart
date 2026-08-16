import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/project.dart';
import '../state/expense_store.dart';
import '../widgets/budget_meter.dart';
import '../widgets/entrance.dart';
import '../widgets/pressable.dart';
import '../widgets/section_card.dart';
import '../widgets/skeleton.dart';
import 'project_detail_screen.dart';
import 'project_editor_sheet.dart';

/// The second ledger: big one-off spending paid for out of savings.
///
/// Building a house, a wedding, a car. None of it belongs in the monthly
/// figures — that money was put aside over years — so it lives here with its own
/// totals, and the screen says so plainly rather than leaving you to wonder why
/// the numbers do not add up against the Overview tab.
class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  /// Creates a project and drops straight into it. You start a project in order
  /// to put something in it, so landing back on the list would just mean one
  /// more tap. Every entry point — the tab button, the empty state, the shell's
  /// action button — goes through here so they all behave the same.
  static Future<void> start(BuildContext context) async {
    final id = await ProjectEditorSheet.show(context);
    if (id == null || !context.mounted) return;
    await ProjectDetailScreen.open(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final projects = store.projects;
    final loadingEmpty = store.isLoading && projects.isEmpty;

    return RefreshIndicator(
      onRefresh: store.refresh,
      color: context.viz.series,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.gutter,
          6,
          AppSizes.gutter,
          110,
        ),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Projects',
                style: context.text.titleMedium?.copyWith(fontSize: 19),
              ),
              const SizedBox(height: 2),
              Text(
                'One-off spending from savings',
                style: context.text.bodySmall?.copyWith(
                  color: context.viz.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (loadingEmpty)
            Entrance(index: 0, child: SectionCard(child: const RowsSkeleton()))
          else if (projects.isEmpty)
            Entrance(
              index: 0,
              child: SectionCard(
                child: _NoProjectsYet(
                  onStart: () => start(context),
                ),
              ),
            )
          else ...[
            Entrance(index: 0, child: _AcrossProjectsCard(store: store)),
            const SizedBox(height: AppSizes.gap),
            for (var i = 0; i < projects.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSizes.gap),
              Entrance(
                index: i + 1,
                child: ProjectCard(
                  summary: projects[i],
                  onTap: () => ProjectDetailScreen.open(context, projects[i].id),
                ),
              ),
            ],
            // No "New project" button down here: the labelled action button
            // floating over this tab is the one way in, and two of them would
            // collide whenever the list is short.
          ],
        ],
      ),
    );
  }
}

/// Everything spent across every project, with the standing reminder that none
/// of it is counted anywhere else in the app.
class _AcrossProjectsCard extends StatelessWidget {
  const _AcrossProjectsCard({required this.store});

  final ExpenseStore store;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final count = store.projects.length;
    final entries = store.projectEntryCount;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spent on projects',
            style: context.text.labelSmall?.copyWith(
              color: viz.inkMuted,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedAmount(
            value: store.projectsTotal,
            formatter: Money.format,
            style: context.text.displaySmall?.copyWith(
              color: viz.inkPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count ${count == 1 ? 'project' : 'projects'} · '
            '$entries ${entries == 1 ? 'entry' : 'entries'}',
            style: context.text.bodySmall?.copyWith(color: viz.inkSecondary),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: viz.surfaceAlt,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: viz.inkMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kept out of your monthly spending, budgets and savings — '
                    'this money came from what you had already put aside.',
                    style: context.text.labelSmall?.copyWith(
                      color: viz.inkSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One project in the list: what it has cost, and how that sits against the
/// estimate when one was given.
class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.summary, required this.onTap});

  final ProjectSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final estimate = summary.estimate;
    final style = bandStyle(context, summary.band);

    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: viz.series.withValues(
                      alpha: context.isDarkMode ? 0.22 : 0.11,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.foundation_rounded,
                    size: 20,
                    color: viz.series,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: viz.inkPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(summary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: viz.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: viz.inkMuted,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text.rich(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    TextSpan(
                      children: [
                        TextSpan(
                          text: Money.format(summary.total),
                          style: context.text.titleMedium?.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                            color: viz.inkPrimary,
                          ),
                        ),
                        if (estimate != null)
                          TextSpan(
                            text: '  of ${Money.compact(estimate)}',
                            style: context.text.bodySmall?.copyWith(
                              color: viz.inkMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (estimate != null) ...[
              const SizedBox(height: 10),
              _EstimateMeter(
                fraction: summary.meterFraction,
                fill: style.fill,
                track: style.track,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(style.icon, size: 14, color: style.fill),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      summary.overEstimate
                          ? '${summary.bandLabel} by '
                                '${Money.format(-summary.remaining!)}'
                          : '${summary.bandLabel} · '
                                '${Money.format(summary.remaining!)} left',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        // Amber is below text contrast on the light surface, so
                        // wording stays in ink and the icon carries the colour.
                        color: summary.overEstimate
                            ? viz.critical
                            : viz.inkSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'No estimate set',
                style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _subtitle(ProjectSummary summary) {
    final count = summary.entryCount;
    final entries = '$count ${count == 1 ? 'entry' : 'entries'}';
    final last = summary.lastEntryDate;
    if (last == null) {
      return 'Started ${Dates.dayMonthYear(summary.project.startedOn)}';
    }
    // "last today" reads as a sentence; "last thu, 13 aug" does not, so only
    // the two word-days are lowercased.
    final when = Dates.relativeDay(last);
    final phrase = when == 'Today' || when == 'Yesterday'
        ? when.toLowerCase()
        : when;
    return '$entries · last $phrase';
  }
}

class _EstimateMeter extends StatelessWidget {
  const _EstimateMeter({
    required this.fraction,
    required this.fill,
    required this.track,
  });

  final double fraction;
  final Color fill;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 9,
        color: track,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: fraction),
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoProjectsYet extends StatelessWidget {
  const _NoProjectsYet({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.foundation_rounded, size: 34, color: viz.inkMuted),
        const SizedBox(height: 12),
        Text(
          'No projects yet',
          textAlign: TextAlign.center,
          style: context.text.titleSmall?.copyWith(color: viz.inkPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'For the big things paid out of savings — building a house, a '
          'wedding, a car. Log every load of bricks with its rate and date, '
          'and see what the whole job has cost.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(
            color: viz.inkSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'None of it touches your monthly spending or budgets.',
          textAlign: TextAlign.center,
          style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Start a project'),
            style: FilledButton.styleFrom(
              backgroundColor: viz.series,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: context.text.titleSmall?.copyWith(fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}
