import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import 'screens/bed_board_screen.dart';
import 'screens/movements_screen.dart';
import 'screens/patients_screen.dart';
import 'services/adt_service.dart';

/// The ADT application's navigation, with the shared [AdtService] provided
/// above it so every screen performs movements the same way.
class AdtHome extends StatelessWidget {
  const AdtHome({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final config = context.read<AppConfig>();
    final repository = context.read<HospitalRepository>();

    return Provider<AdtService>(
      create: (_) => AdtService(
        repository: repository,
        publisher: EventPublisher(baseUrl: config.eaiBaseUrl),
      ),
      child: AppShell(
        title: l10n.appTitleAdt,
        destinations: <ShellDestination>[
          ShellDestination(
            label: (l10n) => l10n.adtDashboard,
            icon: Icons.grid_view_outlined,
            selectedIcon: Icons.grid_view,
            builder: (context) => const BedBoardScreen(),
          ),
          ShellDestination(
            label: (l10n) => l10n.navPatients,
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
            builder: (context) => const AdtPatientsScreen(),
          ),
          ShellDestination(
            label: (l10n) => l10n.adtMovements,
            icon: Icons.swap_horiz_outlined,
            selectedIcon: Icons.swap_horiz,
            builder: (context) => const MovementsScreen(),
          ),
        ],
      ),
    );
  }
}
