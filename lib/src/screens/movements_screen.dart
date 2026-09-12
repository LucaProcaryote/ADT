import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';

/// The append-only movement log.
///
/// Replaying it reconstructs the whole patient journey, which is both the audit
/// trail a hospital has to keep and the clearest way to show students what an
/// ADT feed actually carries - each row is labelled with the HL7 v2 trigger
/// event it would be sent as.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  MovementType? _filter;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;

    return Column(
      children: <Widget>[
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                child: FilterChip(
                  selected: _filter == null,
                  label: Text(l10n.labelAll),
                  onSelected: (_) => setState(() => _filter = null),
                ),
              ),
              for (final type in <MovementType>[
                MovementType.admission,
                MovementType.transfer,
                MovementType.discharge,
              ])
                Padding(
                  padding: const EdgeInsets.only(
                    left: Gap.sm,
                    top: Gap.sm,
                    bottom: Gap.sm,
                  ),
                  child: FilterChip(
                    selected: _filter == type,
                    label: Text(
                      '${type.display.forLanguage(language)} '
                      '(${type.hl7EventCode})',
                    ),
                    onSelected: (_) => setState(() => _filter = type),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RepositoryBuilder<_Data>(
            query: (repository) async {
              final movements = await repository.listMovements(limit: 200);
              final patients = <String, Patient>{};
              for (final movement in movements) {
                if (patients.containsKey(movement.patientId)) continue;
                final patient = await repository.findPatient(movement.patientId);
                if (patient != null) patients[patient.id] = patient;
              }
              final beds = await repository.listBeds();
              final wards = await repository.listWards();
              return _Data(
                movements: movements,
                patients: patients,
                beds: <String, Bed>{for (final b in beds) b.id: b},
                wards: <String, Ward>{for (final w in wards) w.id: w},
              );
            },
            builder: (context, data) {
              final shown = _filter == null
                  ? data.movements
                  : data.movements.where((m) => m.type == _filter).toList();

              if (shown.isEmpty) {
                return EmptyView(
                  message: l10n.adtNoMovements,
                  icon: Icons.swap_horiz,
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(Gap.md),
                itemCount: shown.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _MovementTile(movement: shown[index], data: data),
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
    required this.movements,
    required this.patients,
    required this.beds,
    required this.wards,
  });

  final List<Movement> movements;
  final Map<String, Patient> patients;
  final Map<String, Bed> beds;
  final Map<String, Ward> wards;
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, required this.data});

  final Movement movement;
  final _Data data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final patient = data.patients[movement.patientId];

    final color = switch (movement.type) {
      MovementType.admission => HospitalTheme.successOf(context),
      MovementType.discharge => HospitalTheme.infoOf(context),
      MovementType.transfer => HospitalTheme.warningOf(context),
      _ => theme.colorScheme.outline,
    };
    final icon = switch (movement.type) {
      MovementType.admission => Icons.login,
      MovementType.discharge => Icons.logout,
      MovementType.transfer => Icons.swap_horiz,
      _ => Icons.circle_outlined,
    };

    String where(String? wardId, String? bedId) {
      if (wardId == null && bedId == null) return '—';
      final ward = wardId == null ? null : data.wards[wardId];
      final bed = bedId == null ? null : data.beds[bedId];
      return <String>[
        if (ward != null) ward.name.forLanguage(language),
        if (bed != null) bed.label,
      ].join(' · ');
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, size: 16, color: color),
      ),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              patient?.listName ?? movement.patientId,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          StatusChip(
            label: '${movement.type.display.forLanguage(language)} '
                '· ADT^${movement.type.hl7EventCode}',
            color: color,
            dense: true,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            movement.type == MovementType.admission
                ? '${l10n.labelTo} ${where(movement.toWardId, movement.toBedId)}'
                : movement.type == MovementType.discharge
                    ? '${l10n.labelFrom} ${where(movement.fromWardId, movement.fromBedId)}'
                    : '${where(movement.fromWardId, movement.fromBedId)} '
                        '→ ${where(movement.toWardId, movement.toBedId)}',
            style: theme.textTheme.bodySmall,
          ),
          if (movement.note != null)
            Text(
              movement.note!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          Text(
            '${Formats.dateTime(context, movement.occurredAt)} · '
            '${l10n.labelBy} ${movement.performedBy}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      isThreeLine: true,
    );
  }
}
