# CHORE-TEST-COVERAGE-FLOOR — the suite runs in CI, and nobody knows what it covers

Status: 🔄 in-progress — **86.81%**, floor at **86**. Tickets 01, 02, 03 and 05 are merged ([PR #20](https://github.com/VEAF/Skynet-IADS/pull/20), [#21](https://github.com/VEAF/Skynet-IADS/pull/21), [#22](https://github.com/VEAF/Skynet-IADS/pull/22), [#23](https://github.com/VEAF/Skynet-IADS/pull/23)). Ticket 04 is blocked on `CHORE-PROFESSIONALIZE-THE-REPO` ticket 04, the legacy port — but, and this is new, **the lot is no longer hostage to it**: see the arithmetic below. Ticket 06 is next, and on the numbers it can carry the floor past 90 on its own

Origin: David, 2026-09-19 — *"on a une suite de tests unitaires en CI ? quelle est sa couverture ?
je voudrais un minimum de 80%, fais un lot vivant pour ça"*, raised to **90%** the same day once the
measurement below was on the table.

This is a **living lot**: it does not close when a number is reached once. It installs the
measurement, sets a floor that can only go up, and then stays open while the floor climbs to 90%.

## A word of warning about the word

In this repository **coverage** already means something else: an early warning radar *covers* a SAM
site when it is near enough, which decides the battery's autonomy (`CONTEXT.md`, "Covered does not
mean informed"). Three lots and half a dozen test suites use it that way.

This lot is about **test coverage** — how much of the source the suite executes. Everywhere in this
lot, and in the code and configuration it produces, the two words stay together: *test coverage*,
`checkTestCoverage`, `test-coverage.yml`. A bare `coverage` in this repository is radar coverage.

## What CI does today

`.github/workflows/lua-tests.yml` installs Lua 5.1 on `ubuntu-latest` and runs
`lua5.1 test/lua/run.lua`, on every push to `master` and `develop` and on every pull request.
`run.lua` discovers `test/lua/test_*.lua`, runs each as a child process and aggregates the exit
codes — **18 suites, all green**.

So: yes, there is a unit-test suite in CI. It measures nothing. There is no `luacov`, no report, no
threshold, and no `.luacov` anywhere in the repository. Until this lot, *"what does the suite
cover"* had never been asked in a way that produced a number.

## What the measurement says

Taken on 2026-09-19, at `4125b52`, with `luacov` under Lua 5.1 — each suite run as
`lua5.1 -lluacov test/lua/test_*.lua` so that `luacov` accumulates across the 18 child processes,
then the reporter over the merged `luacov.stats.out`. All 18 suites green during the run.

**70.22%** — 1 679 lines executed out of 2 391, over the sources the loader loads, data tables
excluded (see below).

| Source file | Hits | Missed | Test coverage |
|---|---:|---:|---:|
| `skynet-iads-logger.lua` | 35 | **310** | **10.14%** |
| `skynet-iads-abstract-radar-element.lua` | 456 | **184** | 71.25% |
| `skynet-iads.lua` | 445 | 98 | 81.95% |
| `skynet-iads-jammer.lua` | 88 | 29 | 75.21% |
| `skynet-iads-utils.lua` | 100 | 26 | 79.37% |
| `skynet-iads-harm-detection.lua` | 72 | 21 | 77.42% |
| `skynet-iads-abstract-dcs-object-wrapper.lua` | 53 | 13 | 80.30% |
| `skynet-iads-sam-launcher.lua` | 50 | 9 | 84.75% |
| `skynet-iads-sam-search-radar.lua` | 45 | 7 | 86.54% |
| `skynet-iads-contact.lua` | 90 | 5 | 94.74% |
| `skynet-iads-abstract-element.lua` | 63 | 5 | 92.65% |
| `skynet-iads-table-delegator.lua` | 7 | 4 | 63.64% |
| `skynet-mooose-a2a-dispatcher-connector.lua` | 40 | 1 | 97.56% |
| `skynet-iads-sam-site.lua` | 74 | 0 | 100% |
| `skynet-iads-early-warning-radar.lua` | 28 | 0 | 100% |
| `skynet-iads-awacs-radar.lua` | 16 | 0 | 100% |
| `skynet-iads-command-center.lua` | 10 | 0 | 100% |
| `skynet-iads-sam-tracking-radar.lua` | 7 | 0 | 100% |
| **Total** | **1 679** | **712** | **70.22%** |

Two files carry **69%** of everything the suite never runs: the logger (310) and
`skynet-iads-abstract-radar-element.lua` (184).

## What counts, and what must not

**`skynet-iads-supported-types.lua` is excluded from the denominator, and so is
`highdigitsams/skynet-iads-high-digit-sams-suported-types.lua`.** Both are pure data — nested tables
of SAM type names, radar names and NATO designations, no branch, no function. `luacov` counts every
line of a table constructor as executed the moment the file loads, so `supported-types` alone
scores 493/493 and hands the project 17 points of denominator for free. Counting it, the same run
reports **75.31%**; not counting it, **70.22%**. The lower number is the true one, and it is the one
this lot works against — a floor you can raise by loading a data file is not a floor.

(The high-digit file is not even loaded: `test/lua/skynet-loader.lua` deliberately leaves it out of
`ORDER`, so it never appears in the report at all. Adding it to the loader would add ~300 lines
scored 100% and lift the headline number without testing a thing. Its filename also carries an
upstream typo — `suported` with one `p` — which is real, is referenced by
`build-tools/listToMerge.txt`, and is **not** in the scope of this lot. The exclusion pattern has to
match it as spelled.)

Everything else counts, the logger included. Its status printers are not decoration: the
`skynet-runtime-debug` skill reads those exact lines out of a `dcs.log` to diagnose a mission. Their
shape is a contract with a real consumer, and nothing pins it today.

## What it takes to reach 90%

90% of 2 391 is 2 152. From 1 679, that is **473 more lines executed** — a fifth of the source, and
it leaves room for 239 lines to stay uncovered for good.

Cumulatively, in ticket order:

| Once this lands | Lines it buys | Test coverage |
|---|---:|---:|
| — at the start | | 70.22% |
| ✅ The logger's four status printers (ticket 03) | 303 | 83.35% |
| ✅ The network facade's getters and radio menu (ticket 05) | 84 | **86.81%** |
| The HARM / defence / point-defence block of `abstract-radar-element` (ticket 04) | 173 | ~94% |
| The long tail (ticket 06) | up to 126 | — |

The first two rows are measured, not estimated; the figures the original plan carried (310 and 98 lines, for 83.19% and 94.98%) were close on the logger and optimistic on the facade. The denominator also moved, from 2 391 to 2 411: `luacov` only knows a line exists once the stats file has seen it, so covering a file deeper reveals more of it.

**What changed, and it matters.** 90% of 2 411 is 2 170 lines, and the suite runs 2 093 — **77 short**. Of the 318 lines still never run, 173 sit in `abstract-radar-element`, the file ticket 04 needs the other lot for. The remaining **145 are everywhere else**, which is ticket 06's territory, and 77 < 145.

So the sentence below, written before 03 and 05 landed, is no longer true as stated: ticket 04 is not the gate any more. Ticket 06 alone can take the floor past 90, provided enough of those 145 lines are real. That proviso is not a formality — 19 of them are the logger's continuation lines of multi-line concatenations, which Lua 5.1 does not instrument and which no test can ever reach. Nobody has checked how many of the other 126 are the same kind, and that check is the first thing ticket 06 should do.

The original reasoning, kept because it is what the target was set against:

**90% is where the target stops being reachable by one block.** At 80% the logger alone would have
done it; at 90% tickets 03 *and* 04 both have to land, and close to completely — three quarters of
each leaves the number at 89. Which means this lot now depends on
`CHORE-PROFESSIONALIZE-THE-REPO` ticket 04, the legacy port, finishing. That is a real dependency on
another lot, not a formality, and it is the single thing most likely to hold this one open.

Ticket 06 stops being optional cleanup and becomes the margin: if 03 and 04 come up short, its 120
lines are what closes the gap.

Ticket 04 is not new work invented here: `unit-tests/test-skynet-iads-abstract-radar-element.lua`
holds 50 legacy in-sim tests, 8 of which are ported. The 42 that remain are, by
`CHORE-PROFESSIONALIZE-THE-REPO` ticket 04's own list — *"HARM timing and defence states, point
defence, the SA-2 range tests, ammo and missiles-in-flight, parent/child bookkeeping, cached targets
and aspect"* — almost exactly the functions the report shows as never executed. **That work belongs
to that lot; this one only measures what it buys.** See ticket 04 here for the cross-reference.

## Tickets

| # | Ticket | Status |
|---|---|---|
| 01 | [measure test coverage in CI, and publish the number](tickets/01-measure-test-coverage-in-ci.md) | ✅ |
| 02 | [a floor that only goes up](tickets/02-a-floor-that-only-goes-up.md) | ✅ |
| 03 | [pin the status printers the debug skill reads](tickets/03-pin-the-status-printers.md) | ✅ |
| 04 | [the HARM and defence block of the radar element](tickets/04-the-harm-and-defence-block.md) | ⬜ |
| 05 | [the network facade's getters and radio menu](tickets/05-the-network-facade.md) | ✅ |
| 06 | [the long tail](tickets/06-the-long-tail.md) | ⬜ |

01 and 02 are the mechanism and come first, in that order. 03 to 06 are the climb and can be taken
in any order — each one raises the floor by the amount it actually bought, which is the point of
the ratchet. At a 90% target none of the four is optional; 03 and 04 are the two that decide
whether the target is reached at all.

## How this lot lives

The floor starts at what is measured, not at what is wanted. A gate set to 90% today fails the
build on `develop` from the first run — twenty points short — which teaches everyone to bypass it.
So ticket 02 sets the floor at the measured value, rounded down, and every ticket that lands raises
it — the same shape as the `luacheck` ratchet already pinned in `.luacheckrc`, and for the same
reason: *it exists to erode, never to grow*.

The lot stays open, at 🔄, until the floor reads 90. It is closed by the floor, not by a ticket
count — if the legacy port carries the number past 90 on its own, the remaining tickets close as *no
longer needed*, and that is a good outcome, not a shortcut. The reverse is the one to watch: the
climb stalling at 83% with ticket 04 waiting on another lot. That is a blocked lot, and it should be
said out loud rather than left at 🔄.

## Definition of done

- CI reports a test-coverage percentage on every pull request, from the suite it already runs.
- The denominator excludes the two data tables and nothing else, and the configuration says why.
- The build fails when test coverage drops below the recorded floor.
- The floor reads **90** or better, and the number it is measured against is the honest one.
- `test/lua/README.md` says how to run the measurement locally, on Linux and on Windows.
