import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';

import 'src/adt_home.dart';

/// Entry point of the Admission, Transfer and Discharge application.
///
/// ```
/// flutter run -d chrome                                  # demo data
/// flutter run -d chrome --dart-define=BACKEND=restApi    # local API + Postgres
/// flutter run -d chrome --dart-define=EAI_BASE=http://localhost:8084
/// ```
void main() {
  runApp(
    MiniHospitalApp(
      config: AppConfig.fromEnvironment(HospitalApp.adt),
      title: (l10n) => l10n.appTitleAdt,
      subtitle: (l10n) => l10n.hospitalName,
      homeBuilder: (context) => const AdtHome(),
    ),
  );
}
