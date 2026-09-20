# 03 — Take ED's figures out of DCS, and check them against the datamine

Status: ⬜ ready — decided 2026-09-20, see *The decision* below

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

### What is not established

**The unit-to-missile link.** It goes through `WS[].LN[].PL[].type_ammunition`, which is empty on the
SA-11 TEL, so there is a level of indirection left to understand. That is the one thing that decides
whether a generator is straightforward or painful — settle it before writing the generator, and say
so here if it turns out the datamine cannot answer it.

**The breadth.** Three missiles and two radars is what the correspondence rests on. Skynet models
around forty types. A sample that holds on five is a reason to build, not a proof that it holds on
forty.

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
- A committed table of ED's figures exists, generated from a pinned datamine ref, with the ref
  recorded in it.
- `test/lua/` checks Skynet's accessors against that table, and CI runs it.
- CI fails if the committed table and the pin disagree.
- The in-sim suites no longer assert ED's figures, and what is left there is what needs a simulator.
