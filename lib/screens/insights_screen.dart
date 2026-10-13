import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/analytics.dart';
import '../models/expense.dart';
import '../models/item_catalog.dart';
import '../state/expense_store.dart';
import '../widgets/category_breakdown.dart';
import '../widgets/category_icon.dart';
import '../widgets/delta_badge.dart';
import '../widgets/empty_state.dart';
import '../widgets/entrance.dart';
import '../widgets/expense_tile.dart';
import '../widgets/member_filter_bar.dart';
import '../widgets/period_filter_bar.dart';
import '../widgets/section_card.dart';
import '../widgets/spend_calendar.dart';
import '../widgets/stat_tile.dart';
import '../widgets/trend_bar_chart.dart';
import 'expense_editor_sheet.dart';
import 'member_breakdown.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  static const _weekdayShort = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _weekdayFull = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  List<TrendBucket> _weekdayBuckets(PeriodSummary summary, DateTime now) {
    final todayInRange = summary.range.contains(now);
    return [
      for (var i = 0; i < 7; i++)
        TrendBucket(
          shortLabel: _weekdayShort[i],
          fullLabel: _weekdayFull[i],
          total: summary.weekdayTotals[i],
          isCurrent: todayInRange && now.weekday == i + 1,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final summary = store.summary;
    final now = DateTime.now();
    // "this month" reads correctly mid-sentence; a month name keeps its case.
    final scope = store.relativeRangeLabel?.toLowerCase() ?? store.rangeLabel;
    final noun = store.period.noun;

    var busiest = 0;
    for (var i = 1; i < 7; i++) {
      if (summary.weekdayTotals[i] > summary.weekdayTotals[busiest]) {
        busiest = i;
      }
    }

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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Insights',
                      style: context.text.titleMedium?.copyWith(fontSize: 19),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Patterns behind the total',
                      style: context.text.bodySmall?.copyWith(
                        color: context.viz.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Entrance(index: 0, child: PeriodFilterBar()),
          if (store.hasMembers) ...[
            const SizedBox(height: 12),
            const Entrance(index: 0, child: MemberFilterBar()),
          ],
          if (store.isMemberFiltered) ...[
            const SizedBox(height: 10),
            MemberFilterNote(total: summary.total),
          ],
          const SizedBox(height: 18),
          if (summary.isEmpty)
            Entrance(
              index: 1,
              child: SectionCard(
                child: EmptyState(
                  icon: Icons.insights_rounded,
                  title: 'Nothing to analyse yet',
                  message: store.isMemberFiltered
                      ? 'Nothing logged for ${store.memberFilterLabel} in this '
                            '$noun. Pick Everyone to see the whole household.'
                      : 'Log a few expenses in this $noun and the patterns show '
                            'up here.',
                  actionLabel: 'Add expense',
                  onAction: () => ExpenseEditorSheet.show(context),
                ),
              ),
            )
          else ...[
            Entrance(
              index: 1,
              child: _StatGrid(summary: summary, busiestWeekday: busiest),
            ),
            const SizedBox(height: 12),
            Entrance(
              index: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: DeltaBadge(
                  percent: summary.deltaPercent,
                  comparedTo: 'last $noun',
                ),
              ),
            ),
            const SizedBox(height: AppSizes.gap),
            Entrance(
              index: 3,
              child: SectionCard(
                title: 'Where it went',
                subtitle: 'Share of $scope · change vs last $noun',
                child: CategoryBreakdown(
                  slices: summary.slices,
                  showDelta: true,
                  comparedTo: 'last $noun',
                ),
              ),
            ),
            if (store.hasMembers) ...[
              const SizedBox(height: AppSizes.gap),
              Entrance(
                index: 4,
                child: SectionCard(
                  title: 'Spent by person',
                  subtitle: 'Whole household · share of $scope · tap to filter',
                  child: MemberBreakdown(
                    rows: store.spendByMemberThisPeriod,
                    onSelect: store.setMemberFilter,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSizes.gap),
            Entrance(
              index: 5,
              child: SectionCard(
                title: 'Spending by weekday',
                subtitle: 'Which days cost the most',
                child: TrendBarChart(
                  buckets: _weekdayBuckets(summary, now),
                  plotHeight: 140,
                ),
              ),
            ),
            const SizedBox(height: AppSizes.gap),
            const Entrance(index: 6, child: _CalendarCard()),
            const SizedBox(height: AppSizes.gap),
            Entrance(index: 7, child: _TopItemsCard(summary: summary)),
            const SizedBox(height: AppSizes.gap),
            Entrance(
              index: 8,
              child: SectionCard(
                title: 'Biggest single spends',
                subtitle: 'Top ${summary.biggest.length} of ${summary.count}',
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
                child: Column(
                  children: [
                    for (final expense in summary.biggest)
                      ExpenseTile(
                        expense: expense,
                        onTap: () =>
                            ExpenseEditorSheet.show(context, existing: expense),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A month at a glance, and a way into a single day. Tapping a cell reveals
/// that day's total and its entries, so a spike is one tap from an explanation.
class _CalendarCard extends StatefulWidget {
  const _CalendarCard();

  @override
  State<_CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<_CalendarCard> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final store = context.watch<ExpenseStore>();
    final month = store.calendarMonth;
    final totals = store.dailyTotals(month);
    final selected = _selected;

    // A month change (period stepping) must not leave a stale day selected.
    if (selected != null &&
        (selected.year != month.year || selected.month != month.month)) {
      _selected = null;
    }

    final dayExpenses = selected == null
        ? const <Expense>[]
        : store.expensesOn(selected);
    final dayTotal = dayExpenses.fold<double>(0, (s, e) => s + e.amount);
    final activeDays = totals.values.where((v) => v > 0).length;

    return SectionCard(
      title: 'Spending calendar',
      subtitle: Dates.monthYear(month),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpendCalendar(
            month: month,
            dailyTotals: totals,
            selected: selected,
            onSelect: (day) => setState(() => _selected = day),
          ),
          const SizedBox(height: 14),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: selected == null
                ? Row(
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 15,
                        color: viz.inkMuted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          activeDays == 0
                              ? 'No spending logged this month yet.'
                              : 'Spent on $activeDays '
                                    '${activeDays == 1 ? 'day' : 'days'} — tap a '
                                    'day to see what it was.',
                          style: context.text.bodySmall?.copyWith(
                            color: viz.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: viz.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                Dates.weekdayDayMonth(selected),
                                style: context.text.titleSmall?.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Text(
                              dayExpenses.isEmpty
                                  ? 'Nothing spent'
                                  : '${Money.format(dayTotal)} · '
                                        '${dayExpenses.length} '
                                        '${dayExpenses.length == 1 ? 'entry' : 'entries'}',
                              style: context.text.bodySmall?.copyWith(
                                color: viz.inkSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final expense in dayExpenses)
                        ExpenseTile(
                          expense: expense,
                          showDate: false,
                          onTap: () => ExpenseEditorSheet.show(
                            context,
                            existing: expense,
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

/// "What do I actually keep buying" — grouped by the item name typed on each
/// expense, so chicken and petrol show up separately inside their categories.
class _TopItemsCard extends StatelessWidget {
  const _TopItemsCard({required this.summary});

  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final items = ItemCatalog.topItems(summary.expenses);

    if (items.isEmpty) {
      return SectionCard(
        title: 'Most bought',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'Name what you buy when you add an expense — "Chicken", "Petrol" — '
            'and the things you spend most on appear here.',
            style: context.text.bodySmall?.copyWith(color: viz.inkMuted),
          ),
        ),
      );
    }

    final biggest = items.first.total;
    return SectionCard(
      title: 'Most bought',
      subtitle: 'Top ${items.length} items by spend',
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Row(
              children: [
                CategoryIcon(
                  category: items[i].category,
                  size: 34,
                  iconSize: 17,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              items[i].name,
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
                            Money.format(items[i].total),
                            style: context.text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: viz.inkPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                height: 6,
                                color: viz.seriesTrack,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                    begin: 0,
                                    end: biggest <= 0
                                        ? 0
                                        : items[i].total / biggest,
                                  ),
                                  duration: const Duration(milliseconds: 560),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, value, _) =>
                                      FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: value,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: viz.series,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${items[i].count}×',
                            style: context.text.labelSmall?.copyWith(
                              color: viz.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.summary, required this.busiestWeekday});

  final PeriodSummary summary;
  final int busiestWeekday;

  @override
  Widget build(BuildContext context) {
    final busiestTotal = summary.weekdayTotals[busiestWeekday];

    final topSlice = summary.topSlice;

    // IntrinsicHeight bounds the cross axis, so the two tiles in a row match
    // heights even though the list itself is vertically unbounded.
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatTile(
                  label: 'TOTAL SPENT',
                  value: Money.format(summary.total),
                  caption: '${summary.count} entries',
                  icon: Icons.payments_rounded,
                  emphasis: true,
                  sparkline: summary.buckets.map((b) => b.total).toList(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'AVERAGE PER DAY',
                  value: Money.format(summary.dailyAverage),
                  caption: 'so far this ${summary.period.noun}',
                  icon: Icons.calendar_today_rounded,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatTile(
                  label: 'BIGGEST CATEGORY',
                  value: topSlice?.category.label ?? '—',
                  caption: topSlice == null
                      ? '—'
                      : '${Money.format(topSlice.total)} · '
                            '${(topSlice.share * 100).round()}%',
                  icon: Icons.category_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'PRICIEST WEEKDAY',
                  value: busiestTotal <= 0
                      ? '—'
                      : InsightsScreen._weekdayFull[busiestWeekday],
                  caption: busiestTotal <= 0 ? '—' : Money.format(busiestTotal),
                  icon: Icons.event_rounded,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
