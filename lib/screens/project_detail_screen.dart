import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../models/project.dart';
import '../state/expense_store.dart';
import '../widgets/budget_meter.dart';
import '../widgets/entrance.dart';
import '../widgets/pressable.dart';
import '../widgets/section_card.dart';
import '../widgets/share_meter.dart';
import 'project_editor_sheet.dart';
import 'project_entry_sheet.dart';

/// One project's ledger: what it has cost, where that money went, and every
/// line that got it there.
class ProjectDetailScreen extends StatelessWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  static Future<void> open(BuildContext context, String projectId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProjectDetailScreen(projectId: projectId),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ProjectSummary p) async {
    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this project?'),
        content: Text(
          p.entryCount == 0
              ? '"${p.name}" will be removed.'
              : '"${p.name}" and all ${p.entryCount} '
                    '${p.entryCount == 1 ? 'entry' : 'entries'} '
                    '(${Money.format(p.total)}) will be removed. This cannot '
                    'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete project'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await store.deleteProject(p.id);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Deleted ${p.name}')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final summary = store.projectById(projectId);
    final viz = context.viz;

    if (summary == null) {
      // Deleted on another device and removed by a pull while this page was
      // open. Say so rather than showing an empty ledger.
      return Scaffold(
        appBar: AppBar(title: const Text('Project')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_off_outlined,
                  size: 34,
                  color: viz.inkMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  'This project is no longer here',
                  textAlign: TextAlign.center,
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'It was deleted, on this device or another one.',
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall?.copyWith(
                    color: viz.inkSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to projects'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final days = summary.byDay;
    final stages = summary.byStage;

    return Scaffold(
      appBar: AppBar(
        title: Text(summary.name, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) => switch (value) {
              'edit' => ProjectEditorSheet.show(
                context,
                existing: summary.project,
              ),
              'delete' => _confirmDelete(context, summary),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit project'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Delete project'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            ProjectEntrySheet.show(context, projectId: summary.id),
        backgroundColor: viz.series,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add entry'),
      ),
      body: ScreenIntro(
        child: RefreshIndicator(
          onRefresh: store.refresh,
          color: viz.series,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.gutter,
              10,
              AppSizes.gutter,
              120,
            ),
            children: [
              Entrance(index: 0, child: _TotalCard(summary: summary)),
              if (summary.project.note.trim().isNotEmpty) ...[
                const SizedBox(height: AppSizes.gap),
                Entrance(
                  index: 1,
                  child: SectionCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.sticky_note_2_outlined,
                          size: 17,
                          color: viz.inkMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            summary.project.note.trim(),
                            style: context.text.bodySmall?.copyWith(
                              color: viz.inkSecondary,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (stages.isNotEmpty) ...[
                const SizedBox(height: AppSizes.gap),
                Entrance(
                  index: 2,
                  child: SectionCard(
                    title: 'Where the money went',
                    subtitle:
                        '${stages.length} ${stages.length == 1 ? 'kind' : 'kinds'} '
                        'of expense',
                    child: Column(
                      children: [
                        for (var i = 0; i < stages.length; i++) ...[
                          if (i > 0) const SizedBox(height: 16),
                          _StageRow(
                            stage: stages[i],
                            share: stages[i].shareOf(summary.total),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSizes.gap),
              if (days.isEmpty)
                Entrance(
                  index: 3,
                  child: SectionCard(
                    child: _NoEntriesYet(
                      onAdd: () => ProjectEntrySheet.show(
                        context,
                        projectId: summary.id,
                      ),
                    ),
                  ),
                )
              else
                Entrance(
                  index: 3,
                  child: SectionCard(
                    title: 'Everything logged',
                    subtitle:
                        '${summary.entryCount} '
                        '${summary.entryCount == 1 ? 'entry' : 'entries'} · '
                        'newest first',
                    child: Column(
                      children: [
                        for (var d = 0; d < days.length; d++) ...[
                          if (d > 0) const SizedBox(height: 18),
                          _DayHeader(day: days[d].day, total: days[d].total),
                          for (final entry in days[d].entries) ...[
                            const SizedBox(height: 10),
                            _EntryRow(
                              entry: entry,
                              onTap: () => ProjectEntrySheet.show(
                                context,
                                projectId: summary.id,
                                existing: entry,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the job has cost, against the estimate when there is one.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary});

  final ProjectSummary summary;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final estimate = summary.estimate;
    final style = bandStyle(context, summary.band);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPENT SO FAR',
            style: context.text.labelSmall?.copyWith(
              color: viz.inkMuted,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedAmount(
            value: summary.total,
            formatter: Money.format,
            style: context.text.displaySmall?.copyWith(
              color: viz.inkPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Started ${Dates.dayMonthYear(summary.project.startedOn)}',
            style: context.text.bodySmall?.copyWith(color: viz.inkSecondary),
          ),
          if (estimate != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Estimate ${Money.format(estimate)}',
                    style: context.text.labelSmall?.copyWith(
                      color: viz.inkSecondary,
                    ),
                  ),
                ),
                Text(
                  '${(summary.progress! * 100).round()}%',
                  style: context.text.labelSmall?.copyWith(
                    color: viz.inkSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 11,
                color: style.track,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: summary.meterFraction),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: style.fill,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(style.icon, size: 15, color: style.fill),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    summary.overEstimate
                        ? '${summary.bandLabel} by '
                              '${Money.format(-summary.remaining!)}'
                        : '${summary.bandLabel} · '
                              '${Money.format(summary.remaining!)} still to go',
                    style: context.text.bodySmall?.copyWith(
                      color: summary.overEstimate
                          ? viz.critical
                          : viz.inkSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: viz.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.savings_outlined,
                  size: 15,
                  color: viz.inkMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Paid from savings · not counted in monthly spending',
                    style: context.text.labelSmall?.copyWith(
                      color: viz.inkSecondary,
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

/// One stage's total, ranked. Same form as the category breakdown on the
/// Overview tab: bars in a single hue with the amount labelled on the row.
class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.share});

  final StageTotal stage;

  /// Both the bar length and the number beside it. They have to be the same
  /// figure — a bar drawn to a different scale than its own label misreads at a
  /// glance, which is the only way a breakdown is ever read.
  final double share;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final percent = share * 100;
    final percentLabel = percent > 0 && percent < 1
        ? '<1%'
        : '${percent.round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                stage.stage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: viz.inkPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Money.format(stage.total),
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: viz.inkPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(child: ShareMeter(share: share)),
            const SizedBox(width: 10),
            SizedBox(
              width: 34,
              child: Text(
                percentLabel,
                textAlign: TextAlign.right,
                style: context.text.labelSmall?.copyWith(
                  color: viz.inkSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${stage.count} ${stage.count == 1 ? 'entry' : 'entries'}',
          style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.total});

  final DateTime day;
  final double total;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Row(
      children: [
        Expanded(
          child: Text(
            Dates.relativeDay(day),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(
              color: viz.inkMuted,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          Money.format(total),
          style: context.text.labelSmall?.copyWith(
            color: viz.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// One line of the ledger. A measured buy shows the arithmetic underneath, so
/// the rate paid on the day stays visible months later.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onTap});

  final ProjectEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final measure = entry.measure;
    final note = entry.note.trim();

    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: viz.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: viz.inkPrimary,
                    ),
                  ),
                  if (measure != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      measure,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: viz.series,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: viz.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              Money.format(entry.amount),
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: viz.inkPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoEntriesYet extends StatelessWidget {
  const _NoEntriesYet({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.receipt_long_outlined, size: 30, color: viz.inkMuted),
        const SizedBox(height: 12),
        Text(
          'Nothing logged yet',
          textAlign: TextAlign.center,
          style: context.text.titleSmall?.copyWith(color: viz.inkPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Add the first load of bricks, bag of cement or day of labour. '
          'Enter a quantity and a rate and the total works itself out.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(
            color: viz.inkSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add the first entry'),
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
