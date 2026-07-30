import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../state/expense_store.dart';
import '../widgets/category_icon.dart';

/// Add or edit one expense. Amount first (it is what the user came to type),
/// then category, then date, then an optional note.
class ExpenseEditorSheet extends StatefulWidget {
  const ExpenseEditorSheet({super.key, this.existing});

  final Expense? existing;

  static Future<void> show(BuildContext context, {Expense? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ExpenseEditorSheet(existing: existing),
    );
  }

  @override
  State<ExpenseEditorSheet> createState() => _ExpenseEditorSheetState();
}

class _ExpenseEditorSheetState extends State<ExpenseEditorSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late ExpenseCategory _category;
  late DateTime _date;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amount = TextEditingController(
      text: existing == null ? '' : _trimAmount(existing.amount),
    );
    _note = TextEditingController(text: existing?.note ?? '');
    _category = existing?.category ?? ExpenseCategory.groceries;
    _date = existing?.date ?? dayOnly(DateTime.now());
  }

  static String _trimAmount(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 3),
      lastDate: dayOnly(now),
      helpText: 'Date of expense',
    );
    if (picked != null) setState(() => _date = dayOnly(picked));
  }

  Future<void> _save() async {
    final raw = _amount.text.replaceAll(',', '').trim();
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      setState(() => _error = 'Enter an amount greater than 0');
      return;
    }

    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final expense =
        widget.existing?.copyWith(
          amount: parsed,
          category: _category,
          date: _date,
          note: _note.text,
        ) ??
        Expense(
          id: store.newId(),
          amount: parsed,
          category: _category,
          date: _date,
          note: _note.text,
        );

    await store.save(expense);
    // Never save an entry out of sight: pull the window onto its date.
    store.focusOn(expense.date);

    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _isEditing
              ? 'Updated ${Money.format(expense.amount)} · ${expense.category.label}'
              : 'Added ${Money.format(expense.amount)} · ${expense.category.label}',
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    await store.delete(existing.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Expense deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.save(existing),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final today = dayOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);

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
                    _isEditing ? 'Edit expense' : 'Add expense',
                    style: context.text.titleMedium?.copyWith(fontSize: 19),
                  ),
                ),
                if (_isEditing)
                  IconButton(
                    onPressed: _delete,
                    tooltip: 'Delete expense',
                    icon: const Icon(Icons.delete_outline_rounded),
                    style: IconButton.styleFrom(
                      foregroundColor: viz.critical,
                      backgroundColor: viz.critical.withValues(alpha: 0.10),
                    ),
                  ),
              ],
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
                crossAxisAlignment: CrossAxisAlignment.center,
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
                      autofocus: !_isEditing,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      textInputAction: TextInputAction.done,
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
            const SizedBox(height: 22),
            _FieldLabel('Category'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 14,
              children: [
                for (final category in ExpenseCategory.values)
                  _CategoryOption(
                    category: category,
                    selected: category == _category,
                    onTap: () => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            _FieldLabel('Date'),
            const SizedBox(height: 12),
            // Wrap, not Row: at large text scales the third chip drops to its
            // own line instead of being squeezed past its label.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DateChip(
                  label: 'Today',
                  selected: _date == today,
                  onTap: () => setState(() => _date = today),
                ),
                _DateChip(
                  label: 'Yesterday',
                  selected: _date == yesterday,
                  onTap: () => setState(() => _date = yesterday),
                ),
                _DateChip(
                  label: _date == today || _date == yesterday
                      ? 'Pick a date'
                      : Dates.dayMonthYear(_date),
                  icon: Icons.calendar_month_rounded,
                  selected: _date != today && _date != yesterday,
                  onTap: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _FieldLabel('Note (optional)'),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. weekly grocery run',
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: viz.series,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _isEditing ? 'Save changes' : 'Add expense',
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: context.text.labelSmall?.copyWith(
        color: context.viz.inkMuted,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _CategoryOption extends StatelessWidget {
  const _CategoryOption({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ExpenseCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            CategoryIcon(
              category: category,
              size: 52,
              iconSize: 24,
              selected: selected,
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
                color: selected
                    ? context.viz.inkPrimary
                    : context.viz.inkSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? viz.series.withValues(alpha: context.isDarkMode ? 0.24 : 0.12)
              : viz.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? viz.series : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? viz.series : viz.inkSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelLarge?.copyWith(
                  color: selected ? viz.series : viz.inkSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
