import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/period.dart';
import '../state/expense_store.dart';
import '../state/theme_controller.dart';
import '../widgets/category_breakdown.dart';
import '../widgets/empty_state.dart';
import '../widgets/entrance.dart';
import '../widgets/expense_tile.dart';
import '../widgets/hero_total_card.dart';
import '../widgets/period_filter_bar.dart';
import '../widgets/section_card.dart';
import '../widgets/trend_bar_chart.dart';
import 'expense_editor_sheet.dart';
import 'home_shell.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenTab});

  final TabOpener onOpenTab;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final summary = store.summary;
    final scope = store.relativeRangeLabel ?? store.rangeLabel;

    final trendTitle = switch (store.period) {
      Period.week => 'Spending by day',
      Period.month => 'Spending by week',
      Period.year => 'Spending by month',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.gutter,
        6,
        AppSizes.gutter,
        110,
      ),
      children: [
        const _DashboardHeader(),
        const SizedBox(height: 20),
        const Entrance(index: 0, child: PeriodFilterBar()),
        const SizedBox(height: 18),
        Entrance(
          index: 1,
          child: HeroTotalCard(
            summary: summary,
            label: 'Total spent · $scope',
          ),
        ),
        const SizedBox(height: AppSizes.gap),
        Entrance(
          index: 2,
          child: SectionCard(
            title: trendTitle,
            subtitle: summary.isEmpty ? null : 'Tap a bar to read its total',
            child: summary.isEmpty
                ? const EmptyState(
                    compact: true,
                    icon: Icons.bar_chart_rounded,
                    title: 'Nothing logged yet',
                    message: 'Add an expense and the trend appears here.',
                  )
                : TrendBarChart(buckets: summary.buckets),
          ),
        ),
        const SizedBox(height: AppSizes.gap),
        Entrance(
          index: 3,
          child: SectionCard(
            title: 'Where it went',
            subtitle: summary.isEmpty
                ? null
                : '${summary.slices.length} of 8 categories used',
            trailing: summary.slices.length > 5
                ? CardAction(label: 'All', onTap: () => onOpenTab(1))
                : null,
            child: summary.isEmpty
                ? const EmptyState(
                    compact: true,
                    icon: Icons.donut_large_rounded,
                    title: 'No breakdown yet',
                    message:
                        'Every expense you add is grouped by category here.',
                  )
                : CategoryBreakdown(slices: summary.slices, maxRows: 5),
          ),
        ),
        const SizedBox(height: AppSizes.gap),
        Entrance(
          index: 4,
          child: SectionCard(
            title: 'Recent expenses',
            trailing: CardAction(label: 'See all', onTap: () => onOpenTab(2)),
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
            child: summary.expenses.isEmpty
                ? EmptyState(
                    compact: true,
                    icon: Icons.receipt_long_rounded,
                    title: 'No expenses in this period',
                    message: 'Tap + to log what you just spent.',
                    actionLabel: 'Add expense',
                    onAction: () => ExpenseEditorSheet.show(context),
                  )
                : Column(
                    children: [
                      for (final expense in summary.expenses.take(5))
                        ExpenseTile(
                          expense: expense,
                          onTap: () => ExpenseEditorSheet.show(
                            context,
                            existing: expense,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    if (now.hour < 21) return 'Good evening';
    return 'Good night';
  }

  Future<void> _confirmClear(BuildContext context) async {
    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all expenses?'),
        content: Text(
          'This deletes all ${store.totalEntryCount} entries stored on this '
          'device, including the sample data. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.viz.critical,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.clearAll();
    messenger.showSnackBar(
      const SnackBar(content: Text('All expenses cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final theme = context.watch<ThemeController>();
    final now = DateTime.now();

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(now),
                style: context.text.titleMedium?.copyWith(fontSize: 19),
              ),
              const SizedBox(height: 2),
              Text(
                Dates.weekdayDayMonth(now),
                style: context.text.bodySmall?.copyWith(color: viz.inkMuted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: theme.cycle,
          tooltip: theme.label,
          icon: Icon(theme.icon, size: 21),
          style: IconButton.styleFrom(
            backgroundColor: viz.surface,
            foregroundColor: viz.inkSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
              side: BorderSide(color: viz.hairline),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'More',
          position: PopupMenuPosition.under,
          color: viz.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: viz.hairline),
          ),
          onSelected: (value) {
            if (value == 'clear') _confirmClear(context);
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(
                    Icons.delete_sweep_rounded,
                    size: 19,
                    color: viz.critical,
                  ),
                  const SizedBox(width: 10),
                  const Flexible(child: Text('Clear all expenses')),
                ],
              ),
            ),
          ],
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: viz.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: viz.hairline),
            ),
            child: Icon(
              Icons.more_horiz_rounded,
              size: 21,
              color: viz.inkSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
