# ADT — Admission, Transfer and Discharge

Part of **Mini-Hospital 2026**, a teaching hospital built for the course on
hospital, e-health and connected-medical-device informatics.

This application moves patients: it admits them, transfers them between beds
and wards, discharges them, and keeps the bed board that everyone else reads.

## Run it

```bash
flutter pub get
flutter run -d chrome
```

No database and no Docker required — it starts on the in-memory dataset with
the hospital already half full, which gives you beds to free, patients to move
and a movement history to read.

## What is in it

| Screen | What it does |
|---|---|
| **Bed board** | Every bed in the hospital, grouped by ward: who is in it, how long they have been there, and whether it is free, occupied, being cleaned or blocked. Filter by ward. Tap a bed to act on it. |
| **Patients** | All patients, filtered by whether they are in the hospital. One click to admit, transfer or discharge. |
| **Movements** | The append-only movement log, each row labelled with the HL7 v2 trigger event it corresponds to (`ADT^A01`, `A02`, `A03`). |

### The three movements

**Admission** opens an encounter, claims a free bed and writes an `A01`.
**Transfer** releases the old bed, claims the new one and writes an `A02`.
**Discharge** closes the encounter, sends the bed to cleaning and writes an
`A03`.

A discharged bed goes to **cleaning**, not straight to free. Housekeeping
releases it afterwards. A bed that becomes instantly available the moment a
patient leaves is the kind of detail that makes a simulation unconvincing to
anyone who has worked on a ward — and it gives the students a state machine
with more than two states.

### Consistency

Each movement touches three things that have to agree: the encounter, the bed
and the movement log. `AdtService` owns all three, so the bed board can never
disagree with the patient list.

The in-memory and REST backends have no multi-row transaction, so the writes
are ordered such that an interruption leaves a readable state rather than a
contradictory one — the bed is released before the encounter is closed, and
claimed after the encounter is opened. A production deployment would wrap these
in a database transaction. That gap is deliberate and worth discussing with the
students; the ordering is documented in `lib/src/services/adt_service.dart`.

### Talking to the rest of the hospital

Every movement is published to the EAI integration engine as an HL7-flavoured
event. Publishing is **best-effort by design**: the movement is committed to
the ADT database first, and the user is told separately whether the integration
engine accepted it. Losing a transfer because a downstream system is down is
precisely the failure interface engines exist to prevent.

```bash
flutter run -d chrome --dart-define=EAI_BASE=http://localhost:8084
```

If the engine is unreachable, the movement still happens and the snackbar says
so. Try it: stop the EAI application and admit somebody.

## Languages

English, French and Dutch throughout, switchable from the toolbar. Bed statuses
and ward names come from the database and are translated there, not in the
interface strings.

Every bed status is written out as well as coloured. The four status colours
were validated as a set for colour-vision deficiency and for contrast in both
light and dark mode, but colour is never the only channel — see
`lib/src/widgets/bed_status_legend.dart`.

## Configuration

| Define | Values | Default |
|---|---|---|
| `BACKEND` | `memory`, `restApi`, `dataConnect` | `memory` |
| `AUTH` | `demo`, `firebase` | `demo` |
| `API_BASE` | this application's API | `http://localhost:8082` |
| `EAI_BASE` | the integration engine | `http://localhost:8084` |

## Tests

```bash
flutter test
```

Seventeen tests. The service tests are the interesting ones: they check that a
patient is never admitted twice, that two patients never end up in one bed,
that a discharged bed cannot be filled until it has been cleaned, and that
admitting, transferring twice and discharging leaves a movement log whose every
origin matches the previous destination.
