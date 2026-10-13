import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/error_messages.dart';
import '../models/vehicle.dart';
import '../state/expense_store.dart';
import '../widgets/form_bits.dart';

/// Icon for a vehicle kind, used wherever a vehicle is named.
IconData vehicleIcon(VehicleKind kind) => switch (kind) {
  VehicleKind.car => Icons.directions_car_rounded,
  VehicleKind.bike => Icons.two_wheeler_rounded,
};

/// Add or edit a car or bike.
///
/// Only the name is required. The odometer reading is asked for up front
/// because "due in 3,000 km" means nothing until the app knows where the
/// vehicle is now — but it can be left at zero and corrected by the first
/// service record.
class VehicleEditorSheet extends StatefulWidget {
  const VehicleEditorSheet({super.key, this.existing});

  final Vehicle? existing;

  /// Returns the new vehicle's id when one was created.
  static Future<String?> show(BuildContext context, {Vehicle? existing}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VehicleEditorSheet(existing: existing),
    );
  }

  @override
  State<VehicleEditorSheet> createState() => _VehicleEditorSheetState();
}

class _VehicleEditorSheetState extends State<VehicleEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _plate;
  late final TextEditingController _odometer;
  late final TextEditingController _note;
  late VehicleKind _kind;
  String? _error;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _plate = TextEditingController(text: existing?.plate ?? '');
    _odometer = TextEditingController(
      text: existing == null || existing.odometer == 0
          ? ''
          : '${existing.odometer}',
    );
    _note = TextEditingController(text: existing?.note ?? '');
    _kind = existing?.kind ?? VehicleKind.car;
  }

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    _odometer.dispose();
    _note.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the vehicle a name');
      return;
    }
    final rawKm = _odometer.text.trim();
    final km = rawKm.isEmpty ? 0 : int.tryParse(rawKm);
    if (km == null || km < 0) {
      setState(() => _error = 'Enter the odometer reading in whole km');
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
        final created = await store.createVehicle(
          name: name,
          kind: _kind,
          plate: _plate.text,
          odometer: km,
          note: _note.text,
        );
        navigator.pop(created.id);
        messenger.showSnackBar(SnackBar(content: Text('Added $name')));
      } else {
        await store.saveVehicle(
          existing.copyWith(
            name: name,
            kind: _kind,
            plate: _plate.text.trim(),
            odometer: km,
            note: _note.text.trim(),
          ),
        );
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Vehicle saved')));
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

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'Edit vehicle' : 'New vehicle',
              style: context.text.titleMedium?.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 4),
            Text(
              'A logbook for tuning and services. Costs stay out of the '
              'monthly figures.',
              style: context.text.bodySmall?.copyWith(color: viz.inkMuted),
            ),
            const SizedBox(height: 20),
            const FieldLabel('Type'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in VehicleKind.values)
                  PickChip(
                    label: kind.label,
                    icon: vehicleIcon(kind),
                    selected: _kind == kind,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _kind = kind);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 22),
            const FieldLabel('Name'),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearError(),
              decoration: InputDecoration(
                hintText: _kind == VehicleKind.car
                    ? 'e.g. Honda City'
                    : 'e.g. Honda CD 70',
                prefixIcon: Icon(
                  vehicleIcon(_kind),
                  size: 19,
                  color: viz.inkMuted,
                ),
              ),
            ),
            const SizedBox(height: 22),
            const FieldLabel('Odometer now (km)'),
            const SizedBox(height: 10),
            TextField(
              controller: _odometer,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _clearError(),
              decoration: InputDecoration(
                hintText: 'e.g. 42150',
                suffixText: 'km',
                helperText: 'Used to work out when the next service is due',
                helperStyle: context.text.labelSmall?.copyWith(
                  color: viz.inkMuted,
                ),
              ),
            ),
            const SizedBox(height: 22),
            const FieldLabel('Registration (optional)'),
            const SizedBox(height: 10),
            TextField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'e.g. LEB-1234'),
            ),
            const SizedBox(height: 22),
            const FieldLabel('Note (optional)'),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. 2019 model, petrol',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              FormError(_error!),
            ],
            const SizedBox(height: 26),
            SheetSaveButton(
              label: _isEditing ? 'Save changes' : 'Add vehicle',
              saving: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
