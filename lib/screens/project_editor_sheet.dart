import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../models/project.dart';
import '../state/expense_store.dart';
import '../widgets/pressable.dart';

/// Create or rename a project, and set what the whole job is expected to cost.
///
/// The estimate is optional on purpose: nobody knows the cost of a house on day
/// one, and a made-up target would make the progress meter lie. Without it the
/// project simply reports what it has cost so far.
class ProjectEditorSheet extends StatefulWidget {
  const ProjectEditorSheet({super.key, this.existing});

  final Project? existing;

  /// Returns the project's id when one was created, so the caller can open it.
  static Future<String?> show(BuildContext context, {Project? existing}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProjectEditorSheet(existing: existing),
    );
  }

  @override
  State<ProjectEditorSheet> createState() => _ProjectEditorSheetState();
}

class _ProjectEditorSheetState extends State<ProjectEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _estimate;
  late final TextEditingController _note;

  late DateTime _startedOn;
  String? _error;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  /// Names people actually use, so a first project is one tap away.
  static const _examples = [
    'Building a house',
    'Wedding',
    'Car',
    'Home repairs',
    'Shop setup',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _estimate = TextEditingController(
      text: existing?.estimate == null ? '' : _trim(existing!.estimate!),
    );
    _note = TextEditingController(text: existing?.note ?? '');
    _startedOn = existing?.startedOn ?? dayOnly(DateTime.now());
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  @override
  void dispose() {
    _name.dispose();
    _estimate.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startedOn,
      firstDate: DateTime(now.year - 10),
      lastDate: dayOnly(now),
      helpText: 'Date the work started',
    );
    if (picked != null) setState(() => _startedOn = dayOnly(picked));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the project a name');
      return;
    }
    final rawEstimate = _estimate.text.replaceAll(',', '').trim();
    final estimate = rawEstimate.isEmpty ? null : double.tryParse(rawEstimate);
    if (rawEstimate.isNotEmpty && (estimate == null || estimate <= 0)) {
      setState(() => _error = 'Enter an estimate greater than 0, or leave it '
          'empty');
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final existing = widget.existing;

    try {
      if (existing == null) {
        final created = await store.createProject(
          name: name,
          estimate: estimate,
          note: _note.text,
          startedOn: _startedOn,
        );
        navigator.pop(created.id);
        messenger.showSnackBar(
          SnackBar(content: Text('Started $name')),
        );
      } else {
        await store.saveProject(
          existing.copyWith(
            name: name,
            estimate: estimate,
            note: _note.text.trim(),
            startedOn: _startedOn,
          ),
        );
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Project saved')));
      }
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
    final today = dayOnly(DateTime.now());

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'Edit project' : 'New project',
              style: context.text.titleMedium?.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 4),
            Text(
              'Big spending from savings, kept apart from the monthly figures.',
              style: context.text.bodySmall?.copyWith(color: viz.inkMuted),
            ),
            const SizedBox(height: 20),

            _FieldLabel('Name'),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                hintText: 'e.g. Building a house',
                prefixIcon: Icon(
                  Icons.foundation_rounded,
                  size: 19,
                  color: viz.inkMuted,
                ),
              ),
            ),
            if (!_isEditing) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final example in _examples)
                    _ExampleChip(
                      label: example,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _name.text = example;
                          _error = null;
                        });
                      },
                    ),
                ],
              ),
            ],

            const SizedBox(height: 22),
            _FieldLabel('Estimated total cost (optional)'),
            const SizedBox(height: 10),
            TextField(
              controller: _estimate,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                hintText: 'e.g. 2500000',
                prefixText: '${Money.symbol}  ',
                helperText: 'Leave empty to just track what it costs',
                helperStyle: context.text.labelSmall?.copyWith(
                  color: viz.inkMuted,
                ),
              ),
            ),

            const SizedBox(height: 22),
            _FieldLabel('Started'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DateChip(
                  label: 'Today',
                  selected: _startedOn == today,
                  onTap: () => setState(() => _startedOn = today),
                ),
                _DateChip(
                  label: _startedOn == today
                      ? 'Pick a date'
                      : Dates.dayMonthYear(_startedOn),
                  icon: Icons.calendar_month_rounded,
                  selected: _startedOn != today,
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
                hintText: 'e.g. 5 marla plot, Bahria Phase 8',
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
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
                        _isEditing ? 'Save changes' : 'Create project',
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

class _ExampleChip extends StatelessWidget {
  const _ExampleChip({required this.label, required this.onTap});

  final String label;
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
          color: viz.surfaceAlt,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: viz.hairline),
        ),
        child: Text(
          label,
          style: context.text.labelLarge?.copyWith(
            color: viz.inkSecondary,
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
