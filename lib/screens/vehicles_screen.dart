import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/budget.dart';
import '../models/vehicle.dart';
import '../state/expense_store.dart';
import '../widgets/budget_meter.dart';
import '../widgets/entrance.dart';
import '../widgets/pressable.dart';
import '../widgets/section_card.dart';
import '../widgets/skeleton.dart';
import 'vehicle_detail_screen.dart';
import 'vehicle_editor_sheet.dart';

/// Due status in the budget meter's colours and icons, so "overdue" reads the
/// same as "over budget" everywhere in the app.
({Color fill, Color track, IconData icon}) dueStyle(
  BuildContext context,
  DueStatus status,
) => bandStyle(context, switch (status) {
  DueStatus.overdue => BudgetBand.overBudget,
  DueStatus.dueSoon => BudgetBand.closeToLimit,
  DueStatus.ok => BudgetBand.onTrack,
});

/// One line saying what is due next and when: icon, job, status in words, and
/// the distance and time left.
class DueLine extends StatelessWidget {
  const DueLine({super.key, required this.due, this.prefix});

  final ServiceDue due;

  /// Put in front of the job name — the vehicle's name on the Overview, where
  /// several vehicles share one list.
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final style = dueStyle(context, due.status);
    final urgent = due.status != DueStatus.ok;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(style.icon, size: 16, color: style.fill),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: prefix == null
                      ? due.service
                      : '$prefix · ${due.service}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: viz.inkPrimary,
                  ),
                ),
                TextSpan(text: '  ${due.status.label} · ${due.describe}'),
              ],
            ),
            style: context.text.bodySmall?.copyWith(
              // Amber is below text contrast on the light surface, so the
              // wording stays in ink and the icon carries the colour.
              color: due.status == DueStatus.overdue
                  ? viz.critical
                  : (urgent ? viz.inkSecondary : viz.inkMuted),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// The household's cars and bikes, and what each one needs next.
///
/// A separate ledger: service costs are totalled here and nowhere else, and the
/// screen says so, so nobody wonders why the Overview total does not include
/// last week's tuning.
class VehiclesScreen extends StatelessWidget {
  const VehiclesScreen({super.key});

  /// Adds a vehicle and opens it, ready for its first service record.
  static Future<void> start(BuildContext context) async {
    final id = await VehicleEditorSheet.show(context);
    if (id == null || !context.mounted) return;
    await VehicleDetailScreen.open(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final vehicles = store.vehicles;
    final loadingEmpty = store.isLoading && vehicles.isEmpty;

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
          Text(
            'Vehicles',
            style: context.text.titleMedium?.copyWith(fontSize: 19),
          ),
          const SizedBox(height: 2),
          Text(
            'Tuning and service logbook',
            style: context.text.bodySmall?.copyWith(
              color: context.viz.inkMuted,
            ),
          ),
          const SizedBox(height: 16),
          if (loadingEmpty)
            const Entrance(index: 0, child: SectionCard(child: RowsSkeleton()))
          else if (vehicles.isEmpty)
            Entrance(
              index: 0,
              child: SectionCard(
                child: _NoVehiclesYet(onAdd: () => start(context)),
              ),
            )
          else ...[
            Entrance(index: 0, child: _AcrossVehiclesCard(store: store)),
            for (var i = 0; i < vehicles.length; i++) ...[
              const SizedBox(height: AppSizes.gap),
              Entrance(
                index: i + 1,
                child: VehicleCard(
                  summary: vehicles[i],
                  onTap: () =>
                      VehicleDetailScreen.open(context, vehicles[i].id),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AcrossVehiclesCard extends StatelessWidget {
  const _AcrossVehiclesCard({required this.store});

  final ExpenseStore store;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final count = store.vehicles.length;
    final services = store.vehicleServiceCount;
    final attention = store.vehicleAttention.length;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPENT ON SERVICING',
            style: context.text.labelSmall?.copyWith(
              color: viz.inkMuted,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedAmount(
            value: store.vehiclesTotalCost,
            formatter: Money.format,
            style: context.text.displaySmall?.copyWith(
              color: viz.inkPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count ${count == 1 ? 'vehicle' : 'vehicles'} · '
            '$services ${services == 1 ? 'service' : 'services'} logged'
            '${attention == 0 ? '' : ' · $attention need attention'}',
            style: context.text.bodySmall?.copyWith(color: viz.inkSecondary),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: viz.surfaceAlt,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: viz.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kept out of your monthly spending, budgets and savings. '
                    'Fuel stays an everyday expense.',
                    style: context.text.labelSmall?.copyWith(
                      color: viz.inkSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One vehicle in the list: current reading, what it has cost, and the next
/// job it needs.
class VehicleCard extends StatelessWidget {
  const VehicleCard({super.key, required this.summary, required this.onTap});

  final VehicleSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final next = summary.nextDue;
    final plate = summary.vehicle.plate.trim();

    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: viz.series.withValues(
                      alpha: context.isDarkMode ? 0.22 : 0.11,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    vehicleIcon(summary.vehicle.kind),
                    size: 21,
                    color: viz.series,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: viz.inkPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          summary.vehicle.kind.label,
                          if (plate.isNotEmpty) plate,
                          '${Quantities.format(summary.currentKm)} km',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: viz.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: viz.inkMuted,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              Money.format(summary.totalCost),
              style: context.text.titleMedium?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: viz.inkPrimary,
              ),
            ),
            Text(
              '${summary.serviceCount} '
              '${summary.serviceCount == 1 ? 'service' : 'services'}'
              '${summary.lastServiceDate == null ? '' : ' · last ${Dates.dayMonthYear(summary.lastServiceDate!)}'}',
              style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
            ),
            const SizedBox(height: 10),
            if (next != null)
              DueLine(due: next)
            else
              Text(
                summary.serviceCount == 0
                    ? 'No services logged yet'
                    : 'Nothing scheduled — no intervals set',
                style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoVehiclesYet extends StatelessWidget {
  const _NoVehiclesYet({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.car_repair_rounded, size: 34, color: viz.inkMuted),
        const SizedBox(height: 12),
        Text(
          'No vehicles yet',
          textAlign: TextAlign.center,
          style: context.text.titleSmall?.copyWith(color: viz.inkPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Add your car or bike, then log every tuning, oil change and repair '
          'with its date, odometer reading and cost. The app tells you when '
          'the next one is due — by km or by date, whichever comes first.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(
            color: viz.inkSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add a vehicle'),
            style: FilledButton.styleFrom(
              backgroundColor: viz.series,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: context.text.titleSmall?.copyWith(fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}
