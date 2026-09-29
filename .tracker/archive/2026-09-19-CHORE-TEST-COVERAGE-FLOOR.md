# CHORE-TEST-COVERAGE-FLOOR — the suite ran in CI, and nobody knew what it covered

Closed 2026-09-19. PRs [#20](https://github.com/VEAF/Skynet-IADS/pull/20),
[#21](https://github.com/VEAF/Skynet-IADS/pull/21), [#22](https://github.com/VEAF/Skynet-IADS/pull/22),
[#23](https://github.com/VEAF/Skynet-IADS/pull/23), [#24](https://github.com/VEAF/Skynet-IADS/pull/24).

Origin: David, 2026-09-19 — *"on a une suite de tests unitaires en CI ? quelle est sa couverture ?
je voudrais un minimum de 80%"* — raised to 90% the same day once the measurement was on the table.

A **living lot**: it installed the measurement, set a floor that only goes up, and stayed open while
the floor climbed.

## The climb

**70.22% → 91.17%**, floor **70 → 91**, CI failing below it on every pull request.

| ticket | what it covered | project |
|---|---|---|
| 01–02 | `luacov`, the report, the ratchet | 70.22% |
| 03 | the logger's status printers, 10.14% → 94.68% | 83.35% |
| 05 | the network facade a mission maker writes against, 81.95% → 98.19% | 86.81% |
| 06 | the long tail — jammer, launcher, contact, delegator, abstract element, MOOSE connector all to 100% | **91.17%** |

Ticket 04 closed ⚪ **no longer needed for this lot**: the floor passed 90 without it, which the plan
had called a good outcome rather than a shortcut. The legacy port it would have measured was still
worth doing on its own terms, as `CHORE-PROFESSIONALIZE-THE-REPO` ticket 04.

## The decision that makes the number honest

**The pure data tables are out of the denominator** — `skynet-iads-supported-types.lua` and the
high-digit equivalent. `luacov` counts every line of a table constructor as executed the moment the
file loads, so `supported-types` alone scores 493/493 and hands the project 17 free points. Counting
it: 75.31%. Not counting it: 70.22%. **A floor you can raise by loading a data file is not a floor.**

Everything else counts, the logger included: its status printers are read out of a `dcs.log` by the
`skynet-runtime-debug` skill, so their shape is a contract with a real consumer.

## A word this repository already owns

**Coverage** here means an EW radar covering a SAM site. This lot is about **test coverage**, and the
two words stay together everywhere it touched: `checkTestCoverage`, `test-coverage-floor.txt`. A bare
*coverage* in this repository is radar coverage.

## What it found on the way

Four latent defects, recorded at the end of tickets 05 and 06 rather than fixed there, and taken up
by `FIX-SETUP-WARNINGS-AND-LOG-NOISE` and `FIX-JAMMER-SILENCE-OUTLIVES-THE-JAMMER`. What stays
uncovered, and why, is written in `test/lua/README.md`.
