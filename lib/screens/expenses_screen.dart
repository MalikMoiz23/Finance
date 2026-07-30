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

class _ExpensesScreenState extends State<ExpensesScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  ExpenseCategory? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Expense expense) {
    if (_category != null && expense.category != _category) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return expense.note.toLowerCase().contains(q) ||
        expense.category.label.toLowerCase().contains(q) ||
        expense.amount.round().toString().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final store = context.watch<ExpenseStore>();
    final summary = store.summary;

    final filtered = summary.expenses.where(_matches).toList();
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
                            '${filtered.length} of ${summary.count} in this '
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
                    hintText: 'Search notes, categories, amounts',
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
                    direction: DismissDirection.endToStart,
                    background: Container(
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
                    confirmDismiss: (_) async {
                      final messenger = ScaffoldMessenger.of(context);
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
