import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';

import '../widgets/movement_dialogs.dart';

/// The patient list from the ADT point of view: who is in, who is not, and the
/// action each of them is a candidate for.
class AdtPatientsScreen extends StatefulWidget {
  const AdtPatientsScreen({super.key});

  @override
  State<AdtPatientsScreen> createState() => _AdtPatientsScreenState();
}

enum _Filter { all, admitted, notAdmitted }

class _AdtPatientsScreenState extends State<AdtPatientsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            children: <Widget>[
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: l10n.patientSearchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              Gap.h8,
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<_Filter>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<_Filter>>[
                    ButtonSegment<_Filter>(
                      value: _Filter.all,
                      label: Text(l10n.labelAll),
                    ),
                    ButtonSegment<_Filter>(
                      value: _Filter.admitted,
                      label: Text(l10n.dashboardAdmittedPatients),
                    ),
                    ButtonSegment<_Filter>(
                      value: _Filter.notAdmitted,
                      label: Text(l10n.encounterNone),
                    ),
                  ],
                  selected: <_Filter>{_filter},
                  onSelectionChanged: (value) =>
                      setState(() => _filter = value.first),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RepositoryBuilder<_Data>(
            query: (repository) async {
              final patients = await repository.listPatients(query: _query);
              final encounters = await repository.listEncounters(
                activeOnly: true,
              );
              final beds = await repository.listBeds();
              final wards = await repository.listWards();
              return _Data(
                patients: patients,
                encounters: <String, Encounter>{
                  for (final e in encounters) e.patientId: e,
                },
                beds: <String, Bed>{for (final b in beds) b.id: b},
                wards: <String, Ward>{for (final w in wards) w.id: w},
              );
            },
            builder: (context, data) {
              final shown = data.patients.where((patient) {
                final admitted = data.encounters.containsKey(patient.id);
                return switch (_filter) {
                  _Filter.all => true,
                  _Filter.admitted => admitted,
                  _Filter.notAdmitted => !admitted,
                };
              }).toList();

              if (shown.isEmpty) {
                return EmptyView(
                  message: l10n.labelNoResults,
                  icon: Icons.person_search_outlined,
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(Gap.sm),
                itemCount: shown.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final patient = shown[index];
                  final encounter = data.encounters[patient.id];
                  final bed = encounter?.bedId == null
                      ? null
                      : data.beds[encounter!.bedId];
                  final ward = encounter?.wardId == null
                      ? null
                      : data.wards[encounter!.wardId];

                  return ListTile(
                    leading: PatientAvatar(patient: patient, radius: 20),
                    title: Text(
                      patient.listName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      encounter == null
                          ? '${l10n.patientAgeYears(patient.ageAt())} · '
                                '${patient.mrn} · ${l10n.encounterNone}'
                          : '${l10n.patientAgeYears(patient.ageAt())} · '
                                '${patient.mrn} · '
                                '${ward?.name.forLanguage(language) ?? '—'} '
                                '${bed?.label ?? l10n.locationNotPlaced} · '
                                '${l10n.encounterDays(encounter.lengthOfStayDays)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: encounter == null
                        ? FilledButton.tonalIcon(
                            onPressed: () => showAdmissionDialog(
                              context: context,
                              patient: patient,
                            ),
                            icon: const Icon(Icons.login, size: 16),
                            label: Text(l10n.adtAdmission),
                          )
                        : Wrap(
                            spacing: Gap.sm,
                            children: <Widget>[
                              IconButton(
                                tooltip: l10n.adtTransfer,
                                icon: const Icon(Icons.swap_horiz),
                                onPressed: () => showTransferDialog(
                                  context: context,
                                  patient: patient,
                                  encounter: encounter,
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.adtDischarge,
                                icon: const Icon(Icons.logout),
                                onPressed: () => showDischargeDialog(
                                  context: context,
                                  patient: patient,
                                  encounter: encounter,
                                  bedLabel: bed?.label,
                                ),
                              ),
                            ],
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Data {
  const _Data({
    required this.patients,
    required this.encounters,
    required this.beds,
    required this.wards,
  });

  final List<Patient> patients;
  final Map<String, Encounter> encounters;
  final Map<String, Bed> beds;
  final Map<String, Ward> wards;
}
