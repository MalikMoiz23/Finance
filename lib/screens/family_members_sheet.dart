import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../models/family_member.dart';
import '../state/expense_store.dart';
import '../widgets/pressable.dart';

/// Add, rename and remove the people in the house.
///
/// Opens by itself right after the first login — with the person required on
/// every expense, nothing can be logged until there is at least one name — and
/// is available afterwards from the account menu.
class FamilyMembersSheet extends StatefulWidget {
  const FamilyMembersSheet({super.key, this.firstRun = false});

  /// Shown automatically because the household has no people yet. Changes the
  /// wording from managing a list to setting one up.
  final bool firstRun;

  static Future<void> show(BuildContext context, {bool firstRun = false}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // On the first run there is nowhere else to go, so it does not close by
      // tapping outside — that would leave an app you cannot add anything to.
      isDismissible: !firstRun,
      enableDrag: !firstRun,
      builder: (_) => FamilyMembersSheet(firstRun: firstRun),
    );
  }

  @override
  State<FamilyMembersSheet> createState() => _FamilyMembersSheetState();
}

class _FamilyMembersSheetState extends State<FamilyMembersSheet> {
  final TextEditingController _name = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  String? _error;
  bool _busy = false;

  /// Who is usually in the house. One tap each beats typing.
  static const _suggestions = ['Abba', 'Ammi', 'Bhai', 'Baji', 'Me'];

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _add([String? preset]) async {
    final store = context.read<ExpenseStore>();
    final name = (preset ?? _name.text).trim();
    if (name.isEmpty) {
      setState(() => _error = 'Type a name first');
      return;
    }
    if (store.memberNameTaken(name)) {
      setState(() => _error = '$name is already on the list');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.addMember(name);
      if (!mounted) return;
      setState(() {
        _name.clear();
        _busy = false;
      });
      // Straight on to the next person: a family is rarely just one.
      _nameFocus.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _rename(FamilyMember member) async {
    final store = context.read<ExpenseStore>();
    final controller = TextEditingController(text: member.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    final trimmed = newName?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == member.name) return;
    if (store.memberNameTaken(trimmed, exceptId: member.id)) {
      if (mounted) setState(() => _error = '$trimmed is already on the list');
      return;
    }
    try {
      await store.saveMember(member.copyWith(name: trimmed));
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    }
  }

  Future<void> _remove(FamilyMember member) async {
    final store = context.read<ExpenseStore>();
    final count = store.expenseCountFor(member.id);
    final spent = store.spentBy(member.id);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${member.name}?'),
        content: Text(
          count == 0
              ? '${member.name} will be taken off the list.'
              : 'The ${Money.format(spent)} across $count '
                    '${count == 1 ? 'expense' : 'expenses'} stays in your '
                    'totals — those entries will just read "Not set" instead '
                    'of ${member.name}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await store.deleteMember(member.id);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final store = context.watch<ExpenseStore>();
    final members = store.members;
    final taken = members.map((m) => m.name.toLowerCase()).toSet();
    final unused = _suggestions
        .where((s) => !taken.contains(s.toLowerCase()))
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.firstRun ? 'Who is in the house?' : 'Family members',
              style: context.text.titleMedium?.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 4),
            Text(
              widget.firstRun
                  ? 'Everyone uses this same login. Add a name for each person '
                        'so every expense records who spent it.'
                  : 'Everyone shares this login. Each expense records which of '
                        'these people spent it.',
              style: context.text.bodySmall?.copyWith(
                color: viz.inkMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),

            if (members.isNotEmpty) ...[
              for (final member in members) ...[
                _MemberRow(
                  member: member,
                  count: store.expenseCountFor(member.id),
                  spent: store.spentBy(member.id),
                  onRename: () => _rename(member),
                  onRemove: () => _remove(member),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 10),
            ],

            _FieldLabel(members.isEmpty ? 'First person' : 'Add another'),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              focusNode: _nameFocus,
              autofocus: members.isEmpty,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _add(),
              decoration: InputDecoration(
                hintText: 'e.g. Abba',
                prefixIcon: Icon(
                  Icons.person_outline_rounded,
                  size: 19,
                  color: viz.inkMuted,
                ),
                suffixIcon: IconButton(
                  tooltip: 'Add this person',
                  onPressed: _busy ? null : () => _add(),
                  icon: Icon(Icons.add_circle_rounded, color: viz.series),
                ),
              ),
            ),
            if (unused.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in unused)
                    _SuggestionChip(
                      label: name,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _add(name);
                      },
                    ),
                ],
              ),
            ],

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

            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: members.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: viz.series,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: viz.series.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  members.isEmpty
                      ? 'Add at least one person'
                      : widget.firstRun
                      ? 'Done, start tracking'
                      : 'Done',
                  style: context.text.titleSmall?.copyWith(
                    color: members.isEmpty ? Colors.white70 : Colors.white,
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

/// One person: what they have spent, with rename and remove spelled out rather
/// than left to a pair of bare icons.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.count,
    required this.spent,
    required this.onRename,
    required this.onRemove,
  });

  final FamilyMember member;
  final int count;
  final double spent;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: viz.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          MemberAvatar(name: member.name, initials: member.initials),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: viz.inkPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? 'Nothing logged yet'
                      : '${Money.format(spent)} · $count '
                            '${count == 1 ? 'expense' : 'expenses'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRename,
            tooltip: 'Rename ${member.name}',
            icon: const Icon(Icons.edit_outlined, size: 19),
            style: IconButton.styleFrom(foregroundColor: viz.inkSecondary),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove ${member.name}',
            icon: const Icon(Icons.person_remove_outlined, size: 19),
            style: IconButton.styleFrom(foregroundColor: viz.critical),
          ),
        ],
      ),
    );
  }
}

/// Initials in a neutral circle.
///
/// Deliberately not colour-coded per person: the eight categorical slots in the
/// palette already mean *category*, and a second scale sharing those hues would
/// have one green mean both Abba and groceries.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    required this.initials,
    this.size = 36,
    this.selected = false,
  });

  final String name;
  final String initials;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Semantics(
      label: name,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? viz.series.withValues(alpha: context.isDarkMode ? 0.28 : 0.14)
              : viz.surface,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? viz.series : viz.hairline),
        ),
        child: Text(
          initials,
          style: context.text.labelSmall?.copyWith(
            fontSize: size * 0.34,
            fontWeight: FontWeight.w700,
            color: selected ? viz.series : viz.inkSecondary,
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 15, color: viz.series),
            const SizedBox(width: 5),
            Text(
              label,
              style: context.text.labelLarge?.copyWith(
                color: viz.inkSecondary,
                fontWeight: FontWeight.w600,
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
