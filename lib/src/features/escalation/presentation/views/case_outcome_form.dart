import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../auth/presentation/viewmodels/auth_viewmodel.dart';
import '../../data/models/escalation_model.dart';
import '../viewmodels/escalation_viewmodel.dart';

/// What the clinician decides after speaking to the patient: resolve the
/// case, refer it to a doctor (or a doctor to a specialist), or dispatch an
/// ambulance. The ambulance is simulated: it's recorded and the patient and
/// doctors are told, but nothing real is dispatched.
class CaseOutcomeForm extends ConsumerStatefulWidget {
  const CaseOutcomeForm({
    super.key,
    required this.escalationId,
    required this.onDone,
    this.onLater,
    this.foreground,
  });

  final String escalationId;

  /// Called after the outcome is saved.
  final VoidCallback onDone;

  /// "Decide later": leaves the case open as it is.
  final VoidCallback? onLater;

  /// Text colour override (the call screen is always dark).
  final Color? foreground;

  @override
  ConsumerState<CaseOutcomeForm> createState() => _CaseOutcomeFormState();
}

enum _Outcome {
  resolved(EscalationStatus.resolved, Icons.check_circle_rounded),
  referred(EscalationStatus.referred, Icons.medical_services_rounded),
  ambulance(EscalationStatus.ambulance, Icons.local_hospital_rounded);

  const _Outcome(this.status, this.icon);
  final EscalationStatus status;
  final IconData icon;
}

class _CaseOutcomeFormState extends ConsumerState<CaseOutcomeForm> {
  _Outcome? _choice;
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _noteRequired =>
      _choice == _Outcome.referred || _choice == _Outcome.ambulance;

  Future<void> _save() async {
    final choice = _choice;
    if (choice == null) return;
    if (_noteRequired && _note.text.trim().isEmpty) {
      setState(() => _error = choice == _Outcome.referred
          ? 'Say why you are referring the patient.'
          : 'Note the reason and the patient\'s location.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(escalationsProvider.notifier).recordOutcome(
            widget.escalationId,
            choice.status,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) widget.onDone();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = widget.foreground ?? c.textPrimary;
    final isDoctor = ref.watch(currentUserProvider)?.role == UserRole.doctor;
    final escalation =
        (ref.watch(escalationsProvider).valueOrNull ?? const <Escalation>[])
            .where((e) => e.id == widget.escalationId)
            .firstOrNull;
    final allowed = escalation?.status.next ?? const <EscalationStatus>{};
    final options =
        _Outcome.values.where((o) => allowed.contains(o.status)).toList();

    String label(_Outcome o) => switch (o) {
          _Outcome.resolved => 'Resolved',
          _Outcome.referred =>
            isDoctor ? 'Refer to specialist' : 'Refer to doctor',
          _Outcome.ambulance => 'Dispatch ambulance',
        };
    Color color(_Outcome o) => switch (o) {
          _Outcome.resolved => c.success,
          _Outcome.referred => c.warning,
          _Outcome.ambulance => c.critical,
        };

    if (escalation != null && !escalation.status.isOpen) {
      return Text('This case is resolved.', style: TextStyle(color: fg));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('What happens next?',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: fg)),
        const SizedBox(height: 12),
        for (final o in options) ...[
          _OptionTile(
            icon: o.icon,
            label: label(o),
            color: color(o),
            foreground: fg,
            selected: _choice == o,
            onTap: _saving ? null : () => setState(() => _choice = o),
          ),
          const SizedBox(height: 8),
        ],
        if (_choice == _Outcome.ambulance)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Simulation: the dispatch is recorded and the patient and doctors are '
              'notified, but no real ambulance is sent.',
              style: TextStyle(fontSize: 12, color: fg.fade(0.75)),
            ),
          ),
        if (_choice != null) ...[
          TextField(
            controller: _note,
            enabled: !_saving,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(color: fg),
            decoration: InputDecoration(
              labelText: _noteRequired ? 'Note (required)' : 'Note (optional)',
              hintText: switch (_choice!) {
                _Outcome.resolved => 'e.g. Reassured, readings back to normal',
                _Outcome.referred =>
                  'e.g. Chest pain since morning, please review',
                _Outcome.ambulance =>
                  'e.g. Suspected MI, patient at home address',
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: TextStyle(
                      color: c.critical, fontWeight: FontWeight.w600)),
            ),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: color(_choice!)),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(label(_choice!)),
            ),
          ),
        ],
        if (widget.onLater != null)
          TextButton(
            onPressed: _saving ? null : widget.onLater,
            child: Text('Decide later', style: TextStyle(color: fg.fade(0.8))),
          ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.foreground,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.fade(0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? color : foreground.fade(0.25),
                width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: foreground)),
              ),
              if (selected)
                Icon(Icons.radio_button_checked, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens [CaseOutcomeForm] as a bottom sheet (e.g. from the triage queue,
/// when the clinician couldn't or didn't need to call).
Future<void> showCaseOutcomeSheet(BuildContext context, String escalationId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: SingleChildScrollView(
        child: CaseOutcomeForm(
          escalationId: escalationId,
          onDone: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    ),
  );
}
