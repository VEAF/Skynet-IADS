# FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET — the in-sim mission has been checking code we stopped shipping

Status: 🔄 in-progress — branch `fix/in-sim-suite-tests-a-2023-skynet`, all four tickets coded; ✅ once merged

Origin: found on 2026-09-20, closing `CHORE-PROFESSIONALIZE-THE-REPO` ticket 04. David ran
`unit-tests/skynet-unit-tests.miz` in DCS to confirm that removing six legacy suites had not broken
the archive. It had not — 118 tests, exactly the 168 it ran before minus the 50 removed, no
script-loading error. But one `ERROR SCRIPTING` line in the log put a **popup on the player's
screen**, and asking where it came from turned up the rest.

## The defect

`unit-tests/skynet-unit-tests.miz` carries its own copy of the deliverable, and that copy is:

```
SKYNET VERSION: 3.3.0-develop | BUILD TIME: 29.12.2023 2304Z
```

The `.miz` had not been touched between **2023-12-30** and 2026-09-20. So the in-sim suite has been
exercising **Skynet 3.3.0** for close to three years, while `develop` moved to 3.5.0. Everything it
has ever confirmed is about code this project no longer ships, and nothing it does can catch a
regression in code that it does.

That is the whole defect. The rest follows from it.

### It drags MiST in, and MiST puts a popup on the screen

`fe40c4a` (2026-08-30, *refactor: run without MiST*) removed MiST from Skynet and wrote
`SkynetIADSUtils` to replace it. The current sources make **zero** MiST calls. The 2023 artifact
inside the `.miz` makes **33**, so the mission still has to load `mist_4_5_107.lua`.

Loading MiST installs MiST's own world event handler. When an object dies that MiST does not have in
its alive-units table, it tries to correlate it to a static object by position and calls
`Object.getPosition` on something already gone:

```
ERROR SCRIPTING (Main): Mission script error: [string "l10n/DEFAULT/mist_4_5_107.lua"]:1350: Object doesn't exist
  [C]: in function 'getPosition'
  [string "l10n/DEFAULT/mist_4_5_107.lua"]:1350: in function 'f'
  [string "l10n/DEFAULT/mist_4_5_107.lua"]:1892: in function 'onEvent'
```

DCS shows that to the player as a popup. The two suites that blow objects up —
`test-skynet-iads.lua` (5 `trigger.action.explosion`) and
`test-skynet-iads-abstract-radar-element.lua` (6) — are the trigger.

Besides the artifact, the harness itself uses MiST five times, and every one has an equivalent that
already exists:

| used in the `.miz` | replacement, already written |
|---|---|
| `mist.utils.round` | `SkynetIADSUtils.round` |
| `mist.utils.get2DDist` | `SkynetIADSUtils.get2DDist` |
| `mist.random` | `SkynetIADSUtils.random` |
| `mist.scheduleFunction` | `SkynetIADSUtils.scheduleFunction` |
| `mist.removeFunction` | `SkynetIADSUtils.removeFunction` |

So MiST can leave the mission entirely, and the popup goes with it.

### Four assertions pin DCS data from 2023

The same run reported 114 successes and **4 failures**, all in
`test-skynet-iads-red-sam-sites-and-ew-radars.lua`, last touched 2023-12-29:

| test | asserts | DCS answers today |
|---|---|---|
| `testCheckSA11GroupNumberOfLaunchersAndSearchRadarsAndNatoName` | SA-11 launcher range 35000 | 46000 |
| `testHQ7LauncherAndRadar` | HQ-7 launcher range 12000 | 15000 |
| `testSA15LaunchersSearchRadarRangeAndHARMDefenceChance` | target height 1930 | 1929 |
| `testShilkaGroupLaunchersSearchRadarRangesAndHARMDefenceChance` | target height 1909 | 1908 |

Two missile ranges ED has changed since 2023, and two altitudes that moved by a metre. Nothing in
Skynet is wrong. These are the second kind of drift `docs/evolutions.md` predicted and could not
measure — a stale *expectation* whose spelling is still valid.

## Why it matters

The in-sim suite is the only thing in this project that can answer questions a stub cannot: what a
DCS unit reports about itself, what its radar really holds, what the terrain does. `test/lua/` was
built on exactly that division of labour, and `CHORE-PROFESSIONALIZE-THE-REPO` ticket 04 left six
suites in the `.miz` on the strength of it.

That division only works if the in-sim half runs against the code we ship. Today it does not, so the
guarantee the standalone suite was allowed to lean on is not there.

### And 125 assertions pin ED's data, not just those four

The four are what the 2026-09-20 run made visible. Counted across every in-sim suite — including
`highdigitsams/test-skynet-high-digit-sam-sites.lua`, which the first sweep left out — **125
assertions compare an ED figure to a literal**, and the next DCS patch decides which of them goes
red:

| suite | assertions before | pinning an ED figure |
|---|---|---|
| `highdigitsams/test-skynet-high-digit-sam-sites.lua` | 141 | 58 |
| `test-skynet-iads-red-sam-sites-and-ew-radars.lua` | 122 | 41 |
| `test-skynet-iads-blue-sam-sites-and-ew-radars.lua` | 46 | 19 |
| `test-skynet-iads-abstract-radar-element.lua` | 229 | 7 |
| the other three | 169 | 0 |

An earlier count here said "76 out of 297". That came from grepping for lines *mentioning* one of
these accessors across three suites, which over-counts (it catches figures the test fabricates
itself, and ranges asserted to be 0) and under-counts (it never looked at the high-digit suite).
The figures above are what ticket 03 actually removed.

## What this lot decided

**Whether Skynet's own tests should pin ED's data at all.** Three readings were written up in
`docs/evolutions.md` under *The in-sim suite drifts, and nothing says so*, all framed around running
the mission. David pointed at a fourth, 2026-09-20: VEAF-Mission-Creation-Tools already answers this
**without a simulator**, from the `Quaggles/dcs-lua-datamine` dataset at a pinned commit, with a CI
guard and a weekly robot that bumps the pin.

The datamine carries exactly these figures — `Range_max`, `H_max`, and `detection_distance` times
`0.2 ^ 0.25` — and the two figures the DCS log reported are the two it holds. So ED's data leaves the
simulator: ticket 03 builds the generator, the committed table and the standalone tests, and the
in-sim suites stop asserting figures a stub can now check.

## What the refreshed mission actually did

Run in DCS on 2026-09-20 at 09:04, against the artifact built that morning. The ticket budgeted for a
wall of red. There was none:

| | before (3.3.0) | after (3.5.0) |
|---|---|---|
| tests | 118 | **119** |
| successes | 114 | 114 |
| failures | 4 | **5** |
| `ERROR SCRIPTING` lines | 1, every run | **none** |

The extra test is `testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage`, which the sync baked in
for the first time, and it passes. The four original failures are unchanged, line for line and value
for value — they are the ED figures ticket 03 is about.

**One new failure, and it is the rename `docs/evolutions.md` already predicted**: `0ebbc01` renamed
`lastUpdatePosition` to `lastCoverageUpdatePosition`, and `test-skynet-iads.lua` still wrote the old
name — so it set a field nothing reads, `getDistanceTraveledSinceLastUpdate()` found nil, adopted the
current position and answered 0 where the test asserts 763. It had been passing only because the
mission ran the 2023 build, where the old name was still the real one. Ticket 04.

**No regression in Skynet.** Three years of source changes, and the only thing the refresh broke was
a test writing to a field that had been renamed a month earlier.

A sweep of every field the in-sim suites write, checked against what the sources define, turned up no
second case.

## How it ended

`skynet-unit-tests.miz`, assembled, in DCS on 2026-09-20 at 16:17:

```
--- SKYNET VERSION: 3.5.0 | BUILD TIME: 20.09.2026 1612Z ---
Ran 119 tests in 1.801 seconds, 119 successes, 0 failures
```

| | before the lot (3.3.0) | after |
|---|---|---|
| tests | 118 | **119** |
| failures | 4 | **0** |
| `ERROR SCRIPTING` lines | 1, every run | **none** |
| MiST mentions in the log | many | **none** |

**No regression in Skynet.** Three years of source changes separated the archive from `develop`, and
the only two tests the refresh broke were both in `testAWACSHasMovedAndThereforeRebuildAutonomous
StatesOfSAMSites`, both measuring mechanisms that had been deliberately moved — a renamed field
(ticket 04) and a rebuild path `0ebbc01` relocated on purpose.

**The leak check still checks.** Ticket 02 warned that swapping `mist.removeFunction` for
`SkynetIADSUtils.removeFunction` could leave a check that silently stops checking. It did not: the
run reports `WARNING: IADS left over Tasks` exactly once, the same as it did under MiST. The warning
itself predates this lot and is nobody's business here.

## Tickets

| # | Title | Status |
|---|-------|--------|
| 01 | [Refresh the deliverable the mission carries](tickets/01-refresh-the-embedded-deliverable.md) | ✅ |
| 02 | [Take MiST out of the mission](tickets/02-take-mist-out-of-the-mission.md) | ✅ |
| 03 | [Take ED's figures out of DCS, and check them against the datamine](tickets/03-decide-about-the-dcs-figures.md) | ✅ |
| 04 | [Fix the renamed field the refresh exposed](tickets/04-fix-the-renamed-coverage-field.md) | ✅ |
| 05 | [Assemble the mission instead of committing a copy of the code](tickets/05-assemble-the-mission-instead-of-committing-it.md) | ✅ |

Order matters between 01 and 02: MiST cannot leave while the artifact in the mission still calls it.
03 needs 01 first — measuring ED's figures against the 2023 build would measure the wrong thing twice.

## Watch out for

**The missions are assembled now, not committed complete** (ticket 05). To run one in DCS:
`pwsh -File build-tools/build-compiled-script.ps1`, then `python build-tools/miz-suite.py build`,
then copy `build/missions/<name>.miz` into the DCS `Missions` folder. Opening the archive from
`unit-tests/` directly gives a placeholder message instead.

**`highdigitsams-unit-tests.miz` cannot be run here.** It needs the HighDigitSAMs mod, which David
does not have — DCS refuses to load the mission. Its artifact is refreshed and CI checks its wiring
and parses its scripts, which is strictly more than the nothing it had before, but nobody can say it
runs. Recorded rather than worked around.

**Every ticket here is judged in DCS.** `CLAUDE.md` says to stop and wait for explicit approval when
that is the case, and it applies to all three. CI can check the archive is well-formed —
`build-tools/miz-suite.py check` and the *In-sim mission archive* job do that since 2026-09-20 — but
nothing in CI can run the mission.

**Ticket 01 is the unpredictable one.** The suite has never run against 3.5.0. Three years of source
changes are between the two, so refreshing the artifact may turn a large number of those 118 tests
red at once, and each one then has to be read: a real regression, an API that moved, or an
expectation that was always about 3.3.0. Budget for that rather than for a file swap.
