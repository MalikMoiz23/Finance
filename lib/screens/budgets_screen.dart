import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../models/budget.dart';
import '../models/expense_category.dart';
import '../state/expense_store.dart';
import '../widgets/budget_meter.dart';
import '../widgets/category_icon.dart';
import '../widgets/entrance.dart';
import '../widgets/pressable.dart';
import '../widgets/section_card.dart';
import '../widgets/skeleton.dart';

/// Monthly limits per category.
///
/// Deliberately has no period filter: budgets are monthly by definition, so this
/// screen always reports the current calendar month and says so in the header.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final statuses = store.budgetStatuses;
    final withoutLimit = ExpenseCategory.values
        .where((c) => store.budgetFor(c) == null)
        .toList();
    final loadingEmpty = store.isLoading && store.totalEntryCount == 0;

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
                'Budgets',
                style: context.text.titleMedium?.copyWith(fontSize: 19),
              ),
              const SizedBox(height: 2),
              Text(
                'Monthly limits · ${store.budgetMonthLabel}',
                style: context.text.bodySmall?.copyWith(
                  color: context.viz.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (loadingEmpty)
            Entrance(
              index: 0,
              child: SectionCard(child: const RowsSkeleton(rows: 3)),
            )
          else ...[
            if (statuses.isNotEmpty) ...[
              Entrance(index: 0, child: _OverallCard(store: store)),
              const SizedBox(height: AppSizes.gap),
              Entrance(
                index: 1,
                child: SectionCard(
                  title: 'Where you stand',
                  subtitle: '${statuses.length} of 8 categories have a limit',
                  child: Column(
                    children: [
                      for (var i = 0; i < statuses.length; i++) ...[
                        if (i > 0) const SizedBox(height: 18),
                        BudgetRow(
                          status: statuses[i],
                          onTap: () => BudgetSheet.show(
                            context,
                            category: statuses[i].category,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.gap),
            ] else
              Entrance(
                index: 0,
                child: SectionCard(
                  child: _NoBudgetsYet(
                    onStart: () => BudgetSheet.show(
                      context,
                      category: ExpenseCategory.groceries,
                    ),
                  ),
                ),
              ),
            if (withoutLimit.isNotEmpty) ...[
              if (statuses.isEmpty) const SizedBox(height: AppSizes.gap),
              Entrance(
                index: 2,
                child: SectionCard(
                  title: 'No limit set',
                  subtitle: 'Tap a category to give it a monthly limit',
                  child: Column(
                    children: [
                      for (var i = 0; i < withoutLimit.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        _UnsetRow(
                          category: withoutLimit[i],
                          spent: store.spentThisMonth(withoutLimit[i]),
                          onTap: () => BudgetSheet.show(
                            context,
                            category: withoutLimit[i],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.store});

  final ExpenseStore store;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final budgeted = store.totalBudgeted;
    final spent = store.spentAgainstBudgets;
    final ratio = budgeted <= 0 ? 0.0 : spent / budgeted;
    final band = switch (ratio) {
      >= 1 => BudgetBand.overBudget,
      >= 0.8 => BudgetBand.closeToLimit,
      _ => BudgetBand.onTrack,
    };
    final over = store.overBudgetCount;

    return SectionCard(
      child: Row(
        children: [
          BudgetRing(fraction: ratio, band: band),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${Money.format(spent)} of ${Money.format(budgeted)}',
                  style: context.text.titleSmall?.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 3),
                Text(
                  over == 0
                      ? '${Money.format((budgeted - spent).clamp(0, double.infinity))} left across your limits'
                      : '$over ${over == 1 ? 'category is' : 'categories are'} over budget',
                  style: context.text.bodySmall?.copyWith(
                    color: over == 0 ? viz.inkSecondary : viz.critical,
                    fontWeight: over == 0 ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${store.daysLeftThisMonth} '
                  '${store.daysLeftThisMonth == 1 ? 'day' : 'days'} left in '
                  '${store.budgetMonthLabel}',
                  style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsetRow extends StatelessWidget {
  const _UnsetRow({
    required this.category,
    required this.spent,
    required this.onTap,
  });

  final ExpenseCategory category;
  final double spent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CategoryIcon(category: category, size: 36, iconSize: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: viz.inkPrimary,
                ),
              ),
            ),
            if (spent > 0)
              Text(
                '${Money.compact(spent)} spent',
                style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
              ),
            const SizedBox(width: 8),
            Icon(Icons.add_circle_outline_rounded, size: 19, color: viz.series),
          ],
        ),
      ),
    );
  }
}

class _NoBudgetsYet extends StatelessWidget {
  const _NoBudgetsYet({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: viz.series.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(Icons.savings_rounded, color: viz.series, size: 27),
        ),
        const SizedBox(height: 14),
        Text('No limits yet', style: context.text.titleSmall),
        const SizedBox(height: 6),
        Text(
          'Set a monthly limit on a category and this screen tracks how much of '
          'it you have used, and what you can still spend per day.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(color: viz.inkMuted),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Set your first limit'),
          style: FilledButton.styleFrom(
            backgroundColor: viz.series,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }
}

/// Set, change or remove one category's monthly limit.
class BudgetSheet extends StatefulWidget {
  const BudgetSheet({super.key, required this.category});

  final ExpenseCategory category;

  static Future<void> show(
    BuildContext context, {
    required ExpenseCategory category,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BudgetSheet(category: category),
    );
  }

  @override
  State<BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<BudgetSheet> {
  late final TextEditingController _amount;
  late ExpenseCategory _category;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _category = widget.category;
    final existing = context.read<ExpenseStore>().budgetFor(_category);
    _amount = TextEditingController(
      text: existing == null ? '' : '${existing.monthlyLimit.round()}',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _pickCategory(ExpenseCategory category) {
    final existing = context.read<ExpenseStore>().budgetFor(category);
    setState(() {
      _category = category;
      _amount.text = existing == null ? '' : '${existing.monthlyLimit.round()}';
      _error = null;
    });
  }

  Future<void> _save() async {
    final parsed = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (parsed == null || parsed <= 0) {
      setState(() => _error = 'Enter a limit greater than 0');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await store.saveBudget(_category, parsed);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${_category.label} limit set to ${Money.format(parsed)} a month',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await store.removeBudget(_category);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('${_category.label} limit removed')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final store = context.watch<ExpenseStore>();
    final existing = store.budgetFor(_category);
    final spent = store.spentThisMonth(_category);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    existing == null ? 'Set a monthly limit' : 'Edit the limit',
                    style: context.text.titleMedium?.copyWith(fontSize: 19),
                  ),
                ),
                if (existing != null)
                  IconButton(
                    onPressed: _saving ? null : _remove,
                    tooltip: 'Remove limit',
                    icon: const Icon(Icons.delete_outline_rounded),
                    style: IconButton.styleFrom(
                      foregroundColor: viz.critical,
                      backgroundColor: viz.critical.withValues(alpha: 0.10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Already spent ${Money.format(spent)} on ${_category.label} in '
              '${store.budgetMonthLabel}.',
              style: context.text.bodySmall?.copyWith(color: viz.inkMuted),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                color: viz.surfaceAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _error == null ? viz.hairline : viz.critical,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    Money.symbol,
                    style: context.text.titleMedium?.copyWith(
                      color: viz.inkMuted,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                      ],
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      style: context.text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1,
                        color: viz.inkPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '0',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        hintStyle: context.text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: viz.inkMuted.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '/ month',
                    style: context.text.bodySmall?.copyWith(
                      color: viz.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: viz.critical,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: context.text.bodySmall?.copyWith(
                        color: viz.critical,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in const [5000, 10000, 20000, 30000, 50000])
                  _Preset(
                    amount: preset,
                    selected: _amount.text == '$preset',
                    onTap: () => setState(() {
                      _amount.text = '$preset';
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              'CATEGORY',
              style: context.text.labelSmall?.copyWith(
                color: viz.inkMuted,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 14,
              children: [
                for (final category in ExpenseCategory.values)
                  SizedBox(
                    width: 74,
                    child: Pressable(
                      onTap: () => _pickCategory(category),
                      child: Column(
                        children: [
                          CategoryIcon(
                            category: category,
                            size: 48,
                            iconSize: 22,
                            selected: category == _category,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            category.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(
                              fontSize: 11,
                              height: 1.25,
                              color: category == _category
                                  ? viz.inkPrimary
                                  : viz.inkSecondary,
                              fontWeight: category == _category
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: viz.series,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: viz.series.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        existing == null ? 'Set limit' : 'Save limit',
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
    );
  }
}

class _Preset extends StatelessWidget {
  const _Preset({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final int amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? viz.series.withValues(alpha: context.isDarkMode ? 0.24 : 0.12)
              : viz.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? viz.series : Colors.transparent),
        ),
        child: Text(
          Money.format(amount),
          style: context.text.labelLarge?.copyWith(
            color: selected ? viz.series : viz.inkSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
