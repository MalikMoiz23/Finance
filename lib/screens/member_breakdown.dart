import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/family_member.dart';
import '../state/expense_store.dart';
import '../widgets/pressable.dart';
import '../widgets/share_meter.dart';
import 'family_members_sheet.dart';

/// Who spent what, ranked.
///
/// Same form as the category breakdown above it: bars in a single hue with the
/// amount labelled on every row. People get no colour of their own — the eight
/// categorical slots already mean *category*, and a second scale sharing those
/// hues would have one green mean both Abba and groceries.
class MemberBreakdown extends StatelessWidget {
  const MemberBreakdown({super.key, required this.rows, this.onSelect});

  final List<MemberSpend> rows;

  /// Called with the tapped row's member id — [ExpenseStore.unassignedMember]
  /// for the "Not set" row — so a row can narrow the screens to that person.
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    if (rows.isEmpty) {
      return Text(
        'Nothing logged in this period.',
        style: context.text.bodySmall?.copyWith(color: viz.inkMuted),
      );
    }
    final total = rows.fold<double>(0, (sum, r) => sum + r.total);

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _MemberRow(
            row: rows[i],
            share: rows[i].shareOf(total),
            onTap: onSelect == null
                ? null
                : () => onSelect!(
                    rows[i].member?.id ?? ExpenseStore.unassignedMember,
                  ),
          ),
        ],
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.row, required this.share, this.onTap});

  final MemberSpend row;
  final double share;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final percent = share * 100;
    final percentLabel = percent > 0 && percent < 1
        ? '<1%'
        : '${percent.round()}%';

    final content = Row(
      children: [
        MemberAvatar(name: row.name, initials: row.initials, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        // The unattributed row is real money, so it is listed —
                        // but muted, because it is a gap rather than a person.
                        color: row.unassigned ? viz.inkMuted : viz.inkPrimary,
                        fontStyle: row.unassigned
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Money.format(row.total),
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: viz.inkPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(child: ShareMeter(share: share)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 34,
                    child: Text(
                      percentLabel,
                      textAlign: TextAlign.right,
                      style: context.text.labelSmall?.copyWith(
                        color: viz.inkSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${row.count} ${row.count == 1 ? 'entry' : 'entries'}',
                style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
              ),
            ],
          ),
        ),
      ],
    );
    return onTap == null
        ? content
        : Pressable(onTap: onTap!, scale: 0.99, child: content);
  }
}
