import 'package:hospital_core/hospital_core.dart';
import 'package:uuid/uuid.dart';

/// Why an admission, transfer or discharge cannot go ahead.
enum AdtRefusal {
  patientAlreadyAdmitted,
  patientNotAdmitted,
  bedNotFree,
  bedNotFound,
  sameBed,
}

/// The outcome of an ADT operation.
///
/// [published] is reported separately from [encounter] on purpose: the movement
/// is always committed to the ADT database first, and whether the integration
/// engine accepted it is a second, independent fact the user needs to see.
class AdtResult {
  const AdtResult._({
    this.encounter,
    this.movement,
    this.refusal,
    this.published = false,
    this.publishError,
  });

  const AdtResult.refused(AdtRefusal reason) : this._(refusal: reason);

  const AdtResult.done({
    required Encounter encounter,
    required Movement movement,
    required bool published,
    String? publishError,
  }) : this._(
         encounter: encounter,
         movement: movement,
         published: published,
         publishError: publishError,
       );

  final Encounter? encounter;
  final Movement? movement;
  final AdtRefusal? refusal;

  /// Whether the integration engine acknowledged the event.
  final bool published;
  final String? publishError;

  bool get isSuccess => refusal == null;
}

/// Admission, transfer and discharge.
///
/// Each operation touches three things that have to stay consistent: the
/// encounter, the bed, and the append-only movement log. Doing that in one
/// place - rather than in three screens - is what keeps the bed board from
/// disagreeing with the patient list.
///
/// The in-memory and REST repositories have no multi-row transaction, so the
/// writes are ordered so that a failure part-way through leaves the hospital in
/// a readable state rather than a contradictory one: the bed is released before
/// the encounter is closed, and claimed after the encounter is opened. A real
/// deployment would wrap these in a database transaction, which is a good thing
/// to point out to the students.
class AdtService {
  AdtService({required this.repository, required this.publisher, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final HospitalRepository repository;
  final EventPublisher? publisher;
  final Uuid _uuid;

  /// Admits [patient] into [bed].
  Future<AdtResult> admit({
    required Patient patient,
    required Bed bed,
    required EncounterClass encounterClass,
    required String performedBy,
    String? reason,
    String? attendingPractitioner,
    DateTime? at,
  }) async {
    final existing = await repository.activeEncounterFor(patient.id);
    if (existing != null) {
      return const AdtResult.refused(AdtRefusal.patientAlreadyAdmitted);
    }

    final current = await repository.findBed(bed.id);
    if (current == null) return const AdtResult.refused(AdtRefusal.bedNotFound);
    if (!current.isAvailable) {
      return const AdtResult.refused(AdtRefusal.bedNotFree);
    }

    final now = at ?? DateTime.now();
    final encounterId = 'enc-${_uuid.v4()}';

    final encounter = Encounter(
      id: encounterId,
      patientId: patient.id,
      status: EncounterStatus.inProgress,
      encounterClass: encounterClass,
      admissionDate: now,
      wardId: current.wardId,
      roomId: current.roomId,
      bedId: current.id,
      admittingPractitioner: performedBy,
      attendingPractitioner: attendingPractitioner ?? performedBy,
      reason: reason,
      visitNumber: 'V${now.year}-${now.millisecondsSinceEpoch % 100000}',
    );

    // Open the stay first, then claim the bed: an interruption here leaves an
    // admitted patient without a bed, which the bed board shows as "waiting for
    // a bed" rather than as a bed occupied by nobody.
    await repository.saveEncounter(encounter);
    await repository.saveBed(
      current.copyWith(
        status: BedStatus.occupied,
        currentEncounterId: encounterId,
        currentPatientId: patient.id,
      ),
    );

    final movement = Movement(
      id: 'mv-${_uuid.v4()}',
      encounterId: encounterId,
      patientId: patient.id,
      type: MovementType.admission,
      occurredAt: now,
      performedBy: performedBy,
      toWardId: current.wardId,
      toBedId: current.id,
      note: reason,
    );
    await repository.addMovement(movement);

    return _publish(encounter: encounter, movement: movement);
  }

  /// Moves an admitted patient to another bed.
  Future<AdtResult> transfer({
    required Encounter encounter,
    required Bed destination,
    required String performedBy,
    String? note,
    DateTime? at,
  }) async {
    if (!encounter.status.isActive) {
      return const AdtResult.refused(AdtRefusal.patientNotAdmitted);
    }
    if (encounter.bedId == destination.id) {
      return const AdtResult.refused(AdtRefusal.sameBed);
    }

    final target = await repository.findBed(destination.id);
    if (target == null) return const AdtResult.refused(AdtRefusal.bedNotFound);
    if (!target.isAvailable) {
      return const AdtResult.refused(AdtRefusal.bedNotFree);
    }

    final now = at ?? DateTime.now();
    final origin = encounter.bedId == null
        ? null
        : await repository.findBed(encounter.bedId!);

    // Release the old bed before claiming the new one, so a failure between the
    // two frees a bed rather than double-booking the patient.
    if (origin != null) {
      await repository.saveBed(
        origin.copyWith(status: BedStatus.cleaning, clearOccupant: true),
      );
    }
    await repository.saveBed(
      target.copyWith(
        status: BedStatus.occupied,
        currentEncounterId: encounter.id,
        currentPatientId: encounter.patientId,
      ),
    );

    final updated = encounter.copyWith(
      wardId: target.wardId,
      roomId: target.roomId,
      bedId: target.id,
    );
    await repository.saveEncounter(updated);

    final movement = Movement(
      id: 'mv-${_uuid.v4()}',
      encounterId: encounter.id,
      patientId: encounter.patientId,
      type: MovementType.transfer,
      occurredAt: now,
      performedBy: performedBy,
      fromWardId: origin?.wardId,
      fromBedId: origin?.id,
      toWardId: target.wardId,
      toBedId: target.id,
      note: note,
    );
    await repository.addMovement(movement);

    return _publish(encounter: updated, movement: movement);
  }

  /// Closes the stay and releases the bed for cleaning.
  Future<AdtResult> discharge({
    required Encounter encounter,
    required String performedBy,
    String disposition = 'home',
    String? note,
    DateTime? at,
  }) async {
    if (!encounter.status.isActive) {
      return const AdtResult.refused(AdtRefusal.patientNotAdmitted);
    }

    final now = at ?? DateTime.now();
    final bed = encounter.bedId == null
        ? null
        : await repository.findBed(encounter.bedId!);

    // A discharged bed goes to cleaning, not straight to free: a bed that
    // becomes instantly available the moment a patient leaves is the kind of
    // detail that makes a simulation unconvincing to anyone who has worked on
    // a ward.
    if (bed != null) {
      await repository.saveBed(
        bed.copyWith(status: BedStatus.cleaning, clearOccupant: true),
      );
    }

    final closed = Encounter(
      id: encounter.id,
      patientId: encounter.patientId,
      status: EncounterStatus.finished,
      encounterClass: encounter.encounterClass,
      admissionDate: encounter.admissionDate,
      dischargeDate: now,
      admittingPractitioner: encounter.admittingPractitioner,
      attendingPractitioner: encounter.attendingPractitioner,
      reason: encounter.reason,
      dischargeDisposition: disposition,
      visitNumber: encounter.visitNumber,
    );
    await repository.saveEncounter(closed);

    final movement = Movement(
      id: 'mv-${_uuid.v4()}',
      encounterId: encounter.id,
      patientId: encounter.patientId,
      type: MovementType.discharge,
      occurredAt: now,
      performedBy: performedBy,
      fromWardId: bed?.wardId,
      fromBedId: bed?.id,
      note: note,
    );
    await repository.addMovement(movement);

    return _publish(encounter: closed, movement: movement);
  }

  /// Marks a bed clean, blocked or free without moving anybody.
  Future<Bed> setBedStatus(Bed bed, BedStatus status) =>
      repository.saveBed(bed.copyWith(status: status, clearOccupant: true));

  Future<AdtResult> _publish({
    required Encounter encounter,
    required Movement movement,
  }) async {
    if (publisher == null) {
      return AdtResult.done(
        encounter: encounter,
        movement: movement,
        published: false,
      );
    }
    final result = await publisher!.publishMovement(
      movement: movement,
      encounter: encounter,
    );
    return AdtResult.done(
      encounter: encounter,
      movement: movement,
      published: result.delivered,
      publishError: result.error,
    );
  }
}
