# 03 — a machine verdict for the two flown runs

Status: 🔄 in-progress

Lot: [FEAT-IN-SIM-SMOKE-TESTS](../PRD.md)

## What

`unit-tests/last-line-of-defence/skynet-insim-last-line-of-defence.lua` already flies an intruder at
a dark battery and flies an AWACS away from another. It was missing the last link: a **verdict a
machine can read**. Until now the procedure ended with *"the transitions are what to read back"* —
a human, in `dcs.log`, deciding.

Adds `SKYNET_TEST.verdict()` and `SKYNET_TEST.coverageVerdict()`, each returning one of `IDLE`,
`RUNNING`, `PASS`, or `FAIL: <reason>`, and two `slow` checks in the runner that arm a run and poll
it.

## Why a verdict cannot be computed on demand

Both runs are about a **transition**, not a state. A battery that is dark right now is either one
that never lit — the failure — or one that has correctly gone quiet again — the pass. The current
state cannot tell them apart.

So the two watches, which already tick every 5 s, now also record the edges as they go past, and the
verdict reads the record:

| run | passes when | and only then |
|---|---|---|
| 1 | the site went `ACTIVE`, **and** later went inactive | a light-up with no extinction is not a pass |
| 2 | the battery was held non-autonomous, **and** later handed back | a hold with no hand-back is not a pass |

Going dark is only counted **after** a light-up. Without that, a run in which nothing whatsoever
happened would score the initial dark state as "went quiet" and pass.

## Two properties the recorders must have

**They must not raise.** Each runs inside a `timer.scheduleFunction` body, and DCS drops a schedule
whose body errors. The run would then go blind from that second on and look exactly like a run where
nothing happened — the precise failure this file exists to detect. Both are guarded by `pcall`, and
the existing `status()` carried the same warning in a comment before this ticket.

**They must return a word, never a boolean.** `handleExec` in `dcs-bridge.lua` turns a `false` into
the empty string; see the PRD for the trace. A verdict of `false` would be indistinguishable from a
crash.

## The deadline, and why it is not the runner's

The runner has a `--poll-timeout`, but a timeout there can only ever say *"still RUNNING after
600s"*. A deadline inside the scenario can say **which half never happened** — and that is the
difference between a report somebody acts on and one they have to reproduce. `RUN_DEADLINE` is ten
minutes; run 1 flies 80 km at 200 m/s, so seven is the honest figure and the rest is slack for a slow
load. The runner's timeout stays as a backstop.

## Arming resets the record

`launchIntruder()` rebuilds `SKYNET_TEST.run1` from scratch. The watch has been recording since
mission start, so without the reset a second run would inherit the first one's edges and pass on
them. `startCoverageRun()` does the same for `run2`.

## The gap, stated rather than hidden

**The two recorders have no standalone test.** They are new logic, and `CLAUDE.md` says new logic
ships with its tests. It does not here, and the honest reason is that the scenario file is not
loadable outside a mission: it calls `coalition.getGroups` at load, builds a network, and starts a
scheduled watch on its last line. Testing the state machines would mean either restructuring the
file so they can be lifted out, or loading the whole scenario against `test/lua/dcs-stub.lua` — and
the second would pin behaviour against a stub for a file whose entire purpose is to measure things a
stub cannot answer, which is the kind of test `CLAUDE.md` calls worth nothing.

What stands in for it: both state machines are a dozen lines over a single boolean, both are guarded
by `pcall`, and the DCS run below is the verification. The run must therefore include a **deliberate
failure** — not just two PASSes — or the verdict is untested in the only direction that matters.

Left as a decision for David rather than taken unilaterally: extract the recorders into a pure
module under `test/lua/` and test them there, or accept the DCS run as the gate.

## What did not change

The log lines. Both watches still write their status every 5 s, and that remains the way to see
*how* a run went rather than whether it passed — which is what you want on the day it did not. The
verdict is added beside them, not in their place.

## Definition of done

- `SKYNET_TEST.verdict()` and `SKYNET_TEST.coverageVerdict()` answer in one word, `IDLE` before a run
  is armed.
- Neither recorder can raise out of its scheduled body.
- A second `launchIntruder()` measures afresh.
- The two `slow` checks arm their run and poll to a terminal verdict.
- The file still parses under Lua 5.1, and `miz-suite.py check` is happy.
- **Run in DCS**, both reaching `PASS`, with the timings recorded here.

## Measured in DCS — 2026-09-21

```
  PASS  last-line-of-defence         PASS
  PASS  coverage-follows-what-moves  PASS

2/2 passed
```

**Montage checked before committing fifteen minutes of flight to it**, with `SKYNET_TEST.geometry()`:
the EWR sits 106.0 km from the site for a detection range of 267.5 km, so it covers it and the
network holds it dark; the site's radius came out at 12.7 km, inside the 10–15 km the design draws
from; one parent radar; both elements on land. A run started on a bad montage proves nothing, and
this is the one call that says so in two seconds.

### Run 1, the last line of defence

| t | what the watch saw |
|---|---|
| 49 s | intruder 36.36 km out. `ACTIVE=false AUTONOMOUS=false targetsInRange=false` — dark, and held by the network |
| 213 s | intruder **5.83 km**, inside the 12.7 km radius. `ACTIVE=true AUTONOMOUS=false targetsInRange=false freshReport=true` |
| 525 s | intruder 39.84 km out the other side. `ACTIVE=false freshReport=false` — quiet again |

The middle row is the whole mechanism in one line. `ACTIVE=true` with `targetsInRange=false` means
the site lit with **no radar contact anywhere** — proximity alone woke it. `AUTONOMOUS=false` means
it woke *into* the network rather than being handed to the DCS AI, which is the difference between
the fix and a workaround. And the third row is the half that makes it a test rather than a demo:
it went quiet again.

Over the run the watch recorded 42 ticks lit against 63 dark — a bounded window with dark either
side, not a site that came on and stayed on.

### Run 2, coverage follows what moves

Final state: `AWACS at 214.7 km (range 204.5 km) | battery AUTONOMOUS=true parents=0 | AWACS covers
0 site(s)`. The AWACS crossed its own detection range and the sweep dropped the link: the battery
lost its only parent and was handed back to itself.

### Every verdict seen, including the ones that fail

A verdict nobody has seen go red is a verdict nobody has tested, so the four failure branches were
forced live through the bridge by writing a record with a deadline already past — no re-flying:

| forced state | answer |
|---|---|
| run 1, never lit | `FAIL: the site never lit up -- the last line of defence did not wake it` |
| run 1, lit and never dark | `FAIL: the site lit up but never went quiet again -- the persistence never expired` |
| run 1, inside the deadline | `RUNNING` |
| run 1, not armed | `IDLE` |
| run 2, never held | `FAIL: the battery was never held -- the AWACS never became its parent` |
| run 2, held and never handed back | `FAIL: the battery was held and never handed back -- the coverage refresh did not purge` |

Six states, each naming the half that is missing. That is the whole vocabulary exercised against a
running DCS.

**Zero `ERROR SCRIPTING` lines** in the log across both runs.

This is also what stands in for the standalone test the recorders do not have — see the gap above.
It is weaker than a unit test in one specific way, and worth saying: the failure branches were
exercised by writing the record directly, so they prove the **verdict** reads a record correctly,
not that the **recorders** write one correctly. The recorders are covered only by the two runs
passing.
