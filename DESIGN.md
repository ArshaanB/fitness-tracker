# Fitness Tracker — Design Direction

**Status:** In progress · **Companions:** [PRD.md](PRD.md), [TECH_DESIGN.md](TECH_DESIGN.md)

## Direction (agreed 2026-08-08)

- **Mood:** light and clean — bright, airy, Apple-Fitness-adjacent. Color used sparingly for data.
- **Accent:** electric blue `#0A5CFF` for actions, links, and structure (elapsed chip, progress bar).
- **In-workout density:** hybrid — a compact overview list of the session's exercises, with the active exercise's card expanded into large entry controls.
- **PR moment:** subtle class — the ring quietly becomes an animated rainbow; the finish screen does the real celebrating with a single shimmer, no confetti.
- **Type:** iOS system stack (SF Pro). Big tabular numerals for anything numeric.

## Tokens (v1)

| Token | Value | Use |
|---|---|---|
| ground | `#EBF1F9 → #F5F7FB` (vertical gradient) | App background — blue-tinted so white cards read warm, not stale |
| card | `#FFFFFF` | Cards, sheets — elevated with soft shadow, no border |
| ink | `#0E1726` | Primary text |
| ink-secondary | `#6B7688` | Metadata, previous-set column |
| input-fill | `#EAEFF7` | Weight/reps entry fields |
| accent | `#0A5CFF` | Buttons, links, superset rail |
| ring-low | `#FF453A` | Ring < 70% of best e1RM |
| ring-mid | `#FFB020` | Ring 70–90% |
| ring-high | `#2DBE5F` | Ring 90–100%; also completed-set green |
| ring-pr | rainbow conic | Ring ≥ 100% — animated (respects reduced motion) |

## Signature element: the intensity ring

A 26px donut next to every set that fills and colors by `projected e1RM ÷ best-ever e1RM` (Epley). It is the app's identity — the rest of the UI stays quiet (white cards, one accent) so the rings are the only charged color on screen. The rainbow state is the sole place the palette goes loud.

## Mockups

Interactive HTML mockups live in `design/mockups/`. Each is a self-contained page with the working ring math (Epley in JS), viewable in any browser. They are the visual spec the SwiftUI implementation follows.

| # | Screen | File | Status |
|---|---|---|---|
| 01 | Workout logging (+ rest timer, finish sheet) | [design/mockups/01-logging.html](design/mockups/01-logging.html) | Rev 2 — feedback applied (no supersets, no × in previous column, wider check, ±10s rest adjust, warmer ground) |
| 02 | History feed | — | Not started |
| 03 | Exercise detail (records, charts, history) | — | Not started |
| 04 | Templates list + editor | — | Not started |
| 05 | Streaks + body weight | — | Not started |

## Review workflow

1. Mockup built in HTML → published as a private artifact link for review (tap through on phone or desktop).
2. Feedback applied to the mockup file → artifact redeployed to the same URL.
3. Approved mockup becomes the spec for the SwiftUI build; deviations get noted back here.
