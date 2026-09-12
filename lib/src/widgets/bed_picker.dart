import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';

import 'bed_status_legend.dart';

/// Ward-then-bed picker used by both admission and transfer.
///
/// Only free beds are selectable. Beds that are occupied, being cleaned or
/// blocked are still shown, greyed out and labelled with why: hiding them would
/// leave a bed manager wondering where room 305 went.
class BedPicker extends StatefulWidget {
  const BedPicker({
    super.key,
    required this.onSelected,
    this.selectedBedId,
    this.excludeBedId,
  });

  final ValueChanged<Bed?> onSelected;
  final String? selectedBedId;

  /// The bed the patient is already in, for a transfer.
  final String? excludeBedId;

  @override
  State<BedPicker> createState() => _BedPickerState();
}

class _BedPickerState extends State<BedPicker> {
  String? _wardId;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);

    return RepositoryBuilder<({List<Ward> wards, List<Bed> beds})>(
      query: (repository) async => (
        wards: await repository.listWards(),
        beds: await repository.listBeds(wardId: _wardId),
      ),
      builder: (context, data) {
        final beds =
            data.beds.where((b) => b.id != widget.excludeBedId).toList()
              ..sort((a, b) => a.label.compareTo(b.label));
        final freeCount = beds.where((b) => b.isAvailable).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButtonFormField<String?>(
              initialValue: _wardId,
              decoration: InputDecoration(labelText: l10n.adtSelectWard),
              items: <DropdownMenuItem<String?>>[
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l10n.labelAll),
                ),
                for (final ward in data.wards)
                  DropdownMenuItem<String?>(
                    value: ward.id,
                    child: Text(ward.name.forLanguage(language)),
                  ),
              ],
              onChanged: (value) {
                setState(() => _wardId = value);
                widget.onSelected(null);
              },
            ),
            Gap.h8,
            if (_wardId != null && freeCount == 0)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: HospitalTheme.warningOf(context),
                    ),
                    Gap.w8,
                    Expanded(
                      child: Text(
                        '${l10n.adtNoFreeBed} ${l10n.adtChooseAnotherWard}.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            Text(l10n.adtSelectBed, style: theme.textTheme.labelMedium),
            Gap.h8,
            SizedBox(
              height: 220,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: <Widget>[
                    for (final bed in beds)
                      _SelectableBed(
                        bed: bed,
                        isSelected: bed.id == widget.selectedBedId,
                        onTap: bed.isAvailable
                            ? () => widget.onSelected(bed)
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SelectableBed extends StatelessWidget {
  const _SelectableBed({
    required this.bed,
    required this.isSelected,
    required this.onTap,
  });

  final Bed bed;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final color = bedStatusColor(context, bed.status);
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 118,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.sm,
            vertical: Gap.sm - 2,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer
                : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : color.withValues(alpha: 0.4),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(bedStatusIcon(bed.status), size: 13, color: color),
                  Gap.w4,
                  Text(
                    bed.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                bed.status.display.forLanguage(language),
                style: theme.textTheme.labelSmall?.copyWith(color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
