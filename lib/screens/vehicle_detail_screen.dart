import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../models/vehicle.dart';
import '../state/expense_store.dart';
import '../widgets/entrance.dart';
import '../widgets/pressable.dart';
import '../widgets/section_card.dart';
import '../widgets/share_meter.dart';
import 'vehicle_editor_sheet.dart';
import 'vehicle_service_sheet.dart';
import 'vehicles_screen.dart';

/// One vehicle's logbook: where the odometer stands, what is due next, what
/// each kind of job has cost, and every service in order.
class VehicleDetailScreen extends StatelessWidget {
  const VehicleDetailScreen({super.key, required this.vehicleId});

  final String vehicleId;

  static Future<void> open(BuildContext context, String vehicleId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VehicleDetailScreen(vehicleId: vehicleId),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, VehicleSummary v) async {
    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this vehicle?'),
        content: Text(
          v.serviceCount == 0
              ? '"${v.name}" will be removed.'
              : '"${v.name}" and all ${v.serviceCount} service '
                    '${v.serviceCount == 1 ? 'record' : 'records'} '
                    '(${Money.format(v.totalCost)}) will be removed. This '
                    'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete vehicle'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await store.deleteVehicle(v.id);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Deleted ${v.name}')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  /// A new reading without a service — "the car is at 47,300 now" — so the
  /// km left on every job stays honest between visits to the workshop.
  Future<void> _updateReading(BuildContext context, VehicleSummary v) async {
    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    // An odometer never goes backwards past a reading already on a service.
    final floor = v.services.fold<int>(0, (m, s) => math.max(m, s.odometer));

    final reading = await showDialog<int>(
      context: context,
      builder: (_) => _ReadingDialog(current: v.currentKm, floor: floor),
    );
    if (reading == null) return;
    try {
      await store.saveVehicle(v.vehicle.copyWith(odometer: reading));
      messenger.showSnackBar(
        SnackBar(
          content: Text('${v.name} now at ${Quantities.format(reading)} km'),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final summary = store.vehicleById(vehicleId);
    final viz = context.viz;

    if (summary == null) {
      // Deleted on another device and removed by a pull while this page was
      // open. Say so rather than showing an empty logbook.
      return Scaffold(
        appBar: AppBar(title: const Text('Vehicle')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.no_crash_rounded, size: 34, color: viz.inkMuted),
                const SizedBox(height: 12),
                Text(
                  'This vehicle is no longer here',
                  textAlign: TextAlign.center,
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to vehicles'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final dues = summary.dues;
    final jobs = summary.byService;

    return Scaffold(
      appBar: AppBar(
        title: Text(summary.name, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) => switch (value) {
              'edit' => VehicleEditorSheet.show(
                context,
                existing: summary.vehicle,
              ),
              'delete' => _confirmDelete(context, summary),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit vehicle'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Delete vehicle'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            VehicleServiceSheet.show(context, vehicleId: summary.id),
        backgroundColor: viz.series,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.build_rounded, size: 20),
        label: const Text('Log service'),
      ),
      body: ScreenIntro(
        child: RefreshIndicator(
          onRefresh: store.refresh,
          color: viz.series,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.gutter,
              10,
              AppSizes.gutter,
              120,
            ),
            children: [
              Entrance(
                index: 0,
                child: _ReadingCard(
                  summary: summary,
                  onUpdate: () => _updateReading(context, summary),
                ),
              ),
              const SizedBox(height: AppSizes.gap),
              Entrance(
                index: 1,
                child: SectionCard(
                  title: 'Next service',
                  subtitle: dues.isEmpty
                      ? null
                      : 'By km or date, whichever comes first',
                  child: dues.isEmpty
                      ? Text(
                          summary.serviceCount == 0
                              ? 'Log the last tuning or oil change and the '
                                    'next one is worked out from it.'
                              : 'None of the services logged has an '
                                    'interval, so nothing is scheduled.',
                          style: context.text.bodySmall?.copyWith(
                            color: viz.inkSecondary,
                            height: 1.45,
                          ),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < dues.length; i++) ...[
                              if (i > 0) const SizedBox(height: 14),
                              _DueRow(due: dues[i]),
                            ],
                          ],
                        ),
                ),
              ),
              if (jobs.isNotEmpty && summary.totalCost > 0) ...[
                const SizedBox(height: AppSizes.gap),
                Entrance(
                  index: 2,
                  child: SectionCard(
                    title: 'Cost by job',
                    subtitle: 'Which work costs the most',
                    child: Column(
                      children: [
                        for (var i = 0; i < jobs.length; i++) ...[
                          if (i > 0) const SizedBox(height: 16),
                          _JobRow(
                            job: jobs[i],
                            share: jobs[i].shareOf(summary.totalCost),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              if (summary.services.isNotEmpty) ...[
                const SizedBox(height: AppSizes.gap),
                Entrance(
                  index: 3,
                  child: SectionCard(
                    title: 'Service history',
                    subtitle:
                        '${summary.serviceCount} '
                        '${summary.serviceCount == 1 ? 'record' : 'records'}'
                        ' · newest first',
                    child: Column(
                      children: [
                        for (var i = 0; i < summary.services.length; i++) ...[
                          if (i > 0) Divider(height: 22, color: viz.hairline),
                          _ServiceRow(
                            record: summary.services[i],
                            onTap: () => VehicleServiceSheet.show(
                              context,
                              vehicleId: summary.id,
                              existing: summary.services[i],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.summary, required this.onUpdate});

  final VehicleSummary summary;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final plate = summary.vehicle.plate.trim();
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                vehicleIcon(summary.vehicle.kind),
                size: 18,
                color: viz.inkMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ['ODOMETER', if (plate.isNotEmpty) plate].join(' · '),
                  style: context.text.labelSmall?.copyWith(
                    color: viz.inkMuted,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '${Quantities.format(summary.currentKm)} km',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.displaySmall?.copyWith(
                    color: viz.inkPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onUpdate,
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: const Text('Update'),
                style: TextButton.styleFrom(foregroundColor: viz.series),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Spent on servicing: ${Money.format(summary.totalCost)} · '
            '${summary.serviceCount} '
            '${summary.serviceCount == 1 ? 'service' : 'services'}',
            style: context.text.bodySmall?.copyWith(color: viz.inkSecondary),
          ),
        ],
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.due});

  final ServiceDue due;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final targets = [
      if (due.dueKm != null) '${Quantities.format(due.dueKm!)} km',
      if (due.dueDate != null) Dates.dayMonthYear(due.dueDate!),
    ].join(' or ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DueLine(due: due),
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 2),
          child: Text(
            'Due at $targets · last done '
            '${Dates.dayMonthYear(due.last.date)} at '
            '${Quantities.format(due.last.odometer)} km',
            style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
          ),
        ),
      ],
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.share});

  final ServiceTotal job;
  final double share;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                job.service,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: viz.inkPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Money.format(job.total),
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: viz.inkPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ShareMeter(share: share),
        const SizedBox(height: 4),
        Text(
          '${job.count} ${job.count == 1 ? 'time' : 'times'}',
          style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
        ),
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.record, required this.onTap});

  final VehicleService record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final details = [
      Dates.dayMonthYear(record.date),
      '${Quantities.format(record.odometer)} km',
      if (record.workshop.trim().isNotEmpty) record.workshop.trim(),
    ].join(' · ');
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: viz.inkPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  details,
                  style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
                ),
                if (record.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    record.note.trim(),
                    style: context.text.labelSmall?.copyWith(
                      color: viz.inkSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            record.cost == 0 ? 'Free' : Money.format(record.cost),
            style: context.text.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: record.cost == 0 ? viz.inkMuted : viz.inkPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingDialog extends StatefulWidget {
  const _ReadingDialog({required this.current, required this.floor});

  final int current;
  final int floor;

  @override
  State<_ReadingDialog> createState() => _ReadingDialogState();
}

class _ReadingDialogState extends State<_ReadingDialog> {
  late final TextEditingController _km = TextEditingController(
    text: '${widget.current}',
  );
  String? _error;

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_km.text.trim());
    if (value == null) {
      setState(() => _error = 'Enter the reading in whole km');
      return;
    }
    if (value < widget.floor) {
      setState(
        () => _error =
            'A service was already logged at '
            '${Quantities.format(widget.floor)} km',
      );
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Odometer reading'),
      content: TextField(
        controller: _km,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(suffixText: 'km', errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
