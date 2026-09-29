# FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET — the in-sim mission was checking code we stopped shipping

Closed 2026-09-20, five tickets. [PR #32](https://github.com/VEAF/Skynet-IADS/pull/32).

Found while closing `CHORE-PROFESSIONALIZE-THE-REPO` ticket 04: David ran the in-sim suite to confirm
that removing six legacy suites had not broken the archive. It had not — but one `ERROR SCRIPTING`
line put a **popup on the player's screen**, and asking where it came from turned up the rest.

## The defect

`unit-tests/skynet-unit-tests.miz` carried its own copy of the deliverable:
`SKYNET VERSION: 3.3.0-develop | BUILD TIME: 29.12.2023 2304Z`. The archive had not been touched
between **2023-12-30 and 2026-09-20** while `develop` moved to 3.5.0. So three years of in-sim runs
measured code this project had stopped shipping, and nothing they did could catch a regression in
code that it does.

**MiST came with it.** `fe40c4a` took MiST out of Skynet on 2026-08-30; the current sources make zero
MiST calls, the 2023 artifact makes 33. So the mission still loaded MiST, MiST installed its own
event handler, and a `DEAD` event for an object it did not know called `getPosition` on something
already gone — the popup. The harness's own five MiST calls each already had a `SkynetIADSUtils`
equivalent, so MiST left the mission entirely.

## The two decisions

**ED's figures leave the mission.** 125 assertions pinning a missile's reach, a firing ceiling, a
radar's detection distance or an initial ammunition count moved to `test/lua/dcs-figures.lua`,
generated from a pinned datamine commit, with a weekly workflow that opens a pull request when one
moves. A change then arrives as a diff naming the figure, not as a red test nobody sees for three
years. What stays in a `.miz` is what a stub cannot answer.

**Missions are assembled, not committed** (David's idea, ticket 05). The archives hold placeholders;
`python build-tools/miz-suite.py build` puts the real files in. An assembled mission cannot go stale,
and one opened unbuilt says so on screen.

## Measured in DCS, 2026-09-20 at 16:17

**119 tests, 0 failures**, no `ERROR SCRIPTING` line, no MiST anywhere in the log — and no regression
in Skynet across the three years the suite had been blind.

One new failure was found and it was the rename `docs/evolutions.md` had predicted and could not
prove: `0ebbc01` renamed `lastUpdatePosition` to `lastCoverageUpdatePosition`, the in-sim test kept
writing the old name, so it set a field nothing reads and the assertion answered 0 where 763 was
expected. It had stayed green because the mission ran the 2023 build, where the old name was real.
Refreshing the artifact proved it in one log line.
