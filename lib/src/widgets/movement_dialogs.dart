import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import '../services/adt_service.dart';
import 'bed_picker.dart';

/// Turns a refusal into a sentence in the user's language.
String describeRefusal(HospitalLocalizations l10n, AdtRefusal refusal) =>
    switch (refusal) {
      AdtRefusal.patientAlreadyAdmitted => l10n.adtAlreadyAdmitted,
      AdtRefusal.patientNotAdmitted => l10n.encounterNone,
      AdtRefusal.bedNotFree => l10n.adtNoFreeBed,
      AdtRefusal.bedNotFound => l10n.errorNotFound,
      AdtRefusal.sameBed => l10n.errorGeneric,
    };

/// Reports the outcome, including whether the integration engine took it.
///
/// The movement is committed either way; the second line tells the user
/// whether the rest of the hospital has heard about it yet. Silently swallowing
/// a failed publish is how integration problems go unnoticed for a week.
void reportResult(
  BuildContext context,
  AdtResult result,
  String successMessage,
) {
  final l10n = HospitalLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  if (!result.isSuccess) {
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: HospitalTheme.criticalOf(context),
        content: Text(describeRefusal(l10n, result.refusal!)),
      ),
    );
    return;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(successMessage),
          Text(
            result.published ? l10n.adtEmitEvent : l10n.adtEmitFailed,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

/// Admits a patient: pick the type of stay and a free bed.
Future<void> showAdmissionDialog({
  required BuildContext context,
  required Patient patient,
}) async {
  final service = context.read<AdtService>();
  final user = context.read<AuthService>().currentUser;
  final l10n = HospitalLocalizations.of(context);

  final request = await showDialog<_AdmissionRequest>(
    context: context,
    builder: (context) => _AdmissionDialog(patient: patient),
  );
  if (request == null || !context.mounted) return;

  final result = await service.admit(
    patient: patient,
    bed: request.bed,
    encounterClass: request.encounterClass,
    performedBy: user?.displayName ?? 'Unknown',
    reason: request.reason,
  );
  if (!context.mounted) return;

  reportResult(
    context,
    result,
    l10n.adtAdmissionSuccess(patient.fullName, request.bed.label),
  );
}

/// Moves an admitted patient to another bed.
Future<void> showTransferDialog({
  required BuildContext context,
  required Patient patient,
  required Encounter encounter,
}) async {
  final service = context.read<AdtService>();
  final user = context.read<AuthService>().currentUser;
  final l10n = HospitalLocalizations.of(context);

  final request = await showDialog<_TransferRequest>(
    context: context,
    builder: (context) =>
        _TransferDialog(patient: patient, currentBedId: encounter.bedId),
  );
  if (request == null || !context.mounted) return;

  final result = await service.transfer(
    encounter: encounter,
    destination: request.bed,
    performedBy: user?.displayName ?? 'Unknown',
    note: request.note,
  );
  if (!context.mounted) return;

  reportResult(
    context,
    result,
    l10n.adtTransferSuccess(patient.fullName, request.bed.label),
  );
}

/// Discharges a patient after an explicit confirmation.
Future<void> showDischargeDialog({
  required BuildContext context,
  required Patient patient,
  required Encounter encounter,
  String? bedLabel,
}) async {
  final service = context.read<AdtService>();
  final user = context.read<AuthService>().currentUser;
  final l10n = HospitalLocalizations.of(context);

  final request = await showDialog<_DischargeRequest>(
    context: context,
    builder: (context) =>
        _DischargeDialog(patient: patient, bedLabel: bedLabel ?? '—'),
  );
  if (request == null || !context.mounted) return;

  final result = await service.discharge(
    encounter: encounter,
    performedBy: user?.displayName ?? 'Unknown',
    disposition: request.disposition,
    note: request.note,
  );
  if (!context.mounted) return;

  reportResult(context, result, l10n.adtDischargeSuccess(patient.fullName));
}

// ---------------------------------------------------------------------------

class _AdmissionRequest {
  const _AdmissionRequest({
    required this.bed,
    required this.encounterClass,
    this.reason,
  });

  final Bed bed;
  final EncounterClass encounterClass;
  final String? reason;
}

class _AdmissionDialog extends StatefulWidget {
  const _AdmissionDialog({required this.patient});
  final Patient patient;

  @override
  State<_AdmissionDialog> createState() => _AdmissionDialogState();
}

class _AdmissionDialogState extends State<_AdmissionDialog> {
  final _reasonController = TextEditingController();
  EncounterClass _class = EncounterClass.inpatient;
  Bed? _bed;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;

    return AlertDialog(
      title: Text(l10n.adtNewAdmission),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PatientIdentityBar(patient: widget.patient, dense: true),
              Gap.h8,
              AllergyBanner(patient: widget.patient),
              Gap.h16,
              DropdownButtonFormField<EncounterClass>(
                initialValue: _class,
                decoration: InputDecoration(labelText: l10n.adtEncounterClass),
                items: <DropdownMenuItem<EncounterClass>>[
                  for (final value in EncounterClass.values)
                    DropdownMenuItem<EncounterClass>(
                      value: value,
                      child: Text(value.display.forLanguage(language)),
                    ),
                ],
                onChanged: (value) => setState(() => _class = value ?? _class),
              ),
              Gap.h16,
              TextField(
                controller: _reasonController,
                decoration: InputDecoration(labelText: l10n.encounterReason),
              ),
              Gap.h16,
              BedPicker(
                selectedBedId: _bed?.id,
                onSelected: (bed) => setState(() => _bed = bed),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _bed == null
              ? null
              : () => Navigator.of(context).pop(
                  _AdmissionRequest(
                    bed: _bed!,
                    encounterClass: _class,
                    reason: _reasonController.text.trim().isEmpty
                        ? null
                        : _reasonController.text.trim(),
                  ),
                ),
          child: Text(l10n.adtAdmitPatient),
        ),
      ],
    );
  }
}

class _TransferRequest {
  const _TransferRequest({required this.bed, this.note});
  final Bed bed;
  final String? note;
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.patient, required this.currentBedId});
  final Patient patient;
  final String? currentBedId;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  final _noteController = TextEditingController();
  Bed? _bed;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adtTransferPatient),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PatientIdentityBar(patient: widget.patient, dense: true),
              Gap.h16,
              TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: '${l10n.labelReason} (${l10n.labelOptional})',
                ),
              ),
              Gap.h16,
              BedPicker(
                selectedBedId: _bed?.id,
                excludeBedId: widget.currentBedId,
                onSelected: (bed) => setState(() => _bed = bed),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _bed == null
              ? null
              : () => Navigator.of(context).pop(
                  _TransferRequest(
                    bed: _bed!,
                    note: _noteController.text.trim().isEmpty
                        ? null
                        : _noteController.text.trim(),
                  ),
                ),
          child: Text(l10n.adtTransfer),
        ),
      ],
    );
  }
}

class _DischargeRequest {
  const _DischargeRequest({required this.disposition, this.note});
  final String disposition;
  final String? note;
}

class _DischargeDialog extends StatefulWidget {
  const _DischargeDialog({required this.patient, required this.bedLabel});
  final Patient patient;
  final String bedLabel;

  @override
  State<_DischargeDialog> createState() => _DischargeDialogState();
}

class _DischargeDialogState extends State<_DischargeDialog> {
  final _noteController = TextEditingController();

  /// HL7 discharge dispositions, kept to the ones this hospital uses.
  static const Map<String, Map<String, String>> _dispositions =
      <String, Map<String, String>>{
        'home': <String, String>{
          'en': 'Home',
          'fr': 'Domicile',
          'nl': 'Naar huis',
        },
        'other-hcf': <String, String>{
          'en': 'Another healthcare facility',
          'fr': 'Autre établissement de soins',
          'nl': 'Andere zorginstelling',
        },
        'rehab': <String, String>{
          'en': 'Rehabilitation',
          'fr': 'Revalidation',
          'nl': 'Revalidatie',
        },
        'snf': <String, String>{
          'en': 'Nursing home',
          'fr': 'Maison de repos et de soins',
          'nl': 'Woonzorgcentrum',
        },
        'aadvice': <String, String>{
          'en': 'Left against medical advice',
          'fr': 'Sortie contre avis médical',
          'nl': 'Vertrokken tegen medisch advies',
        },
        'exp': <String, String>{'en': 'Died', 'fr': 'Décès', 'nl': 'Overleden'},
      };

  String _disposition = 'home';

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;

    return AlertDialog(
      title: Text(l10n.adtDischargePatient),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.adtDischargeConfirm(
                widget.patient.fullName,
                widget.bedLabel,
              ),
            ),
            Gap.h16,
            DropdownButtonFormField<String>(
              initialValue: _disposition,
              decoration: InputDecoration(
                labelText: l10n.adtDischargeDisposition,
              ),
              items: <DropdownMenuItem<String>>[
                for (final entry in _dispositions.entries)
                  DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value[language] ?? entry.value['en']!),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _disposition = value ?? _disposition),
            ),
            Gap.h16,
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: '${l10n.labelNotes} (${l10n.labelOptional})',
              ),
              minLines: 2,
              maxLines: 4,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _DischargeRequest(
              disposition: _disposition,
              note: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
            ),
          ),
          child: Text(l10n.adtDischarge),
        ),
      ],
    );
  }
}
