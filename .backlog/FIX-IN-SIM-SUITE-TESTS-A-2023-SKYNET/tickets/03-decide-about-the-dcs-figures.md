# 03 — Decide whether Skynet's tests should pin ED's data at all

Status: ⬜ ready — **needs David's decision before any code**

Four tests failed on the 2026-09-20 run, all in `test-skynet-iads-red-sam-sites-and-ew-radars.lua`,
last touched 2023-12-29:

| test | asserts | DCS answers today |
|---|---|---|
| `testCheckSA11GroupNumberOfLaunchersAndSearchRadarsAndNatoName` | SA-11 launcher range 35000 | 46000 |
| `testHQ7LauncherAndRadar` | HQ-7 launcher range 12000 | 15000 |
| `testSA15LaunchersSearchRadarRangeAndHARMDefenceChance` | target height 1930 | 1929 |
| `testShilkaGroupLaunchersSearchRadarRangesAndHARMDefenceChance` | target height 1908 | 1909 |

Two missile ranges ED has changed, and two altitudes that moved by a metre. Nothing in Skynet is
wrong.

The two altitude assertions are a metre of terrain and are worth nothing whichever way this goes.
The question is about the two ranges.

## The decision

Three readings, and they lead to different work. None is obviously right.

**a. It is a canary, and it just worked.** Nothing else in this project would have told anyone that
the Buk's reach grew by 11 km — a change that moves when a battery wakes, in every mission that uses
one. The cost is a suite that sits red until somebody re-runs it and re-pins the numbers.
*Work:* update the two figures, and say in the file what they are for and that going red is expected
after a DCS patch.

**b. It is noise.** A suite that goes red because ED shipped a patch is a suite people learn to
ignore, and that is how this drift lasted three years. Skynet's job is to decide *with* whatever
range DCS reports, not to have an opinion about the number.
*Work:* delete the range assertions, keep the ones about Skynet's own behaviour.

**c. It is the wrong shape.** What is worth knowing is *that a figure moved*, not that it equals a
literal. A step that records what DCS currently reports for each modelled type and reports the delta
against what was recorded last time says the same thing as (a) and never fails for a reason nobody
caused.
*Work:* a new in-sim script that dumps the figures, and a recorded baseline. More than the other
two, and it replaces rather than repairs.

Recommendation: **(c) if this suite is going to be maintained, (b) if it is not.** (a) only holds if
somebody is actually going to re-run the mission after DCS patches, and three years of evidence say
nobody does.

The same question is written up in `docs/evolutions.md` under *The in-sim suite drifts, and nothing
says so*, which this measurement answers.

## Watch out for

**Ticket 01 comes first, whichever option wins.** Refreshing the artifact may change what these tests
report, so re-pinning figures before that is measuring the wrong build twice.

**Do not take the numbers from the log as the new truth without a second look.** They came from one
install, one theatre and one DCS version. `CLAUDE.md` says to verify DCS behaviour against the
[dcs-lua-datamine dataset](https://github.com/Quaggles/dcs-lua-datamine) or a real log — the log is a
real log, but a single sample, and the two altitudes show how little a one-metre difference means.

## Definition of done

- David has chosen a, b or c, and the reason is written here.
- The four tests reflect that choice.
- If (a) or (c): the file says what the figures are for, so the next person to see them go red knows
  whether they have found a bug or a patch.
