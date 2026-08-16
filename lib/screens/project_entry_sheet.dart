import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../models/project.dart';
import '../models/project_catalog.dart';
import '../state/expense_store.dart';
import '../widgets/pressable.dart';

/// How the amount is arrived at.
enum EntryMode {
  /// One figure, typed straight in — a week of the mason's wages.
  total('Total', Icons.payments_rounded),

  /// Quantity times rate — 5,000 bricks at Rs 18.50.
  measured('Quantity × rate', Icons.calculate_rounded);

  const EntryMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Add or edit one line of a project's ledger.
///
/// Two shapes in one form. Bricks, cement and sand are bought by the unit at a
/// rate, and typing the two separately means the app can show what a brick cost
/// in June against what it costs now. Labour and fees are a single figure. The
/// toggle at the top picks the shape; everything below it is shared.
class ProjectEntrySheet extends StatefulWidget {
  const ProjectEntrySheet({super.key, required this.projectId, this.existing});

  final String projectId;
  final ProjectEntry? existing;

  static Future<void> show(
    BuildContext context, {
    required String projectId,
    ProjectEntry? existing,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          ProjectEntrySheet(projectId: projectId, existing: existing),
    );
  }

  @override
  State<ProjectEntrySheet> createState() => _ProjectEntrySheetState();
}

class _ProjectEntrySheetState extends State<ProjectEntrySheet> {
  late final TextEditingController _stage;
  late final TextEditingController _amount;
  late final TextEditingController _quantity;
  late final TextEditingController _unit;
  late final TextEditingController _rate;
  late final TextEditingController _note;
  final FocusNode _stageFocus = FocusNode();

  late EntryMode _mode;
  late DateTime _date;
  String? _error;
  bool _saving = false;
  bool _suggestionsOpen = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _mode = existing?.isMeasured ?? false ? EntryMode.measured : EntryMode.total;
    _stage = TextEditingController(text: existing?.stage ?? '');
    _amount = TextEditingController(
      text: existing == null || existing.isMeasured
          ? ''
          : _trim(existing.amount),
    );
    _quantity = TextEditingController(
      text: existing?.quantity == null ? '' : _trim(existing!.quantity!),
    );
    _unit = TextEditingController(text: existing?.unit ?? '');
    _rate = TextEditingController(
      text: existing?.rate == null ? '' : _trim(existing!.rate!),
    );
    _note = TextEditingController(text: existing?.note ?? '');
    _date = existing?.date ?? dayOnly(DateTime.now());

    _stageFocus.addListener(() {
      setState(() => _suggestionsOpen = _stageFocus.hasFocus);
    });
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  @override
  void dispose() {
    _stage.dispose();
    _amount.dispose();
    _quantity.dispose();
    _unit.dispose();
    _rate.dispose();
    _note.dispose();
    _stageFocus.dispose();
    super.dispose();
  }

  static double? _parse(TextEditingController field) =>
      double.tryParse(field.text.replaceAll(',', '').trim());

  /// The figure that will be saved: typed in total mode, computed in measured
  /// mode. Null until there is enough to work it out.
  double? get _resolvedAmount {
    if (_mode == EntryMode.total) {
      final typed = _parse(_amount);
      return typed != null && typed > 0 ? typed : null;
    }
    final quantity = _parse(_quantity);
    final rate = _parse(_rate);
    if (quantity == null || rate == null || quantity <= 0 || rate <= 0) {
      return null;
    }
    return ProjectEntry.totalOf(quantity, rate);
  }

  /// Typing the whole word gets the same help as tapping the chip: "Cement"
  /// fills in "bags". Only ever fills an empty unit, so it cannot overwrite a
  /// choice already made.
  void _onStageTyped(String value) {
    setState(() {
      _error = null;
      final unit = ProjectCatalog.unitFor(value);
      if (unit != null && _unit.text.trim().isEmpty) _unit.text = unit;
    });
  }

  void _applyStage(String stage) {
    HapticFeedback.selectionClick();
    setState(() {
      _stage.text = stage;
      // "Cement" is bought in bags, "Sand" by the trip. Filling the unit in
      // saves a tap and keeps the naming consistent across a whole project.
      final unit = ProjectCatalog.unitFor(stage);
      if (unit != null && _unit.text.trim().isEmpty) _unit.text = unit;
      _error = null;
      _suggestionsOpen = false;
    });
    _stageFocus.unfocus();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 10),
      lastDate: dayOnly(now),
      helpText: 'Date of this expense',
    );
    if (picked != null) setState(() => _date = dayOnly(picked));
  }

  /// Keeps the stage, unit and date, clears the numbers — a delivery of bricks
  /// followed by a delivery of sand is two entries, not two trips to the form.
  void _resetForNext() {
    setState(() {
      _amount.clear();
      _quantity.clear();
      _rate.clear();
      _note.clear();
      _error = null;
      _suggestionsOpen = false;
    });
  }

  Future<void> _save({bool keepOpen = false}) async {
    final stage = _stage.text.trim();
    if (stage.isEmpty) {
      setState(() => _error = 'Say what this was for — "Bricks", "Labour"');
      return;
    }
    final amount = _resolvedAmount;
    if (amount == null) {
      setState(
        () => _error = _mode == EntryMode.total
            ? 'Enter an amount greater than 0'
            : 'Enter a quantity and a rate, both greater than 0',
      );
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final measured = _mode == EntryMode.measured;
    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final existing = widget.existing;

    try {
      if (existing == null) {
        await store.addProjectEntry(
          projectId: widget.projectId,
          stage: stage,
          amount: amount,
          date: _date,
          quantity: measured ? _parse(_quantity) : null,
          unit: measured ? _unit.text : '',
          rate: measured ? _parse(_rate) : null,
          note: _note.text,
        );
      } else {
        await store.saveProjectEntry(
          existing.copyWith(
            stage: stage,
            amount: amount,
            date: _date,
            quantity: measured ? _parse(_quantity) : null,
            unit: measured ? _unit.text.trim() : '',
            rate: measured ? _parse(_rate) : null,
            note: _note.text.trim(),
          ),
        );
      }

      if (keepOpen && mounted) {
        _resetForNext();
        setState(() => _saving = false);
      } else {
        navigator.pop();
      }
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            '${existing == null ? 'Added' : 'Updated'} '
            '${Money.format(amount)} · $stage',
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

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await store.deleteProjectEntry(existing.id);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted ${existing.title}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restoreProjectEntry(existing),
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

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final store = context.watch<ExpenseStore>();
    final today = dayOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);

    final used = store.projectById(widget.projectId)?.usedStages ?? const [];
    final suggestions = _suggestionsOpen
        ? ProjectCatalog.suggestStages(query: _stage.text, used: used)
        : const <String>[];

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
                    _isEditing ? 'Edit entry' : 'Add to project',
                    style: context.text.titleMedium?.copyWith(fontSize: 19),
                  ),
                ),
                if (_isEditing)
                  IconButton(
                    onPressed: _saving ? null : _delete,
                    tooltip: 'Delete entry',
                    icon: const Icon(Icons.delete_outline_rounded),
                    style: IconButton.styleFrom(
                      foregroundColor: viz.critical,
                      backgroundColor: viz.critical.withValues(alpha: 0.10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            // --------------------------------------------------------- mode ---
            _ModeToggle(
              mode: _mode,
              onChanged: (mode) {
                HapticFeedback.selectionClick();
                setState(() {
                  _mode = mode;
                  _error = null;
                });
              },
            ),

            // -------------------------------------------------------- stage ---
            const SizedBox(height: 22),
            _FieldLabel('What is it for?'),
            const SizedBox(height: 10),
            TextField(
              controller: _stage,
              focusNode: _stageFocus,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onChanged: _onStageTyped,
              decoration: InputDecoration(
                hintText: 'e.g. Bricks',
                prefixIcon: Icon(
                  Icons.category_outlined,
                  size: 19,
                  color: viz.inkMuted,
                ),
                suffixIcon: _stage.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(_stage.clear),
                      ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: suggestions.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final stage in suggestions)
                            _SmallChip(
                              label: stage,
                              highlight: used.contains(stage),
                              onTap: () => _applyStage(stage),
                            ),
                        ],
                      ),
                    ),
            ),

            // ------------------------------------------------------- amount ---
            const SizedBox(height: 22),
            if (_mode == EntryMode.total) ...[
              _FieldLabel('Amount paid'),
              const SizedBox(height: 10),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() => _error = null),
                style: context.text.titleMedium?.copyWith(fontSize: 20),
                decoration: InputDecoration(
                  hintText: '0',
                  prefixText: '${Money.symbol}  ',
                ),
              ),
            ] else ...[
              _FieldLabel('How many, and at what rate'),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _quantity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (_) => setState(() => _error = null),
                      decoration: const InputDecoration(
                        hintText: '0',
                        labelText: 'Quantity',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _unit,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'pieces',
                        labelText: 'Unit',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final unit in ProjectCatalog.units) ...[
                      _SmallChip(
                        label: unit,
                        highlight: _unit.text.trim() == unit,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _unit.text = unit);
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  hintText: '0',
                  labelText: _unit.text.trim().isEmpty
                      ? 'Rate per unit'
                      : 'Rate per ${_singular(_unit.text.trim())}',
                  prefixText: '${Money.symbol}  ',
                ),
              ),
              const SizedBox(height: 14),
              _ComputedTotal(
                quantity: _parse(_quantity),
                unit: _unit.text.trim(),
                rate: _parse(_rate),
                total: _resolvedAmount,
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 10),
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

            // --------------------------------------------------------- date ---
            const SizedBox(height: 22),
            _FieldLabel('Date'),
            const SizedBox(height: 12),
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

            // --------------------------------------------------------- note ---
            const SizedBox(height: 22),
            _FieldLabel('Note (optional)'),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. Awan bhatta, delivered to site',
              ),
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
                  disabledForegroundColor: Colors.white70,
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
                        _isEditing ? 'Save changes' : 'Add entry',
                        style: context.text.titleSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            if (!_isEditing) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _save(keepOpen: true),
                  icon: const Icon(Icons.playlist_add_rounded, size: 19),
                  label: const Text('Save & add another'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: viz.series,
                    side: BorderSide(color: viz.hairline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: context.text.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Rate per bag" reads better than "Rate per bags". Crude, but it only ever
  /// sees the short unit names in the catalogue — and anything it does not
  /// recognise is left exactly as typed.
  static String _singular(String unit) {
    final u = unit.trim();
    if (u.length < 3 || !u.endsWith('s') || u.endsWith('ss')) return u;
    if (u.endsWith('ies')) return '${u.substring(0, u.length - 3)}y';
    final stem = u.substring(0, u.length - 1);
    // "pieces" keeps its e and becomes "piece"; "bags" simply loses the s.
    return stem;
  }
}

/// Picks how the amount is arrived at. Both options stay visible, so the
/// quantity-and-rate form is discoverable without being forced on a lump sum.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final EntryMode mode;
  final ValueChanged<EntryMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: viz.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final option in EntryMode.values)
            Expanded(
              child: Pressable(
                onTap: () => onChanged(option),
                scale: 0.98,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: option == mode ? viz.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: option == mode ? viz.series : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        option.icon,
                        size: 16,
                        color: option == mode ? viz.series : viz.inkMuted,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelLarge?.copyWith(
                            color: option == mode
                                ? viz.series
                                : viz.inkSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The arithmetic, shown as it is typed. Seeing `5,000 × Rs 18.50 = Rs 92,500`
/// before saving is what catches a rate typed into the quantity box.
class _ComputedTotal extends StatelessWidget {
  const _ComputedTotal({
    required this.quantity,
    required this.unit,
    required this.rate,
    required this.total,
  });

  final double? quantity;
  final String unit;
  final double? rate;
  final double? total;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final ready = total != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: ready
            ? viz.series.withValues(alpha: context.isDarkMode ? 0.18 : 0.09)
            : viz.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ready ? viz.series : viz.hairline),
      ),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.calculate_outlined,
            size: 18,
            color: ready ? viz.series : viz.inkMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready
                      ? '${Quantities.format(quantity!)}'
                            '${unit.isEmpty ? '' : ' $unit'} × '
                            '${Money.rate(rate!)}'
                      : 'Total appears here',
                  maxLines: 2,
                  style: context.text.labelSmall?.copyWith(
                    color: viz.inkSecondary,
                  ),
                ),
                if (ready) ...[
                  const SizedBox(height: 3),
                  Text(
                    Money.format(total!),
                    style: context.text.titleMedium?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: viz.inkPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final String label;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: highlight
              ? viz.series.withValues(alpha: context.isDarkMode ? 0.22 : 0.11)
              : viz.surfaceAlt,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: highlight ? viz.series : viz.hairline),
        ),
        child: Text(
          label,
          style: context.text.labelLarge?.copyWith(
            color: highlight ? viz.series : viz.inkSecondary,
            fontWeight: FontWeight.w600,
          ),
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
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? viz.series.withValues(alpha: context.isDarkMode ? 0.24 : 0.12)
              : viz.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? viz.series : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
