import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../state/expense_store.dart';
import '../widgets/empty_state.dart';
import '../widgets/expense_tile.dart';
import '../widgets/period_filter_bar.dart';
import '../widgets/pressable.dart';
import '../widgets/section_card.dart';
import 'expense_editor_sheet.dart';

/// The table view of the data: every expense in the selected period, grouped by
/// day, searchable, filterable by category. Anything a chart only shows as a
/// mark is readable here as a number.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

/// How the list is ordered.
enum _Sort {
  newest('Newest first', Icons.schedule_rounded),
  biggest('Biggest first', Icons.trending_down_rounded);

  const _Sort(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  ExpenseCategory? _category;

  /// Search the whole history instead of just the selected period.
  bool _allTime = false;
  _Sort _sort = _Sort.newest;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Expense expense) {
    if (_category != null && expense.category != _category) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return expense.item.toLowerCase().contains(q) ||
        expense.note.toLowerCase().contains(q) ||
        expense.category.label.toLowerCase().contains(q) ||
        expense.amount.round().toString().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final store = context.watch<ExpenseStore>();
    final summary = store.summary;

    final source = _allTime ? store.allExpenses : summary.expenses;
    final filtered = source.where(_matches).toList();
    if (_sort == _Sort.biggest) {
      filtered.sort((a, b) => b.amount.compareTo(a.amount));
    }
    final filteredTotal = filtered.fold<double>(0, (s, e) => s + e.amount);

    // Day totals, then a flat row list: header, its expenses, next header.
    final dayTotals = <DateTime, double>{};
    for (final expense in filtered) {
      dayTotals[expense.date] = (dayTotals[expense.date] ?? 0) + expense.amount;
    }
    final rows = <Object>[];
    DateTime? lastDay;
    for (final expense in filtered) {
      if (expense.date != lastDay) {
        lastDay = expense.date;
        rows.add(_DayHeader(day: expense.date, total: dayTotals[lastDay] ?? 0));
      }
      rows.add(expense);
    }

    return RefreshIndicator(
      onRefresh: store.refresh,
      color: viz.series,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.gutter,
              6,
              AppSizes.gutter,
              0,
            ),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Expenses',
                            style: context.text.titleMedium?.copyWith(
                              fontSize: 19,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _allTime
                                ? '${filtered.length} of ${store.totalEntryCount} '
                                      'all time · ${Money.format(filteredTotal)}'
                                : '${filtered.length} of ${summary.count} in this '
                                      '${store.period.noun} · ${Money.format(filteredTotal)}',
                            style: context.text.bodySmall?.copyWith(
                              color: viz.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const PeriodFilterBar(),
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search items, notes, categories, amounts',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: viz.inkMuted,
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                // Wrap, not Row: at large text scales the sort chip drops to a
                // second line instead of overflowing.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ToolChip(
                      icon: _allTime
                          ? Icons.all_inclusive_rounded
                          : Icons.calendar_today_rounded,
                      label: _allTime
                          ? 'All time'
                          : 'This ${store.period.noun}',
                      active: _allTime,
                      onTap: () => setState(() => _allTime = !_allTime),
                    ),
                    _ToolChip(
                      icon: _sort.icon,
                      label: _sort.label,
                      active: _sort != _Sort.newest,
                      onTap: () => setState(
                        () => _sort = _sort == _Sort.newest
                            ? _Sort.biggest
                            : _Sort.newest,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.gutter),
              child: Row(
                children: [
                  _FilterPill(
                    label: 'All',
                    selected: _category == null,
                    onTap: () => setState(() => _category = null),
                  ),
                  for (final category in ExpenseCategory.values) ...[
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: category.label,
                      dotColor: category.colorOf(context),
                      selected: _category == category,
                      onTap: () => setState(
                        () =>
                            _category = _category == category ? null : category,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (rows.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.gutter,
                24,
                AppSizes.gutter,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionCard(
                  child: summary.count == 0
                      ? EmptyState(
                          icon: Icons.receipt_long_rounded,
                          title: 'Nothing logged in this ${store.period.noun}',
                          message:
                              'Step back with the arrows above, or add a new '
                              'expense.',
                          actionLabel: 'Add expense',
                          onAction: () => ExpenseEditorSheet.show(context),
                        )
                      : const EmptyState(
                          icon: Icons.filter_alt_off_rounded,
                          title: 'No matches',
                          message: 'Try a different search term or category.',
                        ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.gutter,
                14,
                AppSizes.gutter,
                110,
              ),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  if (row is _DayHeader) {
                    return Padding(
                      padding: EdgeInsets.only(
                        top: index == 0 ? 0 : 18,
                        bottom: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              Dates.relativeDay(row.day),
                              style: context.text.labelSmall?.copyWith(
                                color: viz.inkSecondary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          Text(
                            Money.format(row.total),
                            style: context.text.labelSmall?.copyWith(
                              color: viz.inkMuted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final expense = row as Expense;
                  return Dismissible(
                    key: ValueKey(expense.id),
                    // Right: log the same thing again today. Left: delete.
                    direction: DismissDirection.horizontal,
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 18),
                      decoration: BoxDecoration(
                        color: viz.series.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded, size: 18, color: viz.series),
                          const SizedBox(width: 8),
                          Text(
                            'Add again',
                            style: context.text.labelLarge?.copyWith(
                              color: viz.series,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    secondaryBackground: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 18),
                      decoration: BoxDecoration(
                        color: viz.critical.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: viz.critical,
                      ),
                    ),
                    // The row only leaves the list once the server confirms the
                    // delete; if it fails the row springs back with the reason.
                    // Duplicating always returns false — the original stays.
                    confirmDismiss: (direction) async {
                      final messenger = ScaffoldMessenger.of(context);
                      if (direction == DismissDirection.startToEnd) {
                        try {
                          await store.duplicate(expense);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Added ${expense.title} again '
                                '(${Money.format(expense.amount)})',
                              ),
                            ),
                          );
                        } catch (error) {
                          messenger.showSnackBar(
                            SnackBar(content: Text(describeError(error))),
                          );
                        }
                        return false;
                      }
                      try {
                        await store.remove(expense.id);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Deleted ${expense.title}'),
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () => store.restore(expense),
                            ),
                          ),
                        );
                        return true;
                      } catch (error) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(describeError(error))),
                        );
                        return false;
                      }
                    },
                    child: ExpenseTile(
                      expense: expense,
                      showDate: false,
                      onTap: () =>
                          ExpenseEditorSheet.show(context, existing: expense),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeader {
  const _DayHeader({required this.day, required this.total});

  final DateTime day;
  final double total;
}

/// A small toggle above the list: search scope and sort order. Both show their
/// current state as words, not just an icon.
class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? viz.series.withValues(alpha: context.isDarkMode ? 0.22 : 0.10)
              : viz.surfaceAlt,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: active ? viz.series : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? viz.series : viz.inkSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.text.labelSmall?.copyWith(
                color: active ? viz.series : viz.inkSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? viz.inkPrimary : viz.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: selected ? viz.inkPrimary : viz.hairline),
        ),
        child: Row(
          children: [
            if (dotColor != null) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: context.text.labelLarge?.copyWith(
                color: selected ? viz.surface : viz.inkSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
