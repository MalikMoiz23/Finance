import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/csv_export.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../models/period.dart';
import '../state/auth_controller.dart';
import '../state/expense_store.dart';
import '../state/theme_controller.dart';
import '../models/budget.dart';
import '../widgets/budget_meter.dart';
import '../widgets/category_breakdown.dart';
import '../widgets/empty_state.dart';
import '../widgets/entrance.dart';
import '../widgets/expense_tile.dart';
import '../widgets/hero_total_card.dart';
import '../widgets/pay_card.dart';
import '../widgets/period_filter_bar.dart';
import '../widgets/pressable.dart';
import '../widgets/section_card.dart';
import '../widgets/skeleton.dart';
import '../widgets/trend_bar_chart.dart';
import 'expense_editor_sheet.dart';
import 'income_sheet.dart';
import 'home_shell.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenTab});

  final TabOpener onOpenTab;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final summary = store.summary;
    final scope = store.relativeRangeLabel ?? store.rangeLabel;

    // First load for this account: no cache to fall back on yet.
    final loadingEmpty = store.isLoading && store.totalEntryCount == 0;

    final trendTitle = switch (store.period) {
      Period.week => 'Spending by day',
      Period.month => 'Spending by week',
      Period.year => 'Spending by month',
    };

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
          const _DashboardHeader(),
          if (store.syncError != null) ...[
            const SizedBox(height: 14),
            _SyncBanner(message: store.syncError!, onRetry: store.refresh),
          ],
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
            child: PayCard(
              comparison: store.thisMonthVsLast,
              onEdit: () => IncomeSheet.show(context),
            ),
          ),
          const SizedBox(height: AppSizes.gap),
          Entrance(
            index: 3,
            child: _BudgetSummary(store: store, onOpenTab: onOpenTab),
          ),
          const SizedBox(height: AppSizes.gap),
          Entrance(
            index: 4,
            child: SectionCard(
              title: trendTitle,
              subtitle: summary.isEmpty ? null : 'Tap a bar to read its total',
              child: loadingEmpty
                  ? const _CardLoading(chart: true)
                  : summary.isEmpty
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
            index: 5,
            child: SectionCard(
              title: 'Where it went',
              subtitle: summary.isEmpty
                  ? null
                  : '${summary.slices.length} of 8 categories used',
              trailing: summary.slices.length > 5
                  ? CardAction(label: 'All', onTap: () => onOpenTab(1))
                  : null,
              child: loadingEmpty
                  ? const _CardLoading()
                  : summary.isEmpty
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
            index: 6,
            child: SectionCard(
              title: 'Recent expenses',
              trailing: CardAction(label: 'See all', onTap: () => onOpenTab(2)),
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
              child: loadingEmpty
                  ? const _CardLoading()
                  : summary.expenses.isEmpty
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
      ),
    );
  }
}

/// Loading placeholders shaped like the content they precede, so the card does
/// not resize when the data lands.
class _CardLoading extends StatelessWidget {
  const _CardLoading({this.chart = false});

  final bool chart;

  @override
  Widget build(BuildContext context) =>
      chart ? const ChartSkeleton() : const RowsSkeleton(rows: 3);
}

/// Budget state on the dashboard: a ring for the month overall, then the two
/// categories closest to their limit. Nudges you to set one if there are none.
class _BudgetSummary extends StatelessWidget {
  const _BudgetSummary({required this.store, required this.onOpenTab});

  final ExpenseStore store;
  final TabOpener onOpenTab;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final statuses = store.budgetStatuses;

    if (statuses.isEmpty) {
      return Pressable(
        onTap: () => onOpenTab(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: viz.surface,
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            border: Border.all(color: viz.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: viz.series.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.savings_rounded, size: 19, color: viz.series),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Set a monthly limit',
                      style: context.text.titleSmall?.copyWith(fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Track groceries, fuel or bills against a budget',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: viz.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: viz.inkMuted),
            ],
          ),
        ),
      );
    }

    final budgeted = store.totalBudgeted;
    final spent = store.spentAgainstBudgets;
    final ratio = budgeted <= 0 ? 0.0 : spent / budgeted;
    final band = switch (ratio) {
      >= 1 => BudgetBand.overBudget,
      >= 0.8 => BudgetBand.closeToLimit,
      _ => BudgetBand.onTrack,
    };
    final over = store.overBudgetCount;
    final shown = statuses.take(2).toList();

    return SectionCard(
      title: 'Budgets',
      subtitle:
          '${store.budgetMonthLabel} · ${store.daysLeftThisMonth} '
          '${store.daysLeftThisMonth == 1 ? 'day' : 'days'} left',
      trailing: CardAction(label: 'All', onTap: () => onOpenTab(3)),
      child: Column(
        children: [
          Row(
            children: [
              BudgetRing(fraction: ratio, band: band, size: 54),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${Money.format(spent)} of ${Money.format(budgeted)}',
                      style: context.text.titleSmall?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      over == 0
                          ? '${Money.format((budgeted - spent).clamp(0, double.infinity))} still available'
                          : '$over ${over == 1 ? 'category' : 'categories'} over budget',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: over == 0 ? viz.inkSecondary : viz.critical,
                        fontWeight: over == 0
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            BudgetRow(status: shown[i], dense: true, onTap: () => onOpenTab(3)),
          ],
        ],
      ),
    );
  }
}

/// Shown when the last fetch failed. The numbers on screen are the cached ones,
/// so the app stays readable — but they may be out of date.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: viz.critical.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 17, color: viz.critical),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(
                color: viz.critical,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          TextButton(
            onPressed: () => onRetry(),
            style: TextButton.styleFrom(
              foregroundColor: viz.critical,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 34),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
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
          'This permanently deletes all ${store.totalEntryCount} expenses in '
          'your account. It cannot be undone.',
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
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await store.clearAll();
      messenger.showSnackBar(
        const SnackBar(content: Text('All expenses deleted')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  /// Puts every expense on the clipboard as CSV — paste straight into Excel or
  /// Google Sheets. Copying avoids a file-picker dependency and works on web.
  Future<void> _copyCsv(BuildContext context) async {
    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final rows = store.allExpenses;
    if (rows.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing to export yet')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: expensesToCsv(rows)));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${rows.length} expenses copied — paste into a spreadsheet',
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final auth = context.read<AuthController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Your expenses stay saved in your account. You will need your email '
          'and password to get back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final theme = context.watch<ThemeController>();
    final user = context.watch<AuthController>().user;
    final now = DateTime.now();
    final greeting = user == null
        ? _greeting(now)
        : '${_greeting(now)}, ${user.firstName}';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
        // PopupMenuButton's `tooltip` does not give the button an accessible
        // name, so Semantics supplies one. The tooltip is left off: with both,
        // the name is emitted twice and a screen reader says it twice.
        Semantics(
          label: 'Account and data',
          button: true,
          container: true,
          child: PopupMenuButton<String>(
            key: const ValueKey('account_menu'),
            tooltip: '',
            position: PopupMenuPosition.under,
            color: viz.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: viz.hairline),
            ),
            onSelected: (value) => switch (value) {
              'export' => _copyCsv(context),
              'clear' => _confirmClear(context),
              'signout' => _confirmSignOut(context),
              _ => null,
            },
            itemBuilder: (_) => [
              if (user != null)
                PopupMenuItem<String>(
                  enabled: false,
                  height: 38,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        user.name.isEmpty ? 'Signed in' : user.name,
                        style: context.text.labelSmall?.copyWith(
                          color: viz.inkSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        user.email,
                        style: context.text.labelSmall?.copyWith(
                          color: viz.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'export',
                child: Row(
                  children: [
                    Icon(
                      Icons.table_view_rounded,
                      size: 19,
                      color: viz.inkSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Flexible(child: Text('Copy as spreadsheet')),
                  ],
                ),
              ),
              PopupMenuItem<String>(
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
              PopupMenuItem<String>(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 19,
                      color: viz.inkSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Flexible(child: Text('Log out')),
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
        ),
      ],
    );
  }
}
