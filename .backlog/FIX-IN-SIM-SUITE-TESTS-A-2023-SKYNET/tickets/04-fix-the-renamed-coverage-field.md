# 04 — The one thing the refresh broke: a field renamed a month earlier

Status: ✅ done — 2026-09-20, green in DCS at 16:17

Refreshing the artifact (ticket 01) turned exactly one test red that had been green:

```
[string "l10n/DEFAULT/test-skynet-iads.lua"]:165: expected: 763, actual: 0
```

`testAWACSHasMovedAndThereforeRebuildAutonomousStatesOfSAMSites` wrote
`awacs.lastUpdatePosition`, and `0ebbc01` (2026-08-23, *a dark site wakes on close proximity, and
coverage follows what moves*) renamed that field to `lastCoverageUpdatePosition`. So the test set a
field nothing reads; `getDistanceTraveledSinceLastUpdate()` found `lastCoverageUpdatePosition` nil,
adopted the current position and answered 0, where the test asserts 763 — the distance in nautical
miles between the two AWACS the mission places.

It had been passing for a month only because the mission ran the December 2023 build, where
`lastUpdatePosition` was still the real name. This is the exact case `docs/evolutions.md` recorded on
2026-09-19 as *one confirmed case* and could not prove, because nothing ran the mission.

## Why it is fixed here rather than recorded

Ticket 01 says not to fix what turns red, and the reason is sound: a pile of blind fixes to a suite
nobody has read in three years is how the drift started. That reasoning does not reach this one.
There is a single red test, its cause is a rename that `git log` names, and the remedy is two
identifiers. Leaving it open would re-create the drift the lot exists to end.

## What was done

`unit-tests/test-skynet-iads.lua`: `lastUpdatePosition` → `lastCoverageUpdatePosition` at lines 163
and 174, and the comment at 172 that still taught the old name.

A sweep of every `<object>.<field> =` written by the in-sim suites, checked against the fields
`skynet-iads-source/` defines, found **no second case** — the other candidates are debug-settings keys
and tables local to the tests. That sweep is the cheap lint step `docs/evolutions.md` proposed; it was
run by hand here rather than wired into CI, because one run of it found one thing and the standing
guard that matters (`miz-suite.py check`) now covers the drift that let it hide.

## And a second thing in the same test, found by the next run

The 2026-09-20 16:14 run took the failures from 5 to **1**, and the one left was the same test, four
lines further down: `test-skynet-iads.lua:176: expected: 1, actual: 0`. The 763 held, so the rename
was right; what failed was the last part, which counted calls to
`buildRadarCoverageForEarlyWarningRadar` to prove that a moved AWACS triggers a coverage rebuild.

**Not a regression.** `0ebbc01` moved that on purpose, and says so where the code used to be:

> an element that has moved is picked up by `SkynetIADS:refreshRadarCoverage()`. It used to be
> handled here, for AWACS only, by `buildRadarCoverageForEarlyWarningRadar` — which only ever adds,
> so an AWACS in transit accumulated every battery it had ever flown near

So the test was counting a function that is no longer on that path. The behaviour it meant to check
is covered standalone by `test/lua/test_skynet_iads_coverage_refresh.lua`, whose own header records
that the old check "tested the AWACS class rather than the fact of moving". The counter and its two
assertions are gone, with that reason written where they were; what stays is the part that needs the
simulator — the distance between two real DCS units.

## Definition of done

- The field is spelled the way the sources spell it, in both copies. ✅ and the 763 was observed
  passing on 2026-09-20 at 16:14.
- ✅ Observed green: 2026-09-20 16:17, **119 tests, 119 successes, 0 failures**.
