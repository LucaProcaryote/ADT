import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';

/// The colour a bed status is drawn in.
///
/// These four are seen together on the bed board, so they were validated as a
/// set for colour-vision deficiency and contrast rather than picked by eye.
/// Every bed still carries its status in words as well - the colour is a
/// shortcut for people who can use it, never the only channel.
Color bedStatusColor(BuildContext context, BedStatus status) =>
    switch (status) {
      BedStatus.free => HospitalTheme.successOf(context),
      BedStatus.occupied => HospitalTheme.infoOf(context),
      BedStatus.cleaning => HospitalTheme.warningOf(context),
      BedStatus.blocked => Theme.of(context).colorScheme.outline,
    };

IconData bedStatusIcon(BedStatus status) => switch (status) {
  BedStatus.free => Icons.check_circle_outline,
  BedStatus.occupied => Icons.person,
  BedStatus.cleaning => Icons.cleaning_services_outlined,
  BedStatus.blocked => Icons.block,
};

/// The legend shown above the bed board. With four statuses on screen at once
/// a legend is not optional.
class BedStatusLegend extends StatelessWidget {
  const BedStatusLegend({super.key, required this.counts});

  final Map<BedStatus, int> counts;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return Wrap(
      spacing: Gap.md,
      runSpacing: Gap.sm,
      children: <Widget>[
        for (final status in BedStatus.values)
          StatusChip(
            label:
                '${status.display.forLanguage(language)} '
                '· ${counts[status] ?? 0}',
            color: bedStatusColor(context, status),
            icon: bedStatusIcon(status),
          ),
      ],
    );
  }
}
