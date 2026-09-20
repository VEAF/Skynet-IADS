# 03 — Take ED's figures out of DCS, and check them against the datamine

Status: ✅ done — 2026-09-20, bar the DCS pass; decision in *The decision* below

Four tests failed on the 2026-09-20 run, all in `test-skynet-iads-red-sam-sites-and-ew-radars.lua`,
last touched 2023-12-29:

| test | asserts | DCS answers today |
|---|---|---|
| `testCheckSA11GroupNumberOfLaunchersAndSearchRadarsAndNatoName` | SA-11 launcher range 35000 | 46000 |
| `testHQ7LauncherAndRadar` | HQ-7 launcher range 12000 | 15000 |
| `testSA15LaunchersSearchRadarRangeAndHARMDefenceChance` | target height 1930 | 1929 |
| `testShilkaGroupLaunchersSearchRadarRangesAndHARMDefenceChance` | target height 1909 | 1908 |

Two missile ranges ED has changed, and two altitudes that moved by a metre. Nothing in Skynet is
wrong.

**The four are only what is visible today.** Across the three in-sim suites that interrogate DCS
units, **76 assertions out of 297** pin a figure that belongs to ED, not to Skynet:

| suite | assertions | of which ED data |
|---|---|---|
| `test-skynet-iads-red-sam-sites-and-ew-radars.lua` | 122 | 42 |
| `test-skynet-iads-blue-sam-sites-and-ew-radars.lua` | 46 | 19 |
| `test-skynet-iads-abstract-radar-element.lua` | 229 | 15 |
| the other three | 169 | 0 |

So the question is about 76 assertions, and the next DCS patch decides which of them goes red.

## The decision

**David, 2026-09-20: build the bridge to the datamine, in this lot.**

The three readings originally written here — re-pin the figures, delete them, or record and diff
them — were all framed around running the mission. David pointed at a fourth:
[VEAF-Mission-Creation-Tools](https://github.com/VEAF/VEAF-Mission-Creation-Tools) already answers
this question **without a simulator**. `veaf_build/dcs_data/` sparse-clones
[`Quaggles/dcs-lua-datamine`](https://github.com/Quaggles/dcs-lua-datamine) at a pinned commit,
generates a committed artifact from it, and a per-pull-request CI guard regenerates against the pin
and fails on any diff. A weekly workflow bumps the pin and opens a pull request when upstream moves.

That is the third reading (record the figures and report the delta) with the part nobody wanted to
maintain already solved: the recording is a file in the repository, the delta is a red CI job, and
the refresh is a robot's pull request.

### The correspondence is measured, not assumed

Checked at the pin VMCT uses (`fe1d800`, DCS 2.9.29.27278):

| what Skynet reads | where it lives in the datamine | samples |
|---|---|---|
| `SkynetIADSSAMLauncher:getRange()` | `_G/rockets/<missile>.Range_max` | SA-11 **46000**, HQ-7 **15000**, SA-15 12000 |
| `SkynetIADSSAMLauncher:getMaximumFiringAltitude()` | `_G/rockets/<missile>.H_max` | SA-11 22000, SA-15 6000 |
| `getMaxRangeFindingTarget()` | `_G/db/Sensors/Sensor/<radar>.detection_distance` × 0.66874 | SA-11 SR 66874.03125, Shilka 5015.552734375 |

The two figures the DCS log reported on 2026-09-20 — 46000 and 15000 — are exactly what the datamine
holds. The radar coefficient is `0.2 ^ 0.25`: detection range goes as the fourth root of the target's
radar cross-section, and 0.2 m² is the reference target the DCS API reports against. Both samples
match to the eighth decimal.

The unit-to-sensor link is direct: `_G/db/Units/Cars/Car/*.lua` carries
`Sensors = { RADAR = { "SA-11 Buk TR" } }`.

A correction to the line above, measured after it was written: the radar relation lands **bit for
bit on both samples, but only in single precision**. Rounding `0.2 ^ 0.25` to a 32-bit float and
multiplying in 32-bit reproduces both figures exactly; in double precision the SA-11 still lands and
the Shilka misses by 4.5e-4, one unit in the last place of a 32-bit float at that magnitude. The
earlier claim that both matched "to the eighth decimal" was checked by eye and was wrong for the
Shilka. Lua is double precision, so `test/lua/test_dcs_figures.lua` asserts a relative tolerance.

### Settled: the unit-to-missile link does not exist in the dump

The ticket asked for this to be settled before writing the generator, and to be written up here if
the datamine could not answer it. **It cannot.** The link lives in `WS[].LN[].PL[].type_ammunition`,
and Quaggles' exporter prunes it: empty on 50 of the 61 ground units that carry one, `"Redacted"` on
the rest. Measured 2026-09-20 across the whole `_G/db/Units/Cars` subtree, not inferred from the
SA-11 alone.

Two consequences, and neither costs the point of the ticket:

- **Radars are recorded by unit**, because that walk is real on both hops: `samTypesDB` names the DCS
  type, `_G/db/Units/**/<type>.lua` names its sensor, `_G/db/Sensors/Sensor/<sensor>.lua` states the
  distance. 34 of the 36 types `samTypesDB` lists resolve; the two that do not are `Strela-1 9P31`
  and `Strela-10M3`, which carry no radar at all — they are infrared — and are correct to be absent.
- **Missiles are recorded by missile**, unfiltered. The display name carries the connection a human
  needs: the entry that moved from 35000 to 46000 is `9M38M1 Buk-M1 (SA-11 Gadfly)`. Filtering to the
  surface-to-air ones would mean guessing from the `_file` path of an ED source file, and a filter
  that misses a SAM costs more than a few hundred lines nobody reads.

So point 2 of *What to build* — standalone tests comparing Skynet's accessors to the table — is not
what shipped for launchers, and could not be. What `test/lua/test_dcs_figures.lua` does instead is
guard the **generator**, which is where the real risk was: a regex-based generator fails quietly, by
writing a well-formed empty file or a plausible half-full one. Reading the real `samTypesDB` from the
Lua side is what caught a non-greedy regex that read only the first entry of each block and had
silently dropped two radars.

## What to build

1. **A generator**, modelled on `veaf_build/dcs_data/`: sparse-clone the datamine at a pinned ref,
   read the types Skynet models, emit a committed Lua table of the figures — launcher range, firing
   altitude, radar detection range, per unit type.
2. **Standalone tests in `test/lua/`** that compare Skynet's own accessors against that table, using
   the DCS stub. These run in CI, on every pull request, with no simulator.
3. **A CI guard** that regenerates against the pin and fails on a diff, so the committed table cannot
   drift from the ref it claims to come from.
4. **The ED-data assertions leave the in-sim suites.** What stays in the `.miz` is what a stub cannot
   answer: terrain elevation, real detection geometry, in-game events. A figure ED publishes in a
   file is not one of those.

## Watch out for

**Ticket 01 comes first.** Refreshing the artifact may change what these tests report, so measuring
against the 2023 build would be measuring the wrong thing twice.

**A pinned ref is a claim about a DCS version, and missions do not all run that version.** The
generator records what the pin says; it does not promise the player's install agrees. Say so in the
generated file.

**Do not take the 2026-09-20 log as truth on its own.** It is one install, one theatre, one DCS
version. It agrees with the datamine on the two figures it reported, which is what makes the datamine
usable — not the other way round.

## Definition of done

- The unit-to-missile link is either understood, or written up here as the reason the scope shrank.
  ✅ written up above: the dump prunes it, and the shape changed rather than shrank.
- A committed table of ED's figures exists, generated from a pinned datamine ref, with the ref
  recorded in it. ✅ `test/lua/dcs-figures.lua`, 34 radars and 234 missiles at `fe1d8008e6e8`.
- `test/lua/` checks Skynet's accessors against that table, and CI runs it. ✅ with the change of
  target explained above — `test_dcs_figures.lua` guards the generator and anchors the figures
  against what a real DCS run reported, and CI runs it with the rest of the suite.
- CI fails if the committed table and the pin disagree. ✅ `dcs-figures.py check`, in the *Lua unit
  tests* job.
- The in-sim suites no longer assert ED's figures, and what is left there is what needs a simulator.
  ✅ 125 assertions removed, each one reading a real DCS unit. Kept on purpose: 16 whose figures the
  test fabricates through a mocked `getDCSRepresentation()`, and 13 asserting a range of 0 — Skynet
  coping with the S-300, which DCS ships with empty sensor data.
- ⬜ **Pending the next DCS pass.** Removing assertions cannot turn a test red in CI, because nothing
  in CI runs this mission. The run is what proves no test lost the local it needed.

## The weekly watch

`.github/workflows/dcs-data-drift.yml`, Mondays 06:20 UTC. It reads upstream's HEAD, bumps the pin,
regenerates, and opens a pull request when a figure moved. The branch name carries the commit, on
purpose: a fixed branch name that survives a merge makes the push a no-op, no pull request is opened,
and the workflow goes quiet in a way indistinguishable from "nothing changed" — which silenced the
same robot in VEAF-Mission-Creation-Tools for three weeks in July 2026.

The pin is moved by `dcs-figures.py bump`, not by a `sed` in the workflow, because a textual
replacement that matches nothing exits zero: the pin would stay put while every later step reported
success.
