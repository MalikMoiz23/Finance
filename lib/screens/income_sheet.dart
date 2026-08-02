import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../state/expense_store.dart';
import '../widgets/pressable.dart';

/// Set or update the pay for one month.
///
/// Pay is recorded per month rather than as one global figure, so entering a
/// raise changes this month onward and leaves last month's savings history
/// intact. Months without their own figure inherit the most recent earlier one.
class IncomeSheet extends StatefulWidget {
  const IncomeSheet({super.key, required this.month});

  final DateTime month;

  static Future<void> show(BuildContext context, {DateTime? month}) {
    final now = DateTime.now();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          IncomeSheet(month: month ?? DateTime(now.year, now.month)),
    );
  }

  @override
  State<IncomeSheet> createState() => _IncomeSheetState();
}

class _IncomeSheetState extends State<IncomeSheet> {
  late final TextEditingController _amount;
  late DateTime _month;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.month.year, widget.month.month);
    final store = context.read<ExpenseStore>();
    final existing =
        store.incomeRowFor(_month) ??
        (store.effectiveIncome(_month) == null
            ? null
            : null); // only prefill an exact match
    final carried = store.effectiveIncome(_month);
    _amount = TextEditingController(
      text: existing != null
          ? '${existing.amount.round()}'
          : carried != null
          ? '${carried.amount.round()}'
          : '',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _stepMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final now = DateTime.now();
    // No point setting pay for a month that has not started.
    if (next.isAfter(DateTime(now.year, now.month))) return;
    final store = context.read<ExpenseStore>();
    final row = store.incomeRowFor(next);
    final carried = store.effectiveIncome(next);
    HapticFeedback.selectionClick();
    setState(() {
      _month = next;
      _amount.text = row != null
          ? '${row.amount.round()}'
          : carried != null
          ? '${carried.amount.round()}'
          : '';
      _error = null;
    });
  }

  Future<void> _save() async {
    final parsed = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (parsed == null || parsed <= 0) {
      setState(() => _error = 'Enter your pay for the month');
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
      await store.saveIncome(_month, parsed);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Pay for ${Dates.monthYear(_month)} set to ${Money.format(parsed)}',
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
      await store.removeIncome(_month);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Pay for ${Dates.monthYear(_month)} removed')),
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
    final exact = store.incomeRowFor(_month);
    final carried = store.effectiveIncome(_month);
    final now = DateTime.now();
    final atCurrentMonth = _month.year == now.year && _month.month == now.month;

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
                    exact == null ? 'Set your monthly pay' : 'Update your pay',
                    style: context.text.titleMedium?.copyWith(fontSize: 19),
                  ),
                ),
                if (exact != null)
                  IconButton(
                    onPressed: _saving ? null : _remove,
                    tooltip: 'Remove this month\'s figure',
                    icon: const Icon(Icons.delete_outline_rounded),
                    style: IconButton.styleFrom(
                      foregroundColor: viz.critical,
                      backgroundColor: viz.critical.withValues(alpha: 0.10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Which month this figure belongs to.
            Row(
              children: [
                _StepButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _stepMonth(-1),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        Dates.monthYear(_month),
                        style: context.text.titleSmall?.copyWith(fontSize: 15),
                      ),
                      Text(
                        atCurrentMonth ? 'This month' : 'Earlier month',
                        style: context.text.labelSmall?.copyWith(
                          color: viz.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                _StepButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: atCurrentMonth ? null : () => _stepMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 16),

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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: viz.surfaceAlt,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: viz.inkMuted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      exact == null && carried != null
                          ? 'Right now this month uses '
                                '${Money.format(carried.amount)} carried '
                                'forward. Saving here fixes a figure for '
                                '${Dates.monthYear(_month)} only.'
                          : 'Later months reuse this figure until you set a '
                                'new one, so a raise never rewrites the months '
                                'before it.',
                      style: context.text.bodySmall?.copyWith(
                        color: viz.inkSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
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
                        exact == null ? 'Set pay' : 'Save pay',
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

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: viz.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: viz.hairline),
        ),
        child: Icon(
          icon,
          size: 22,
          color: onTap == null
              ? viz.inkMuted.withValues(alpha: 0.4)
              : viz.inkSecondary,
        ),
      ),
    );
  }
}
