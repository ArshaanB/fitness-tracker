# Fitness Tracker — Technical Design

**Status:** Draft v1 · **Companion to:** [PRD.md](PRD.md) · **Last updated:** 2026-08-08

## 1. Stack

| Layer | Choice | Rationale |
|---|---|---|
| App | Swift + SwiftUI, iOS 17+ | Native feel, modern APIs (Swift Charts, Observation), single platform in v1 |
| Local store | SQLite via **GRDB** | Offline-first source of truth. GRDB over SwiftData: mature migrations, real SQL for the analytical queries (e1RM history, records, charts), and a schema that mirrors Postgres closely |
| Backend | **Supabase** (Postgres + Auth + PostgREST) | Accounts from day one without operating a server; schema is plain Postgres so we can eject later |
| Charts | Swift Charts | Built-in, good enough for v1 charts |

**Offline-first is non-negotiable:** every read and write goes to the local SQLite database first. Supabase is a sync target, never in the logging path. Airplane-mode logging must work end to end.

## 2. Data model

Same logical schema in SQLite and Postgres. All IDs are client-generated UUIDs (required for offline creation). Weights stored as decimal pounds in v1 but in a `weight` column with a per-user unit setting anticipated, so kg is a display-layer change later.

```
users            (Supabase auth)
exercises        id, user_id, name, kind        -- kind: barbell | dumbbell | machine | bodyweight
templates        id, user_id, name, position, archived_at
template_items   id, template_id, exercise_id, position,
                 superset_group,                -- nullable int; unused in v1 (supersets deferred), kept for later
                 rest_seconds, target_set_count
workouts         id, user_id, template_id?, started_at, finished_at?, notes
workout_items    id, workout_id, exercise_id, position, superset_group, rest_seconds
sets             id, workout_item_id, position, weight?, reps?,
                 seconds?, distance?,           -- imported timed/cardio history only in v1
                 completed_at?                  -- null = planned but not done
body_weights     id, user_id, measured_at, weight
settings         user_id, weekly_goal (default 3), unit (lbs)
```

Notes:
- An in-progress workout is just a `workouts` row with `finished_at IS NULL`. Resume = load it; the idle prompt fires when `now - last completed set > 6h` (tunable).
- Records (best weight, best e1RM, rep PRs) are **derived, never stored** — computed from `sets` with indexed queries and cached in memory. Editing history therefore recomputes them for free.
- "Previous session numbers" for a template exercise = the sets from the most recent finished workout containing that exercise.

## 3. Core algorithms

**Estimated 1RM — Epley:** `e1RM = weight × (1 + reps/30)`, computed per completed set. Bodyweight exercises use added weight only for e1RM in v1 (open question in PRD; revisit if rings feel wrong on pull-ups).

**Intensity ring:** for the weight (and current rep target) being entered, compare projected e1RM against the exercise's all-time best e1RM:
- `< 70%` → red
- `70–90%` → yellow
- `> 90%` → green
- `≥ 100%` → rainbow (animated)

Thresholds live in one constants file — expect tuning after real gym use.

## 4. Strong CSV import

First feature built. A parser for Strong's export format (one row per set) that:
1. Creates one `exercises` row per distinct exercise name (this *is* the v1 exercise library).
2. Groups rows by (date, workout name) into `workouts` / `workout_items` / `sets`.
3. Runs as a pure, unit-tested function: CSV in → domain objects out. Tested against the owner's real export before any UI exists.

Import is idempotent (re-running doesn't duplicate) so it can be re-run during development.

**Real export profile** (owner's data, 2018-06-16 → 2026-08-08; the local copy lives gitignored at `data/strong_workouts.csv` — personal data never gets committed to this public repo):
- Columns: `Date, Workout Name, Duration, Exercise Name, Set Order, Weight, Reps, Distance, Seconds, Notes, Workout Notes, RPE`.
- 12,596 set rows · 736 workouts (grouped by Date + Workout Name) · 91 distinct exercises.
- Quoted fields with embedded commas appear; date format `YYYY-MM-DD HH:MM:SS`; duration format `1h 5m`.
- ~3,471 zero-weight rows (Push Up, Chin Up, Pull Up, …) → bodyweight exercises; e1RM treats these as reps-only.
- Rows with `Seconds` and `Distance` (planks, treadmill). v1 UI doesn't create timed/cardio sets, but the importer preserves them (`sets` gains nullable `seconds`/`distance` columns) so history is complete.
- RPE column is entirely empty — safely ignored.
- `Set Order` is not always numeric — two special values discovered on first real render:
  - **"Rest Timer"** (1,871 rows): not sets — the configured rest duration per exercise. Imported as `workoutItem.restSeconds`, which will seed template rest times.
  - **"W"** (735 rows): warm-up sets. Imported as real sets with `isWarmup = true`; excluded from all records/e1RM baselines (matching Strong), shown with a "W" marker.
  - Set positions therefore come from appearance order, not `Set Order` (Strong restarts numbering around warm-ups). Net: 10,725 real sets.

## 5. Sync strategy (v1: deliberately simple)

Single device + accounts means v1 sync is **backup, not multi-device merge**:
- Every local mutation appends to an `outbox` table; a background task pushes pending rows to Supabase (upsert by UUID) whenever online.
- On fresh install/sign-in, pull everything down to rebuild the local store.
- No conflict resolution in v1 — one device writing means last-write-wins is trivially correct. Real sync (multi-device, Watch) is a post-v1 project and the UUID + outbox design is chosen so it extends rather than rewrites.

## 6. App architecture

- SwiftUI + `@Observable` view models, one per screen; no third-party architecture framework.
- A single `Database` service (GRDB) owns all persistence; view models never touch SQL directly — they call repository methods (`workoutRepo.completeSet(...)`, `statsRepo.bestE1RM(for:)`).
- Rest timer: a live activity–style local notification scheduled on set completion; timer state derives from `completed_at` timestamps so it survives app restarts.
- Feature modules mirror the PRD verticals: `Logging/`, `Templates/`, `Library/`, `History/`, `Import/`, `Sync/`.

## 7. Build order

1. **Foundation + import** — Xcode project, GRDB schema + migrations, Strong CSV parser with tests against the real export.
2. **Read-only history** — history feed and exercise detail (records, charts, set history) over imported data. Proves the data model before any writes.
3. **Logging core** — start from template, log sets with previous-session numbers, intensity ring, rest timer, finish screen with PR detection.
4. **Full logging** — mid-workout editing, supersets, in-workout exercise history, resume/timeout.
5. **Templates CRUD + streaks + body weight.**
6. **Supabase** — auth, schema, outbox push, restore-on-sign-in. Last because everything before it works fully offline.

Each phase ends with the app runnable in the simulator. Real-device gym testing starts after phase 3.
