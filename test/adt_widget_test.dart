import 'package:adt_app/src/adt_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_core/hospital_core.dart';

Future<MemoryHospitalRepository> pumpAdt(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final repository = MemoryHospitalRepository(
    seed: HospitalSeed.build(now: DateTime.utc(2026, 9, 12, 10)),
  );
  final auth = DemoAuthService();
  await auth.initialize();
  await auth.signInAs(
    seedUsers.firstWhere((u) => u.role == UserRole.admissionClerk),
  );

  await tester.pumpWidget(
    MiniHospitalApp(
      config: const AppConfig(
        app: HospitalApp.adt,
        backendMode: BackendMode.memory,
        authMode: AuthMode.demo,
        apiBaseUrl: '',
        fhirBaseUrl: '',
        eaiBaseUrl: '',
      ),
      title: (l10n) => l10n.appTitleAdt,
      homeBuilder: (context) => const AdtHome(),
      repositoryOverride: repository,
      authOverride: auth,
      localeStore: InMemoryLocaleStore(),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('the bed board shows wards, beds and a status legend', (
    tester,
  ) async {
    await pumpAdt(tester);

    expect(find.text('Admission, Transfer & Discharge'), findsOneWidget);
    expect(find.textContaining('Cardiology'), findsWidgets);
    // The legend names every status in words, not colour alone.
    expect(find.textContaining('Free ·'), findsOneWidget);
    expect(find.textContaining('Occupied ·'), findsOneWidget);
    expect(find.textContaining('Cleaning ·'), findsOneWidget);
    expect(find.textContaining('Blocked ·'), findsOneWidget);
  });

  testWidgets('occupied beds name the patient in them', (tester) async {
    await pumpAdt(tester);

    // Narrow to one ward so the bed is on screen rather than below the fold.
    await tester.tap(find.widgetWithText(FilterChip, 'Intensive care unit'));
    await tester.pumpAndSettle();

    // pat-008 is in intensive care bed 221-A in the seed data.
    expect(find.text('221-A'), findsOneWidget);
    expect(find.textContaining('DE SMET'), findsOneWidget);
    // And the bed says "Occupied" in words, next to the patient.
    expect(find.text('Occupied'), findsOneWidget);
  });

  testWidgets('the movement log labels each row with its HL7 event', (
    tester,
  ) async {
    await pumpAdt(tester);

    await tester.tap(find.text('Movements').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('ADT^A01'), findsWidgets);
    expect(find.textContaining('ADT^A02'), findsWidgets);
  });

  testWidgets('an unadmitted patient is offered the admission action', (
    tester,
  ) async {
    await pumpAdt(tester);

    await tester.tap(find.text('Patients').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Haddad');
    await tester.pumpAndSettle();

    // Amina Haddad is deliberately left unadmitted in the seed data.
    expect(find.textContaining('HADDAD'), findsOneWidget);
    expect(find.text('Admission'), findsOneWidget);
  });

  testWidgets('everything translates', (tester) async {
    await pumpAdt(tester);

    await tester.tap(find.text('NL'));
    await tester.pumpAndSettle();
    expect(find.text('Opname, overplaatsing en ontslag'), findsOneWidget);
    expect(find.textContaining('Vrij ·'), findsOneWidget);

    await tester.tap(find.text('FR'));
    await tester.pumpAndSettle();
    expect(find.text('Admission, transfert et sortie'), findsOneWidget);
    expect(find.textContaining('Libre ·'), findsOneWidget);
  });
}
