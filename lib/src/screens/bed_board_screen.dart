import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import '../services/adt_service.dart';
import '../widgets/bed_status_legend.dart';
import '../widgets/movement_dialogs.dart';

/// The bed board: every bed in the hospital, grouped by ward, with who is in
/// it. This is the screen a bed manager lives on.
class BedBoardScreen extends StatefulWidget {
  const BedBoardScreen({super.key});

  @override
  State<BedBoardScreen> createState() => _BedBoardScreenState();
}

class _BedBoardScreenState extends State<BedBoardScreen> {
  String? _wardFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;

    return RepositoryBuilder<_BoardData>(
      query: (repository) async {
        final wards = await repository.listWards();
        final rooms = await repository.listRooms();
        final beds = await repository.listBeds(wardId: _wardFilter);
        final encounters = await repository.listEncounters(activeOnly: true);
        final patients = <String, Patient>{};
        for (final encounter in encounters) {
          final patient = await repository.findPatient(encounter.patientId);
          if (patient != null) patients[patient.id] = patient;
        }
        return _BoardData(
          wards: wards,
          rooms: <String, Room>{for (final room in rooms) room.id: room},
          beds: beds,
          encounters: <String, Encounter>{
            for (final encounter in encounters) encounter.id: encounter,
          },
          patients: patients,
        );
      },
      builder: (context, data) {
        final counts = <BedStatus, int>{};
        for (final bed in data.beds) {
          counts[bed.status] = (counts[bed.status] ?? 0) + 1;
        }

        final wardsShown = _wardFilter == null
            ? data.wards
            : data.wards.where((w) => w.id == _wardFilter).toList();

        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: <Widget>[
                        FilterChip(
                          selected: _wardFilter == null,
                          label: Text(l10n.labelAll),
                          onSelected: (_) => setState(() => _wardFilter = null),
                        ),
                        for (final ward in data.wards)
                          Padding(
                            padding: const EdgeInsets.only(left: Gap.sm),
                            child: FilterChip(
                              selected: _wardFilter == ward.id,
                              label: Text(ward.name.forLanguage(language)),
                              onSelected: (_) =>
                                  setState(() => _wardFilter = ward.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Gap.h16,
                  BedStatusLegend(counts: counts),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Gap.md),
                children: <Widget>[
                  for (final ward in wardsShown)
                    _WardSection(ward: ward, data: data),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BoardData {
  const _BoardData({
    required this.wards,
    required this.rooms,
    required this.beds,
    required this.encounters,
    required this.patients,
  });

  final List<Ward> wards;
  final Map<String, Room> rooms;
  final List<Bed> beds;
  final Map<String, Encounter> encounters;
  final Map<String, Patient> patients;
}

class _WardSection extends StatelessWidget {
  const _WardSection({required this.ward, required this.data});

  final Ward ward;
  final _BoardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final beds = data.beds.where((b) => b.wardId == ward.id).toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    if (beds.isEmpty) return const SizedBox.shrink();

    final free = beds.where((b) => b.isAvailable).length;
    final occupied = beds.where((b) => b.status == BedStatus.occupied).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: SectionCard(
        title:
            '${ward.name.forLanguage(language)} '
            '(${l10n.locationFloor} ${ward.floor})',
        icon: Icons.meeting_room_outlined,
        trailing: Padding(
          padding: const EdgeInsets.only(right: Gap.sm),
          child: Text(
            '${l10n.adtBedsFree(free)} · ${l10n.adtBedsOccupied(occupied)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        child: Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: <Widget>[
            for (final bed in beds) _BedCard(bed: bed, data: data),
          ],
        ),
      ),
    );
  }
}

class _BedCard extends StatelessWidget {
  const _BedCard({required this.bed, required this.data});

  final Bed bed;
  final _BoardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final color = bedStatusColor(context, bed.status);
    final encounter = bed.currentEncounterId == null
        ? null
        : data.encounters[bed.currentEncounterId];
    final patient = bed.currentPatientId == null
        ? null
        : data.patients[bed.currentPatientId];

    return SizedBox(
      width: 190,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openActions(context, patient, encounter),
        child: Container(
          padding: const EdgeInsets.all(Gap.sm + 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(bedStatusIcon(bed.status), size: 14, color: color),
                  Gap.w4,
                  Text(
                    bed.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (data.rooms[bed.roomId]?.isIsolation ?? false)
                    Icon(
                      Icons.shield_outlined,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              // The status is always written out, not only coloured.
              Text(
                bed.status.display.forLanguage(language),
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
              const SizedBox(height: 6),
              if (patient != null) ...<Widget>[
                Text(
                  patient.listName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${patient.ageAt()}y · ${patient.mrn}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (patient.hasHighRiskAllergy)
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 13,
                        color: HospitalTheme.criticalOf(context),
                      ),
                  ],
                ),
                if (encounter != null)
                  Text(
                    '${encounter.lengthOfStayDays} d',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ] else
                Text(
                  '—',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openActions(
    BuildContext context,
    Patient? patient,
    Encounter? encounter,
  ) async {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final service = context.read<AdtService>();
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                '${l10n.locationBed} ${bed.label}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(bed.status.display.forLanguage(language)),
            ),
            const Divider(height: 1),
            if (patient != null && encounter != null) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(l10n.adtTransferPatient),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showTransferDialog(
                    context: context,
                    patient: patient,
                    encounter: encounter,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l10n.adtDischargePatient),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showDischargeDialog(
                    context: context,
                    patient: patient,
                    encounter: encounter,
                    bedLabel: bed.label,
                  );
                },
              ),
            ] else ...<Widget>[
              for (final status in <BedStatus>[
                BedStatus.free,
                BedStatus.cleaning,
                BedStatus.blocked,
              ])
                if (status != bed.status)
                  ListTile(
                    leading: Icon(bedStatusIcon(status)),
                    title: Text(
                      '${l10n.adtSetBedStatus}: '
                      '${status.display.forLanguage(language)}',
                    ),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await service.setBedStatus(bed, status);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '${bed.label} → '
                            '${status.display.forLanguage(language)}',
                          ),
                        ),
                      );
                    },
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
