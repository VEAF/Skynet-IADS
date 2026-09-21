# FIX-COVERAGE-UPDATE-DARKENS-SITES — declaring that a radar covers a battery switched the battery off

Closed 2026-09-19. [PR #19](https://github.com/VEAF/Skynet-IADS/pull/19).

## The defect

`buildRadarAssociation()` records that a radar covers a battery through `addParentRadar()`, which
ends in `informChildrenOfStateChange()` and therefore `goDark()`. **Writing down a fact about
geometry switched off a radar.**

```
goDark ← resetAutonomousState ← setToCorrectAutonomousState
       ← informChildrenOfStateChange ← addParentRadar
       ← buildRadarAssociation ← buildRadarCoverageForEarlyWarningRadar ← addEarlyWarningRadar
```

Found on 2026-09-19 while instructing `FIX-STALE-HARM-SILENCE` ticket 02, by tracing which step of a
bulk re-add darkened a designated site. It was not the step under review — the site was already dark
before that code ran. In walder's original, not a regression.

## Why it was an oversight rather than a design

`FEAT-LAST-LINE-OF-DEFENSE` wrote `addParentRadarWithoutStateChange()` for exactly this, with a
comment naming the hazard — a sweep going through `addParentRadar` would *"hand an extinction order
to the whole network"* — and converted `refreshRadarCoverage()`. `buildRadarAssociation()` was
missed, and was left as the only caller of the informing version in the sources.

## What it cost

**In game.** Adding an EW radar mid-mission darkened every battery in its range, including one
designated onto an intruder and not yet locked on. `goDark()`'s guards cover a site that has acquired
a track or has missiles in flight; not that one. The symptom is the one `3a94937` is about:
launchers raised, slew onto the target, back to travel, no shot. Bounded by `contactUpdateInterval`
— 5 s — which is long enough for a fast pass to be over.

**In work.** During one `activate()` on three EW radars and ten SAM sites: **250**
`informChildrenOfStateChange()` calls where **10** are needed. `buildRadarCoverage()` already ends
with an explicit loop notifying every site once; the other 240 were N² noise generated inside it.
