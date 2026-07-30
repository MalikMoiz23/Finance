import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/analytics.dart';
import '../state/expense_store.dart';
import '../widgets/category_breakdown.dart';
import '../widgets/delta_badge.dart';
import '../widgets/empty_state.dart';
import '../widgets/entrance.dart';
import '../widgets/expense_tile.dart';
import '../widgets/period_filter_bar.dart';
import '../widgets/section_card.dart';
import '../widgets/stat_tile.dart';
import '../widgets/trend_bar_chart.dart';
import 'expense_editor_sheet.dart';

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

    return ListView(
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
        const SizedBox(height: 18),
        if (summary.isEmpty)
          Entrance(
            index: 1,
            child: SectionCard(
              child: EmptyState(
                icon: Icons.insights_rounded,
                title: 'Nothing to analyse yet',
                message:
                    'Log a few expenses in this $noun and the patterns show up '
                    'here.',
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
          const SizedBox(height: AppSizes.gap),
          Entrance(
            index: 4,
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
          Entrance(
            index: 5,
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
