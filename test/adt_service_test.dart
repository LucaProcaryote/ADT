import 'package:adt_app/src/services/adt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_core/hospital_core.dart';

void main() {
  late MemoryHospitalRepository repository;
  late AdtService service;

  final now = DateTime.utc(2026, 9, 12, 10);

  setUp(() async {
    repository = MemoryHospitalRepository(seed: HospitalSeed.build(now: now));
    await repository.initialize();
    // No publisher: these tests are about the database staying consistent,
    // and the integration engine is deliberately not a prerequisite.
    service = AdtService(repository: repository, publisher: null);
  });

  Future<Patient> unadmittedPatient() async {
    final patients = await repository.listPatients();
    for (final patient in patients) {
      if (await repository.activeEncounterFor(patient.id) == null) {
        return patient;
      }
    }
    fail('the seed should leave some patients unadmitted');
  }

  Future<Bed> freeBed({String wardId = 'ward-int'}) async =>
      (await repository.listBeds(wardId: wardId, status: BedStatus.free)).first;

  group('admission', () {
    test('opens the stay, claims the bed and logs the movement', () async {
      final patient = await unadmittedPatient();
      final bed = await freeBed();

      final result = await service.admit(
        patient: patient,
        bed: bed,
        encounterClass: EncounterClass.inpatient,
        performedBy: 'Tester',
        reason: 'Observation',
        at: now,
      );

      expect(result.isSuccess, isTrue);

      final encounter = await repository.activeEncounterFor(patient.id);
      expect(encounter, isNotNull);
      expect(encounter!.bedId, bed.id);
      expect(encounter.wardId, bed.wardId);
      expect(encounter.roomId, bed.roomId);
      expect(encounter.status, EncounterStatus.inProgress);
      expect(encounter.reason, 'Observation');

      final updatedBed = (await repository.findBed(bed.id))!;
      expect(updatedBed.status, BedStatus.occupied);
      expect(updatedBed.currentPatientId, patient.id);
      expect(updatedBed.currentEncounterId, encounter.id);

      final movements = await repository.listMovements(
        encounterId: encounter.id,
      );
      expect(movements, hasLength(1));
      expect(movements.single.type, MovementType.admission);
      expect(movements.single.toBedId, bed.id);
      expect(movements.single.performedBy, 'Tester');
    });

    test('refuses a patient who is already in', () async {
      final admitted = (await repository.listEncounters(
        activeOnly: true,
      )).first;
      final patient = (await repository.findPatient(admitted.patientId))!;
      final bed = await freeBed();

      final result = await service.admit(
        patient: patient,
        bed: bed,
        encounterClass: EncounterClass.inpatient,
        performedBy: 'Tester',
      );

      expect(result.isSuccess, isFalse);
      expect(result.refusal, AdtRefusal.patientAlreadyAdmitted);
      // Nothing may have changed.
      expect((await repository.findBed(bed.id))!.status, BedStatus.free);
    });

    test('refuses a bed that is not free', () async {
      final patient = await unadmittedPatient();
      final occupied = (await repository.listBeds(
        status: BedStatus.occupied,
      )).first;

      final result = await service.admit(
        patient: patient,
        bed: occupied,
        encounterClass: EncounterClass.inpatient,
        performedBy: 'Tester',
      );

      expect(result.refusal, AdtRefusal.bedNotFree);
      expect(await repository.activeEncounterFor(patient.id), isNull);
      // The bed still belongs to whoever was in it.
      final after = (await repository.findBed(occupied.id))!;
      expect(after.currentPatientId, occupied.currentPatientId);
    });

    test('refuses a bed being cleaned', () async {
      final patient = await unadmittedPatient();
      final cleaning = (await repository.listBeds(
        status: BedStatus.cleaning,
      )).first;

      final result = await service.admit(
        patient: patient,
        bed: cleaning,
        encounterClass: EncounterClass.inpatient,
        performedBy: 'Tester',
      );
      expect(result.refusal, AdtRefusal.bedNotFree);
    });
  });

  group('transfer', () {
    test('moves the patient and hands the old bed to cleaning', () async {
      final encounter = (await repository.listEncounters(
        activeOnly: true,
      )).firstWhere((e) => e.bedId != null);
      final origin = encounter.bedId!;
      final destination = await freeBed(wardId: 'ward-surg');

      final result = await service.transfer(
        encounter: encounter,
        destination: destination,
        performedBy: 'Tester',
        note: 'Needs surgery',
        at: now,
      );

      expect(result.isSuccess, isTrue);

      final updated = (await repository.findEncounter(encounter.id))!;
      expect(updated.bedId, destination.id);
      expect(updated.wardId, destination.wardId);
      expect(updated.status, EncounterStatus.inProgress);

      // The bed just vacated is not immediately available.
      final oldBed = (await repository.findBed(origin))!;
      expect(oldBed.status, BedStatus.cleaning);
      expect(oldBed.currentPatientId, isNull);
      expect(oldBed.currentEncounterId, isNull);

      final newBed = (await repository.findBed(destination.id))!;
      expect(newBed.status, BedStatus.occupied);
      expect(newBed.currentPatientId, encounter.patientId);

      final movements = await repository.listMovements(
        encounterId: encounter.id,
      );
      final transfer = movements.firstWhere(
        (m) => m.type == MovementType.transfer,
      );
      expect(transfer.fromBedId, origin);
      expect(transfer.toBedId, destination.id);
      expect(transfer.note, 'Needs surgery');
    });

    test('refuses a transfer into the same bed', () async {
      final encounter = (await repository.listEncounters(
        activeOnly: true,
      )).firstWhere((e) => e.bedId != null);
      final same = (await repository.findBed(encounter.bedId!))!;

      final result = await service.transfer(
        encounter: encounter,
        destination: same,
        performedBy: 'Tester',
      );
      expect(result.refusal, AdtRefusal.sameBed);
    });

    test('refuses to move a discharged patient', () async {
      final finished = (await repository.listEncounters()).firstWhere(
        (e) => e.status == EncounterStatus.finished,
      );
      final destination = await freeBed();

      final result = await service.transfer(
        encounter: finished,
        destination: destination,
        performedBy: 'Tester',
      );
      expect(result.refusal, AdtRefusal.patientNotAdmitted);
      expect(
        (await repository.findBed(destination.id))!.status,
        BedStatus.free,
      );
    });

    test('never leaves two patients in one bed', () async {
      final active = await repository.listEncounters(activeOnly: true);
      final first = active.firstWhere((e) => e.bedId != null);
      final destination = await freeBed(wardId: 'ward-geri');

      await service.transfer(
        encounter: first,
        destination: destination,
        performedBy: 'Tester',
      );

      final occupancy = <String, int>{};
      for (final encounter in await repository.listEncounters(
        activeOnly: true,
      )) {
        if (encounter.bedId == null) continue;
        occupancy[encounter.bedId!] = (occupancy[encounter.bedId!] ?? 0) + 1;
      }
      expect(occupancy.values.every((count) => count == 1), isTrue);
    });
  });

  group('discharge', () {
    test('closes the stay and releases the bed for cleaning', () async {
      final encounter = (await repository.listEncounters(
        activeOnly: true,
      )).firstWhere((e) => e.bedId != null);
      final bedId = encounter.bedId!;

      final result = await service.discharge(
        encounter: encounter,
        performedBy: 'Tester',
        disposition: 'home',
        at: now,
      );

      expect(result.isSuccess, isTrue);

      final closed = (await repository.findEncounter(encounter.id))!;
      expect(closed.status, EncounterStatus.finished);
      expect(closed.dischargeDate, now);
      expect(closed.dischargeDisposition, 'home');
      // A closed stay keeps its admission date and visit number.
      expect(closed.admissionDate, encounter.admissionDate);
      expect(closed.visitNumber, encounter.visitNumber);

      expect(await repository.activeEncounterFor(encounter.patientId), isNull);

      final bed = (await repository.findBed(bedId))!;
      expect(bed.status, BedStatus.cleaning);
      expect(bed.currentPatientId, isNull);
    });

    test('refuses to discharge twice', () async {
      final encounter = (await repository.listEncounters(
        activeOnly: true,
      )).firstWhere((e) => e.bedId != null);
      await service.discharge(encounter: encounter, performedBy: 'Tester');

      final again = (await repository.findEncounter(encounter.id))!;
      final result = await service.discharge(
        encounter: again,
        performedBy: 'Tester',
      );
      expect(result.refusal, AdtRefusal.patientNotAdmitted);
    });

    test('the bed can be readmitted once it has been cleaned', () async {
      final encounter = (await repository.listEncounters(
        activeOnly: true,
      )).firstWhere((e) => e.bedId != null);
      final bedId = encounter.bedId!;
      await service.discharge(encounter: encounter, performedBy: 'Tester');

      final dirty = (await repository.findBed(bedId))!;
      final patient = await unadmittedPatient();

      // Still being cleaned: not yet available.
      var result = await service.admit(
        patient: patient,
        bed: dirty,
        encounterClass: EncounterClass.inpatient,
        performedBy: 'Tester',
      );
      expect(result.refusal, AdtRefusal.bedNotFree);

      // Housekeeping marks it free, and now it can take a patient.
      await service.setBedStatus(dirty, BedStatus.free);
      final clean = (await repository.findBed(bedId))!;
      result = await service.admit(
        patient: patient,
        bed: clean,
        encounterClass: EncounterClass.inpatient,
        performedBy: 'Tester',
      );
      expect(result.isSuccess, isTrue);
    });
  });

  group('the whole journey', () {
    test(
      'admit, transfer twice, discharge leaves a complete audit trail',
      () async {
        final patient = await unadmittedPatient();
        final emergency = await freeBed(wardId: 'ward-emer');

        final admission = await service.admit(
          patient: patient,
          bed: emergency,
          encounterClass: EncounterClass.emergency,
          performedBy: 'Clerk',
          reason: 'Chest pain',
          at: now,
        );
        final encounterId = admission.encounter!.id;

        final icu = await freeBed(wardId: 'ward-icu');
        await service.transfer(
          encounter: (await repository.findEncounter(encounterId))!,
          destination: icu,
          performedBy: 'Nurse',
          at: now.add(const Duration(hours: 2)),
        );

        final cardiology = await freeBed(wardId: 'ward-card');
        await service.transfer(
          encounter: (await repository.findEncounter(encounterId))!,
          destination: cardiology,
          performedBy: 'Nurse',
          at: now.add(const Duration(days: 2)),
        );

        await service.discharge(
          encounter: (await repository.findEncounter(encounterId))!,
          performedBy: 'Clerk',
          disposition: 'home',
          at: now.add(const Duration(days: 5)),
        );

        final movements = await repository.listMovements(
          encounterId: encounterId,
        );
        expect(movements, hasLength(4));

        // Oldest first, so the journey reads in order.
        final ordered = movements.reversed.toList();
        expect(ordered.map((m) => m.type), <MovementType>[
          MovementType.admission,
          MovementType.transfer,
          MovementType.transfer,
          MovementType.discharge,
        ]);

        // Each movement's origin is the previous movement's destination.
        expect(ordered[1].fromBedId, emergency.id);
        expect(ordered[1].toBedId, icu.id);
        expect(ordered[2].fromBedId, icu.id);
        expect(ordered[2].toBedId, cardiology.id);
        expect(ordered[3].fromBedId, cardiology.id);

        final closed = (await repository.findEncounter(encounterId))!;
        expect(closed.status, EncounterStatus.finished);
        expect(closed.lengthOfStayDays, 5);

        // Every bed the patient passed through is free of them.
        for (final bedId in <String>[emergency.id, icu.id, cardiology.id]) {
          expect((await repository.findBed(bedId))!.currentPatientId, isNull);
        }
      },
    );
  });
}
