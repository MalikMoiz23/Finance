import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/item_catalog.dart';
import '../state/expense_store.dart';
import '../widgets/category_icon.dart';
import '../widgets/pressable.dart';
import 'family_members_sheet.dart';

/// Add or edit one expense: amount, what it was, category, date, note.
///
/// The item field learns. Typing "chick" offers "Chicken" from what this account
/// has bought before — with its category and last price — so a daily entry is
/// two taps. New accounts get the same completions from a built-in catalogue.
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
  late final TextEditingController _item;
  late final TextEditingController _note;
  final FocusNode _itemFocus = FocusNode();

  late ExpenseCategory _category;
  late DateTime _date;
  String? _memberId;
  String? _error;
  bool _saving = false;
  bool _suggestionsOpen = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _memberId = existing?.memberId;
    _amount = TextEditingController(
      text: existing == null ? '' : _trimAmount(existing.amount),
    );
    _item = TextEditingController(text: existing?.item ?? '');
    _note = TextEditingController(text: existing?.note ?? '');
    _category = existing?.category ?? ExpenseCategory.groceries;
    _date = existing?.date ?? dayOnly(DateTime.now());

    _itemFocus.addListener(() {
      setState(() => _suggestionsOpen = _itemFocus.hasFocus);
    });
  }

  static String _trimAmount(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  /// The person this will be saved against.
  ///
  /// With exactly one person in the house there is only one possible answer, so
  /// it is filled in rather than demanded; with more than one, nothing is
  /// assumed and the form insists. An id whose person has since been removed
  /// counts as unset, so the form asks again instead of saving a name that no
  /// longer exists.
  String? _selectedMember(ExpenseStore store) {
    final chosen = _memberId;
    if (chosen != null && store.memberById(chosen) != null) return chosen;
    return store.members.length == 1 ? store.members.single.id : null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _item.dispose();
    _note.dispose();
    _itemFocus.dispose();
    super.dispose();
  }

  /// Filling in one tap: name, category, and the last price paid.
  void _apply(ItemSuggestion suggestion, {bool closeList = true}) {
    HapticFeedback.selectionClick();
    setState(() {
      _item.text = suggestion.name;
      _category = suggestion.category;
      if (_amount.text.trim().isEmpty && suggestion.typicalAmount != null) {
        _amount.text = _trimAmount(suggestion.typicalAmount!);
      }
      _error = null;
      if (closeList) _suggestionsOpen = false;
    });
    if (closeList) _itemFocus.unfocus();
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

  /// Bumps the amount by a round number — quicker than typing when you already
  /// know roughly what it cost.
  void _bump(int by) {
    final current =
        double.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
    HapticFeedback.selectionClick();
    setState(() {
      _amount.text = _trimAmount(current + by);
      _error = null;
    });
  }

  /// Clears the amount, item and note but keeps the category and date, so a run
  /// of entries from the same shopping trip is quick.
  void _resetForNext() {
    setState(() {
      _amount.clear();
      _item.clear();
      _note.clear();
      _error = null;
      _suggestionsOpen = false;
    });
  }

  /// Writes straight to Supabase. On failure the sheet stays open with the
  /// message, so nothing the user typed is lost.
  Future<void> _save({bool keepOpen = false}) async {
    final raw = _amount.text.replaceAll(',', '').trim();
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      setState(() => _error = 'Enter an amount greater than 0');
      return;
    }
    // Required: an expense nobody owns cannot answer the question the family
    // list exists to answer.
    final store = context.read<ExpenseStore>();
    final memberId = _selectedMember(store);
    if (memberId == null) {
      setState(
        () => _error = store.members.isEmpty
            ? 'Add the people in your house first'
            : 'Pick who spent this',
      );
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final existing = widget.existing;

    try {
      if (existing == null) {
        await store.create(
          amount: parsed,
          category: _category,
          date: _date,
          item: _item.text,
          note: _note.text,
          memberId: memberId,
        );
      } else {
        await store.update(
          existing.copyWith(
            amount: parsed,
            category: _category,
            date: _date,
            item: _item.text,
            note: _note.text,
            memberId: memberId,
          ),
        );
      }
      // Never save an entry out of sight: pull the window onto its date.
      store.focusOn(_date);
      final what = _item.text.trim().isEmpty
          ? _category.label
          : _item.text.trim();
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
            '${Money.format(parsed)} · $what',
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
      await store.remove(existing.id);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted ${existing.title}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restore(existing),
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

    final query = _item.text.trim();
    final suggestions = _suggestionsOpen
        ? store.suggestItems(query)
        : const <ItemSuggestion>[];
    final quickAdd = _isEditing
        ? const <ItemSuggestion>[]
        : store.recentItems(limit: 5);

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
                    onPressed: _saving ? null : _delete,
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

            // ------------------------------------------------------- amount ---
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
                      autofocus: !_isEditing,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      textInputAction: TextInputAction.next,
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

            // ------------------------------------------------ amount bumps ---
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final step in const [50, 100, 200, 500, 1000]) ...[
                    _BumpChip(step: step, onTap: () => _bump(step)),
                    const SizedBox(width: 8),
                  ],
                  if (_amount.text.isNotEmpty)
                    _BumpChip(
                      label: 'Clear',
                      onTap: () => setState(() {
                        _amount.clear();
                        _error = null;
                      }),
                    ),
                ],
              ),
            ),

            // ------------------------------------------------------- person ---
            const SizedBox(height: 20),
            _FieldLabel('Who spent this?'),
            const SizedBox(height: 10),
            if (store.members.isEmpty)
              _NoMembersYet(
                onAdd: () => FamilyMembersSheet.show(context),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final member in store.members)
                    _PersonChip(
                      name: member.name,
                      initials: member.initials,
                      selected: member.id == _selectedMember(store),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _memberId = member.id;
                          _error = null;
                        });
                      },
                    ),
                  _AddPersonChip(
                    onTap: () => FamilyMembersSheet.show(context),
                  ),
                ],
              ),

            // --------------------------------------------------- quick add ---
            if (quickAdd.isNotEmpty) ...[
              const SizedBox(height: 16),
              _FieldLabel('Buy again'),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final suggestion in quickAdd) ...[
                      _QuickChip(
                        suggestion: suggestion,
                        onTap: () => _apply(suggestion, closeList: false),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],

            // --------------------------------------------------------- item ---
            const SizedBox(height: 20),
            _FieldLabel('What did you buy?'),
            const SizedBox(height: 10),
            TextField(
              controller: _item,
              focusNode: _itemFocus,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'e.g. Chicken',
                prefixIcon: Icon(
                  Icons.shopping_basket_outlined,
                  size: 19,
                  color: viz.inkMuted,
                ),
                suffixIcon: _item.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear item',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _item.clear()),
                      ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: suggestions.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: viz.surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: viz.hairline),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < suggestions.length; i++)
                            _SuggestionRow(
                              suggestion: suggestions[i],
                              first: i == 0,
                              onTap: () => _apply(suggestions[i]),
                            ),
                        ],
                      ),
                    ),
            ),

            // ----------------------------------------------------- category ---
            const SizedBox(height: 20),
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
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _category = category);
                    },
                  ),
              ],
            ),

            // --------------------------------------------------------- date ---
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

            // --------------------------------------------------------- note ---
            const SizedBox(height: 22),
            _FieldLabel('Note (optional)'),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. weekend stock, Al-Fatah',
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
                        _isEditing ? 'Save changes' : 'Add expense',
                        style: context.text.titleSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            // Entering a whole shopping trip: save and stay, keeping the
            // category and date for the next line.
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
}

/// One person to attribute the expense to. Required, so the unselected state
/// has to look unfinished rather than merely optional.
class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.name,
    required this.initials,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String initials;
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
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          color: selected
              ? viz.series.withValues(alpha: context.isDarkMode ? 0.24 : 0.12)
              : viz.surfaceAlt,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? viz.series : viz.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MemberAvatar(
              name: name,
              initials: initials,
              size: 30,
              selected: selected,
            ),
            const SizedBox(width: 9),
            Text(
              name,
              style: context.text.labelLarge?.copyWith(
                color: selected ? viz.series : viz.inkSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            // The tick is what carries "chosen" for anyone who cannot separate
            // the two fills by colour.
            if (selected) ...[
              const SizedBox(width: 7),
              Icon(Icons.check_circle_rounded, size: 16, color: viz.series),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddPersonChip extends StatelessWidget {
  const _AddPersonChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: viz.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_alt_rounded, size: 16, color: viz.inkMuted),
            const SizedBox(width: 7),
            Text(
              'Add person',
              style: context.text.labelLarge?.copyWith(
                color: viz.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the household has nobody in it yet. With the person required,
/// this is a dead end unless it offers the way out, so it does.
class _NoMembersYet extends StatelessWidget {
  const _NoMembersYet({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: viz.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: viz.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Nobody added yet. Add the people in your house and every expense '
            'will record who spent it.',
            style: context.text.bodySmall?.copyWith(
              color: viz.inkSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_rounded, size: 18),
              label: const Text('Add family members'),
              style: FilledButton.styleFrom(
                backgroundColor: viz.series,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Adds a round number to the amount — faster than the keyboard for the common
/// "it was about five hundred" case.
class _BumpChip extends StatelessWidget {
  const _BumpChip({this.step, this.label, required this.onTap});

  final int? step;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final isClear = step == null;
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: viz.surfaceAlt,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: viz.hairline),
        ),
        child: Text(
          label ?? '+$step',
          style: context.text.labelLarge?.copyWith(
            color: isClear ? viz.inkMuted : viz.inkSecondary,
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

/// One autocomplete row: what it is, which category it will file under, and the
/// price last paid for it.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.first,
    required this.onTap,
  });

  final ItemSuggestion suggestion;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: viz.hairline)),
        ),
        child: Row(
          children: [
            CategoryIcon(category: suggestion.category, size: 30, iconSize: 15),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: viz.inkPrimary,
                    ),
                  ),
                  Text(
                    suggestion.fromHistory
                        ? '${suggestion.category.label} · bought ${suggestion.uses}×'
                        : suggestion.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: viz.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (suggestion.typicalAmount != null) ...[
              const SizedBox(width: 8),
              Text(
                Money.format(suggestion.typicalAmount!),
                style: context.text.labelLarge?.copyWith(
                  color: viz.series,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Buy again" chip: one tap fills item, category and last price.
class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.suggestion, required this.onTap});

  final ItemSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final color = suggestion.category.colorOf(context);
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: viz.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: viz.hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              suggestion.name,
              style: context.text.labelLarge?.copyWith(
                color: viz.inkPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (suggestion.typicalAmount != null) ...[
              const SizedBox(width: 7),
              Text(
                Money.compact(suggestion.typicalAmount!),
                style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
              ),
            ],
          ],
        ),
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
      child: Pressable(
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
