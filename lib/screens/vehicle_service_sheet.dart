import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../core/formatters.dart';
import '../models/service_catalog.dart';
import '../models/vehicle.dart';
import '../state/expense_store.dart';
import '../widgets/form_bits.dart';

/// Log a tuning or service: what was done, when, at what reading, for how much,
/// and when it is due again.
///
/// Picking a job fills in its usual interval — from this vehicle's own last
/// record of it when there is one, else from the preset for a car or a bike.
/// The fields stay editable, because what the mechanic said beats any default.
class VehicleServiceSheet extends StatefulWidget {
  const VehicleServiceSheet({
    super.key,
    required this.vehicleId,
    this.existing,
  });

  final String vehicleId;
  final VehicleService? existing;

  static Future<void> show(
    BuildContext context, {
    required String vehicleId,
    VehicleService? existing,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          VehicleServiceSheet(vehicleId: vehicleId, existing: existing),
    );
  }

  @override
  State<VehicleServiceSheet> createState() => _VehicleServiceSheetState();
}

class _VehicleServiceSheetState extends State<VehicleServiceSheet> {
  late final TextEditingController _service;
  late final TextEditingController _odometer;
  late final TextEditingController _cost;
  late final TextEditingController _intervalKm;
  late final TextEditingController _intervalMonths;
  late final TextEditingController _workshop;
  late final TextEditingController _note;
  late DateTime _date;
  String? _error;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final vehicle = context.read<ExpenseStore>().vehicleById(widget.vehicleId);
    _service = TextEditingController(text: existing?.service ?? '');
    _odometer = TextEditingController(
      text: existing != null
          ? '${existing.odometer}'
          : (vehicle == null || vehicle.currentKm == 0
                ? ''
                : '${vehicle.currentKm}'),
    );
    _cost = TextEditingController(
      text: existing == null || existing.cost == 0
          ? ''
          : existing.cost == existing.cost.roundToDouble()
          ? '${existing.cost.round()}'
          : '${existing.cost}',
    );
    _intervalKm = TextEditingController(text: _num(existing?.intervalKm));
    _intervalMonths = TextEditingController(
      text: _num(existing?.intervalMonths),
    );
    _workshop = TextEditingController(text: existing?.workshop ?? '');
    _note = TextEditingController(text: existing?.note ?? '');
    _date = existing?.date ?? dayOnly(DateTime.now());
  }

  static String _num(int? value) => value == null ? '' : '$value';

  @override
  void dispose() {
    for (final c in [
      _service,
      _odometer,
      _cost,
      _intervalKm,
      _intervalMonths,
      _workshop,
      _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  /// Fills the job name and its interval. The vehicle's own last record of the
  /// job wins over the preset: if the mechanic said 4,000 km last time, that is
  /// what this household goes by.
  void _pick(String name, VehicleSummary vehicle) {
    HapticFeedback.selectionClick();
    final key = name.trim().toLowerCase();
    final previous = vehicle.services
        .where((s) => s.serviceKey == key && s.id != widget.existing?.id)
        .firstOrNull;
    final preset = ServiceCatalog.find(vehicle.vehicle.kind, name);
    setState(() {
      _service.text = name;
      _intervalKm.text = _num(previous?.intervalKm ?? preset?.intervalKm);
      _intervalMonths.text = _num(
        previous?.intervalMonths ?? preset?.intervalMonths,
      );
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 15),
      lastDate: dayOnly(now),
      helpText: 'Date of the service',
    );
    if (picked != null) setState(() => _date = dayOnly(picked));
  }

  /// Empty is null; anything else must be a whole number above zero.
  static ({bool ok, int? value}) _optionalPositive(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return (ok: true, value: null);
    final value = int.tryParse(text);
    return (ok: value != null && value > 0, value: value);
  }

  Future<void> _save() async {
    final service = _service.text.trim();
    if (service.isEmpty) {
      setState(() => _error = 'Say what was done — e.g. Tuning');
      return;
    }
    final km = int.tryParse(_odometer.text.trim());
    if (km == null || km < 0) {
      setState(() => _error = 'Enter the odometer reading in whole km');
      return;
    }
    final rawCost = _cost.text.replaceAll(',', '').trim();
    final cost = rawCost.isEmpty ? 0.0 : double.tryParse(rawCost);
    if (cost == null || cost < 0) {
      setState(() => _error = 'Enter the cost, or leave it empty');
      return;
    }
    final everyKm = _optionalPositive(_intervalKm.text);
    final everyMonths = _optionalPositive(_intervalMonths.text);
    if (!everyKm.ok || !everyMonths.ok) {
      setState(
        () => _error = 'Intervals must be whole numbers above 0, or empty',
      );
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
        await store.addVehicleService(
          vehicleId: widget.vehicleId,
          service: service,
          date: _date,
          odometer: km,
          cost: cost,
          intervalKm: everyKm.value,
          intervalMonths: everyMonths.value,
          workshop: _workshop.text,
          note: _note.text,
        );
      } else {
        await store.saveVehicleService(
          existing.copyWith(
            service: service,
            date: _date,
            odometer: km,
            cost: cost,
            intervalKm: everyKm.value,
            intervalMonths: everyMonths.value,
            workshop: _workshop.text.trim(),
            note: _note.text.trim(),
          ),
        );
      }
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Service saved' : 'Logged $service at $km km',
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
    if (existing == null) return;
    final store = context.read<ExpenseStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await store.deleteVehicleService(existing.id);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted ${existing.title}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restoreVehicleService(existing),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final store = context.watch<ExpenseStore>();
    final vehicle = store.vehicleById(widget.vehicleId);
    final today = dayOnly(DateTime.now());
    final suggestions = vehicle == null
        ? const <String>[]
        : ServiceCatalog.suggestions(
            vehicle.vehicle.kind,
            vehicle.services,
          ).take(8).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'Edit service' : 'Log a service',
              style: context.text.titleMedium?.copyWith(fontSize: 19),
            ),
            if (vehicle != null) ...[
              const SizedBox(height: 4),
              Text(
                '${vehicle.name} · now at '
                '${Quantities.format(vehicle.currentKm)} km',
                style: context.text.bodySmall?.copyWith(color: viz.inkMuted),
              ),
            ],
            const SizedBox(height: 20),
            const FieldLabel('What was done'),
            const SizedBox(height: 10),
            TextField(
              controller: _service,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearError(),
              decoration: InputDecoration(
                hintText: 'e.g. Tuning',
                prefixIcon: Icon(
                  Icons.build_rounded,
                  size: 19,
                  color: viz.inkMuted,
                ),
              ),
            ),
            if (vehicle != null && suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in suggestions)
                    PickChip(
                      label: name,
                      selected:
                          _service.text.trim().toLowerCase() ==
                          name.toLowerCase(),
                      onTap: () => _pick(name, vehicle),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            const FieldLabel('Date'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PickChip(
                  label: 'Today',
                  selected: _date == today,
                  onTap: () => setState(() => _date = today),
                ),
                PickChip(
                  label: _date == today
                      ? 'Pick a date'
                      : Dates.dayMonthYear(_date),
                  icon: Icons.calendar_month_rounded,
                  selected: _date != today,
                  onTap: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FieldLabel('Odometer'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _odometer,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => _clearError(),
                        decoration: const InputDecoration(
                          hintText: '42150',
                          suffixText: 'km',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FieldLabel('Cost'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _cost,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        onChanged: (_) => _clearError(),
                        decoration: InputDecoration(
                          hintText: '2500',
                          prefixText: '${Money.symbol} ',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const FieldLabel('Next due after'),
            const SizedBox(height: 4),
            Text(
              'Whichever comes first. Leave both empty for a one-off job.',
              style: context.text.labelSmall?.copyWith(color: viz.inkMuted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _intervalKm,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => _clearError(),
                    decoration: const InputDecoration(
                      hintText: '5000',
                      suffixText: 'km',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _intervalMonths,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => _clearError(),
                    decoration: const InputDecoration(
                      hintText: '6',
                      suffixText: 'months',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const FieldLabel('Workshop (optional)'),
            const SizedBox(height: 10),
            TextField(
              controller: _workshop,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. Al-Madina Autos',
              ),
            ),
            const SizedBox(height: 22),
            const FieldLabel('Note (optional)'),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. Shell Helix 10W-40, new plugs',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              FormError(_error!),
            ],
            const SizedBox(height: 26),
            SheetSaveButton(
              label: _isEditing ? 'Save changes' : 'Save service',
              saving: _saving,
              onPressed: _save,
            ),
            if (_isEditing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: viz.critical),
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                label: const Text('Delete this service'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
