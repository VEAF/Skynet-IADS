# 01 — a runner, and the five questions it puts to the demo

Status: 🔄 in-progress

Lot: [FEAT-IN-SIM-SMOKE-TESTS](../PRD.md)

## What

`build-tools/run-smoke.py`: stdlib only, no dependency. It selects checks, sends their Lua to
`dcs-serve`'s `POST /api/exec`, polls the ones that watch something unfold, prints a table and
returns an exit code.

```
python build-tools/run-smoke.py --list
python build-tools/run-smoke.py --target demo
python build-tools/run-smoke.py --target lastline --tier slow
```

Flags: `--target`, `--tier {fast,slow,all}`, `--only NAME...`, `--url`, `--token`, `--timeout`,
`--poll-timeout`.

## The three reply shapes it has to tell apart

This is the substance of the ticket. All three arrive over the same wire and two of them lie.

| what happened | how it arrives | what the runner does |
|---|---|---|
| the Lua returned a word | `200 {"result": "alive"}` | judge it against the check's predicate |
| the Lua **raised** | **`200`** `{"error": "..."}` | raise — the status code alone would call it an answer |
| DCS is not connected | `503 {"ready": false}` | **skip the whole run and exit 0** |
| the token lacks `superuser` | `401` / `403` | say so and exit 2, rather than reporting every check red |
| the command timed out in DCS | `504` | fail that check, keep going |

The self-skipping behaviour is VMCT's stance and worth stating plainly: the absence of a simulator
is not a result about Skynet, and reporting it as one teaches people to ignore the output.

## Transport loss, and why a test enforces it

`handleExec` in `dcs-bridge.lua` returns `tostring(result ~= nil and result or "")`. For `false`
that evaluates to `""` — see the PRD for the trace. So a reply of `""` means *the check returned
something the transport cannot carry*, and the runner reports it as `ABORT`, not `FAIL`: "failed"
would send somebody hunting a defect in Skynet when the defect is in the check.

`test/python/test_run_smoke.py` sweeps **every** expectation in `CHECKS` against `""` and fails if
one of them would accept it. It earned its place immediately: `artifact-loaded` was first written as
`v not in ("skynet-absent", "nil")`, which accepts `""`, and the sweep caught it. The fix was to pin
the shape of a version instead — an allow-list of what is acceptable cannot make that mistake, a
deny-list of known-bad values can.

## The five checks

Five `fast` checks against `build/missions/skynet-test-persian-gulf.miz`, open in DCS. The runner
only asks questions: nothing is spawned, nothing is modified, and the mission needs no new trigger
and no edit. That is why this ticket builds no mission.

| check | what it asks | goes red when |
|---|---|---|
| `artifact-loaded` | `SkynetIADS.version` | the artifact did not load in the real engine, or reports no version |
| `networks-built` | `#getSAMSites()` and `#getEarlyWarningRadars()` on `redIADS` | prefix discovery enrolled nothing |
| `named-elements-found` | the six elements the setup script configures by name | one of them is not in the network |
| `jammer-alive` | `Unit.getByName('jammer-emitter')` exists and lives | the demo destroyed its own jammer |
| `no-mist` | `type(mist)` | MiST came back |

## Why these five

**They are the ones that would have caught this month's defects.** Not chosen for coverage — chosen
against the record:

- the in-sim archives ran a **December 2023 artifact** for three years → `artifact-loaded` prints
  the version, so a stale mission shows up as the wrong number rather than as a pass;
- **MiST** installed its own event handler and put a popup on the player's screen → `no-mist`;
- **both Persian Gulf demos destroyed their jammer** at t=0 on every load from 2020 → `jammer-alive`,
  which is `FIX-DEMO-DESTROYS-ITS-JAMMER` turned into a permanent question. That lot is why this
  check exists, and this check is what proves the lot.

`networks-built` and `named-elements-found` cover the step every mission maker actually depends on
and the one that fails quietly: prefix discovery finding nothing after a group is renamed.

## Why named elements rather than a count

A count is derived from the same table the network read, so asserting it is close to asserting that
addition works. The six names — `SAM-SA-2`, `SAM-SA-6`, `SAM-SA-11`, `SAM-SA-11-2`, `EW-Center3`,
`AWACS-K-50` — are hard-coded in the demo's **own setup script**, which configures each one
individually. Asking the network to hand them back proves discovery reached them *and* that the
lookups work, against a list written somewhere else.

## Two numbers deliberately not pinned

`networks-built` asserts both counts are non-zero and nothing more. The exact figures are not in the
code, because **nobody has counted them**: they would be a guess dressed as a regression net, and a
wrong one would fail the first real run for no reason. The first DCS run fills them in below, and
the expectation tightens to those numbers in the same pull request if it is still open, or in a
one-line follow-up if it is not.

## Measured in DCS — 2026-09-21

Run twice against `build/missions/skynet-test-persian-gulf.miz`, once without
`FIX-DEMO-DESTROYS-ITS-JAMMER` and once with it, so every check has been seen in the state it is
supposed to report.

Without the fix, David in the `Hornet SA-11-2` slot:

```
  PASS  artifact-loaded       3.5.0
  PASS  networks-built        sam:13 ewr:8
  PASS  named-elements-found  all-found
  FAIL  jammer-alive          emitter-gone
  PASS  no-mist               nil

4/5 passed
```

With it: **5/5**, `jammer-alive` → `alive`, and the network then reports the F-4E as a contact at
53 NM — which it cannot do for an aircraft that no longer exists. Exit code 1 on the failing run and
0 on the passing one.

So `jammer-alive` has now been seen red **and** green, which is the only way a check is tested. It
also settles the slot question from the outside: the guard fired while the slot it tests was
occupied.

**The two counts are now pinned.** `sam:13 ewr:8`, measured rather than guessed, and the expectation
tightened from "non-zero" to those exact figures — with the test updated to match. Non-zero was too
weak for the failure that actually happens: a renamed group does not empty the network, it makes it
*smaller*, and `sam:1 ewr:8` would have sailed through. If somebody adds a battery to the demo this
goes red and the number moves in the same change, which is the point of a regression net.

**One claim withdrawn rather than repeated.** An earlier draft of the sibling lot cited "zero
`SKYNET: JAMMER:` lines in the log" as evidence the jammer was dead. Measured here on the **fixed**
build, with the F-4E alive and tracked: still zero, because the jammer only logs within
`maximumEffectiveDistanceNM` of a *live* radar and this run never reached that geometry. The absence
is consistent with both states, so it proves nothing and is out of the record.

## Why stdlib only

`miz-suite.py` sets the precedent and CTLD's runner made the same call. A tool a developer runs
occasionally on a Windows DCS machine should not need a virtual environment; `urllib` is enough for
one POST.

## Definition of done

- The runner exists, and `--list` prints the checks and the missions they need.
- Every reply shape in *The three reply shapes* above is covered by a test driving a patched `urlopen`.
- No expectation in `CHECKS` accepts the empty string, enforced by a test rather than by review.
- A polled check reaches a terminal verdict, honours `--poll-timeout`, and its arming step runs once
  and before the poll.
- `python -m unittest discover -s test/python` is green.
- The five checks are in `CHECKS`, each with a `why` worth reading on the day it fails.
- `build --with-bridge` puts the bridge in, plain `build` does not, and the committed archives are
  untouched by both.
- Run against a real DCS, with the table above filled in and the two counts recorded.

## Why this is one ticket and not two

It was two while it was being written — "the runner" and "the checks" — and that split did not
survive contact with the commit. Both live in one file and are one subject: a runner with no
questions is not runnable, and a question with no runner cannot be asked. Splitting them would have
meant either an intermediate commit that does nothing or two subjects in one commit, which
`CLAUDE.md` forbids for good reason. The ticket follows the code rather than the other way round.
