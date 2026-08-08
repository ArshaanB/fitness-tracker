# Fitness Tracker — Product Requirements Document

**Status:** Draft v1 · **Owner:** Arshaan · **Last updated:** 2026-08-08

## 1. Vision

A workout tracking iOS app that starts at feature parity with the parts of the Strong app actually used day-to-day, then grows into a more personal, opinionated training tool. Built for one user first, but with product-quality ambitions — decisions should not preclude shipping this publicly later.

The signature differentiator from day one: **the intensity ring** — instant, glanceable feedback on how hard a set is relative to your all-time best, turning every logged set into a small moment of feedback.

## 2. Goals

1. Replace Strong entirely for the owner's own training within v1.
2. Preserve years of training history via Strong CSV import, so records and charts are meaningful from day one.
3. Make in-gym logging fast, glanceable, and motivating — the app is used mid-set with sweaty hands and limited attention.
4. Lay a foundation (own backend, accounts) that supports an eventual public product.

## 3. Non-goals (v1)

- Apple Watch or iPad apps (iPhone only).
- Apple Health integration (read or write).
- Data export (import matters now; export comes later).
- Custom exercise creation UI (deferred; library is seeded from import).
- kg support (lbs only; store weights in a unit-agnostic way so kg can come later).
- Social features, sharing, community.
- Built-in exercise media/instructional content.
- Body measurements beyond body weight.
- Cardio and timed/duration exercises (strength logging only: weighted, bodyweight, and machine/cable exercises).

## 4. Target user

Initially: the owner — an experienced lifter who trains from a small set of repeatable templates, cares about progressive overload against personal records, and wants zero friction while logging. Later: lifters like them.

## 5. Product scope — v1 verticals

### 5.1 Workout logging (the core)

The live in-gym experience. Everything else in the app exists to serve this screen.

**Starting a workout**
- Workouts almost always start from a saved template.
- Starting a template pre-loads its exercises and sets, each showing the corresponding numbers from the last session with that template/exercise as the target to beat.

**Logging a set**
- Core entry is weight × reps, with the previous session's performance visible inline.
- **Intensity ring (signature feature):** as a weight is entered, an indicator circle next to the set fills with a color reflecting proximity to the personal record for that exercise:
  - **Red** — far below your max.
  - **Yellow** — solid working weight, not pushing bounds.
  - **Green** — approaching your PR.
  - **Rainbow** — PR-breaking territory.
- The ring's baseline is **best-ever estimated 1RM** for the exercise, so 5×225 can score higher than 1×245. A set whose estimated 1RM exceeds the historical best earns the rainbow state.
- Supported exercise types: barbell/dumbbell (weight × reps), machine/cable (weight × reps), and bodyweight (reps, with optional added weight).
- Units: lbs only in v1.

**Rest timer**
- Checking off a set auto-starts a rest timer using the per-exercise rest duration configured in the template.
- Notifies when rest is up (app foregrounded or not).

**Mid-workout flexibility**
- Full editing during a session: add/remove/swap exercises, reorder, add/delete sets. The template is a starting point, not a contract.
- **Supersets:** exercises can be grouped and alternated back-to-back, with the logger and rest timer aware of the grouping.
- **In-workout exercise history:** tapping an exercise opens its past performance, records, and charts without leaving the session.

**Interruptions**
- An in-progress workout survives app closure and phone locks; reopening the app resumes it in place.
- If a workout sits idle for many hours, the app offers to auto-finish or discard it rather than leaving a zombie session.

**Finishing**
- A finish screen summarizes the session: duration, total volume, and any records set (best weight, best estimated 1RM, rep PRs) — with a celebratory moment when PRs land.

### 5.2 Routines & templates

- A **flat list** of templates (e.g. Push, Pull, Legs) — no folders, programs, or scheduling in v1.
- A template stores: an ordered list of exercises (with superset groupings), set structure, and **per-exercise rest durations** that drive the auto-timer.
- Templates are not the source of target numbers: the numbers shown during a workout are simply **whatever was done last session** (auto-carry). Templates themselves change only through deliberate edits.
- Templates can be created, edited, duplicated, and deleted.

### 5.3 Exercise library

- The library is **seeded from the Strong CSV import** — every exercise in the user's history becomes a library entry. No large built-in catalog in v1.
- Custom exercise creation is deferred (the imported set covers current training).
- **Exercise detail page** — the analytical heart of the app for a single movement:
  - **Records:** best weight, best estimated 1RM, best set, rep records — the same numbers that power the intensity ring.
  - **Progress charts:** heaviest weight, estimated 1RM, and volume over time.
  - **Full set history:** chronological list of every past session's sets.

### 5.4 History & progress

- **Chronological feed** of past workouts, newest first: cards showing date, template name, duration, total volume, and PR badges. No calendar view in v1.
- **Training frequency/streaks** view: workouts per week and consistency over time. This is the only aggregate dashboard in v1 — per-exercise charts carry the rest of the analytical load.
- **Past workouts are fully editable:** fix typos, add forgotten sets, adjust dates. Records and intensity-ring baselines recompute after edits.
- **Body weight tracking:** simple weight log with a chart. No other body measurements.

### 5.5 Data & platform

- **iPhone-only** native iOS app.
- **Own backend with user accounts from day one**, anticipating a public product. The in-gym experience must still tolerate poor/no connectivity — logging can never block on the network.
- **Strong CSV import** is a v1 requirement: it seeds the exercise library, full workout history, records, and chart data.
- Export, Apple Health, and multi-device are explicitly post-v1.

## 6. Post-v1 direction (not committed)

Ideas raised but intentionally out of scope, listed so v1 doesn't preclude them:

- Custom exercise creation and richer library metadata.
- CSV export.
- Apple Health integration.
- kg support.
- Calendar view of history; richer aggregate analytics (volume trends, PR timeline).
- Full body measurements.
- Apple Watch app.
- Personal features to be defined (see open questions).

## 7. Open questions

1. **Post-v1 personal features** — the owner has ideas beyond Strong parity (AI coaching? deeper analytics? social? Watch?) that haven't been specified yet. These should be captured before major architectural bets beyond the backend/accounts decision.
2. **Estimated 1RM formula** — which formula (Epley, Brzycki, etc.) and how bodyweight exercises factor into the intensity ring.
3. **Intensity ring thresholds** — the exact e1RM percentage cutoffs for red/yellow/green/rainbow.
4. **Auto-timeout window** — how many idle hours before an in-progress workout prompts to finish/discard.
5. **Backend scope for v1** — accounts exist from day one, but how much lives server-side vs. on-device at launch (sync model, offline strategy) is a design decision for the technical spec.

## 8. Success criteria

- The owner logs 100% of workouts in this app instead of Strong, with no logging moment slower than Strong.
- Imported Strong history renders correctly: records, charts, and intensity-ring baselines reflect years of real data on first launch.
- The intensity ring feels accurate and motivating in real training — the rainbow state coincides with genuine PRs.
