# FEAT-IN-SIM-SMOKE-TESTS — a release can be flown before it is numbered

Closed 2026-09-21. [PR #35](https://github.com/VEAF/Skynet-IADS/pull/35).

Answers the *Smoke tests* entry `docs/evolutions.md` had carried since the repository was
professionalised, and took the entry with it. Reopened by David before cutting the first release.

## The gap it closes

The standalone suite covers 94.63% of the source and cannot prove that the artifact loads in the real
engine, that the simulator ever **calls** a mechanism, or that the mission somebody downloads still
demonstrates what it claims. Every defect found by flying in September 2026 sat in that gap and went
red nowhere: a 2023 artifact in the in-sim suites, Skynet 3.2 in three demos, MiST putting a popup on
screen, and both Persian Gulf demos destroying their jammer since 2020.

## What was built

`build-tools/run-smoke.py` — stdlib only — sends Lua into a running DCS through `dcs-serve`'s
`POST /api/exec`, reads one word per check, prints a table and returns an exit code. Seven checks
over two missions. `unit-tests/README.md` is the door.

Built after reading how `CTLD_Next` and `VMCT` already do this rather than inventing it: CTLD's
**tiers** (a fast sweep must not sit behind an aircraft), VMCT's **checks as data**, and from both the
**one-word verdict**. Neither runs DCS in CI and neither can, so this is a **consultative** local step
in the `release` skill, before the version is bumped — David's call.

## Three reply shapes, two of which lie

| what happened | how it arrives |
|---|---|
| the Lua raised | **HTTP 200** with an `error` field — the status code alone calls it an answer |
| the Lua returned `false` | `""`, indistinguishable from nil, a crash, and success |
| DCS not connected | 503 — a **skip**, not a failure |

The second is `handleExec`'s `tostring(result ~= nil and result or "")`, the classic Lua `and/or`
pitfall, verified in the bridge's source and already reported upstream as
[VEAF/VEAF-dcs-bridge#35](https://github.com/VEAF/VEAF-dcs-bridge/issues/35) with all four cases
measured live — so nothing was filed from here. Hence the house rule, enforced rather than
remembered: **a check returns a word**, and the tests sweep every expectation against `""`.

## `miz-suite.py build --with-bridge`

Added mid-lot, when David asked whether the mission had what the bridge needs. It did not: only
`last-line-of-defence` carried `dcs-bridge.lua`, so the five demo checks were unreachable. The
injection is the inverse of `remove` across the same four wiring places, **opt-in and confined to the
git-ignored build** — the demos are release assets and must not ship a socket.

## Measured in DCS, 2026-09-21 — 7/7

`3.5.0`, `sam:13 ewr:8` (pinned to what was counted, not guessed), `all-found`, `alive`, `nil`, and
both flown runs `PASS`. Run 1 lit at 5.83 km inside a 12.7 km radius with `targetsInRange=false` and
`AUTONOMOUS=false`, and went quiet again — 42 ticks lit against 63 dark. Run 2 ended with the AWACS at
214.7 km for a 204.5 km range, the battery at `parents=0`. Zero `ERROR SCRIPTING`.

Every state of the verdict vocabulary was observed, failures included: the four `FAIL` branches were
forced live by writing a record with a deadline already past.

## Known gap, stated rather than hidden

The two Lua transition recorders have **no standalone test** — the scenario file is not loadable
outside a mission, and pinning it against a stub would test the one thing a stub cannot answer. Their
verification is the DCS run. Forcing the failure branches exercised the *verdict* reading a record,
not the *recorders* writing one.

## Four defects it caught in its own code before merge

An expectation going green on an empty reply; an injection that desynchronised the two copies of a
trigger (caught only by testing both serialisations); `--list` naming an archive that holds a
placeholder; and `--with-bridge` claiming to inject a bridge that was already there. The last two
were found by reviewing the diff, and no test would have caught them — the mission came out correct
both times.
