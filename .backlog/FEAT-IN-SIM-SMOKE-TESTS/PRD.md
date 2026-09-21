# FEAT-IN-SIM-SMOKE-TESTS — a release can be flown before it is numbered

Status: 🔄 in-progress

Origin: `docs/evolutions.md` has carried a *Smoke tests* entry since the repository was
professionalised — *"study how the legacy unit-test can be transformed into something more usable
and build in-sim smoke tests. See if MCPs or such exists that can help communicate with a running
DCS mission."* David reopened it on 2026-09-21, before cutting the first VEAF release, alongside
`FIX-DEMO-DESTROYS-ITS-JAMMER`. This lot answers it and takes the entry with it.

## The gap

The standalone suite proves that a function does what it says. 94.63% of the source is covered and
CI holds a floor that only goes up. None of it can prove:

- that the artifact loads in the real engine, where DCS's own Lua 5.1 and its sanitisation live;
- that the simulator ever **calls** the mechanism — the failure mode `FEAT-LAST-LINE-OF-DEFENSE` was
  written to catch is code that is perfectly tested and never invoked;
- that the mission somebody downloads still demonstrates what it claims.

Every defect found by flying, this month, is in that third category, and none of them went red:
the in-sim suites ran a December 2023 artifact for three years; three of four demos shipped Skynet
3.2; MiST put a popup on a player's screen; and both Persian Gulf demos destroyed their own jammer
at t=0 on every load since 2020. Four findings, all from somebody opening DCS, none from a gate.

## What the neighbours do, and what we take

Read on 2026-09-21 rather than invented. `CTLD_Next` and `VEAF-Mission-Creation-Tools` have both
built this, independently, and agree on more than they differ.

| | CTLD_Next | VMCT v4 | here |
|---|---|---|---|
| transport | `dcs-serve`, `POST /api/exec` | the dcs-fiddle hook **and** `dcs-serve` | `dcs-serve` only |
| verdict | `PASS/FAIL/ABORT/RUNNING/STARTED` | a predicate over a tagged string | both: a tagged word, a Python predicate |
| runner | `run_scenarios.py`, 426 lines, no dependencies | `veaf-tools dcs smoke-test` | `build-tools/run-smoke.py`, no dependencies |
| tiers | `auto / auto-check / auto-slow / human` | `--probe-only` then assert | `fast / slow` |
| shape | one file per scenario, ~60 of them | checks as data, 9 of them | checks as data — we have seven, not sixty |
| in CI | **no**, and their docs say why | **no**, and their docs say why | **no**, and this says why |
| the test mission | committed `.miz`, code found by an env var | a source folder, `.miz` assembled and git-ignored | assembled by `miz-suite.py`, same as VMCT |

Two things settle by themselves from that table. **Nobody runs DCS in CI** — GitHub runners have no
DCS, no licence and no GPU, and both projects treat that as a design stance rather than a debt. And
**VMCT assembles its test mission rather than committing it**, which is the choice this repository
already made with `miz-suite.py`, arrived at separately.

What we take deliberately: CTLD's **tiers**, because our checks do not all cost the same in
wall-clock seconds and a sweep should not sit behind an aircraft; VMCT's **check-as-data** shape,
because seven checks in a list read better than seven files; and from both, the **one-word verdict**.

## The trap, verified in the bridge's own code

VMCT's hardest-won lesson is *"everything crosses as a string, tag your verdicts"*. Their pain came
from `net.dostring_in`, which returns a Lua **error as an ordinary result** — a check went green on
the reply that proved nothing had run. Checked against our transport before relying on it:

```lua
-- src/lua/dcs-bridge.lua, handleExec
local ok, result = pcall(f)
if ok then
    enqueue({ id = msg.id, result = tostring(result ~= nil and result or ""), error = nil })
else
    enqueue({ id = msg.id, result = nil, error = tostring(result) })
end
```

Good news: errors go in a separate `error` field, so VMCT's worst trap does not reach us. Bad news,
and it is real: `result ~= nil and result or ""` is the classic Lua `and/or` pitfall. When the Lua
returns `false`, `result ~= nil` is true, `true and false` is `false`, and `false or ""` is `""`. **A
boolean `false` arrives as the empty string**, indistinguishable from nil, from a crash and from
success. A table arrives as `table: 0x...`, truthy and meaningless.

Hence the house rule, which is why CTLD and VMCT both reached it: **a check returns a word.** It is
enforced rather than remembered — `test/python/test_run_smoke.py` sweeps every expectation against
the empty string, and it caught `artifact-loaded` going green on `""` while that check was being
written.

**Already reported upstream**, and the search for that was worth doing before opening a duplicate:
[VEAF/VEAF-dcs-bridge#35](https://github.com/VEAF/VEAF-dcs-bridge/issues/35) has the same trace plus
something better than a trace — the four cases measured against a live DCS, where `return true` gives
`"true"` and `return false`, `return nil` and no return at all are all `""`. So there is nothing for
this project to file. The rule above is the workaround, and it stays worth keeping once the bridge is
fixed: a word says more at a glance than a boolean ever will.

One more, worth knowing: **a Lua error comes back as HTTP 200** with an `error` field. Reading the
status code alone would take it for an answer.

## What to do

| | Ticket |
|---|---|
| 1 | [a runner, and the five questions it puts to the demo](tickets/01-a-runner-that-talks-to-dcs-serve.md) |
| 2 | [a machine verdict for the two flown runs](tickets/02-a-machine-verdict-for-the-flown-runs.md) |

Two, not the three this lot was planned with. "The runner" and "the checks it runs" turned out to be
one subject in one file, and the split would have forced either a commit that does nothing or two
subjects in one commit. Written down because the split was announced before the work started.

One branch, one pull request. Nothing under `skynet-iads-source/` changes, so the artifact is
unaffected and the coverage floor does not move.

## Two targets, and why no new mission was built

The expensive part of an in-sim check is the mission. This lot builds none, because the runner sends
its Lua to whatever is open:

- **the demo** — `skynet-test-persian-gulf.miz`, untouched. Five questions, nothing spawned, nothing
  modified. These check what we actually ship, which is where every defect of this month was.
- **`last-line-of-defence`** — already flies an intruder and moves an AWACS. It was missing only the
  last link: a verdict a machine can read. Ticket 2 adds it.

### The demo target does not work yet, and here is why

Found by David on 2026-09-21, by asking whether the mission had what the bridge needs. It does not.
`dcs-bridge.lua` has to be **loaded by the mission** for `dcs-serve` to reach anything, and only
`skynet-insim-last-line-of-defence.miz` carries it — 13 575 bytes, committed in full, wired as a
third script. The two demo archives wire two scripts and neither is the bridge:

```
== demo-missions\skynet-test-persian-gulf.miz
wiring consistent, 2 scripts loaded in this order:
   1. skynet-iads-compiled.lua  (ResKey_Action_172)
   2. skynet-iads-setup-persian-gulf.lua  (ResKey_Action_337)
```

So the five `fast` checks are written, tested and unreachable: with the demo open, `dcs-serve` has
nothing to talk to. The two `slow` checks work today.

The fix cannot be "bake the bridge into the demo". Those archives are **release assets**; a mission a
newcomer downloads must not open a socket on their machine. It has to be injected only for a smoke
run, into `build/missions/`, which is git-ignored — and `miz-suite.py` can `remove` a script from an
archive's four wiring places but has no inverse. Adding one means allocating a resource key, writing
`mapResource`, appending to the existing trigger's action string and putting the file in the zip,
across the two serialisations `test/python/test_miz_suite.py` covers.

**Resolved 2026-09-21: David chose the injection, in this branch.** `miz-suite.py build
--with-bridge` wires the bridge into every archive built that does not already carry it, across the
same four places `remove` clears. It never touches a committed archive, and a plain `build` is
unchanged — so what a release attaches still ships no socket. The copy is lifted from
`skynet-insim-last-line-of-defence.miz`, which means both smoke targets are driven through
byte-identical bridge code rather than through whatever a checkout next door happens to hold.

The injection clones the neighbouring structures rather than templating them. A block is seven lines
in DCS's serialisation and two in the editor's, one closes on `-- end of [n]` and the other on
nothing, and a malformed one still parses as Lua — so nothing would complain until DCS did. Copying
the neighbour and changing its key and its number cannot pick the wrong shape.

**A real defect was caught by testing both shapes**, which is the reason that discipline exists here.
The first version appended the compiled call at the end of `trig.actions` but the action block to the
**first** `trigrules` array. `check` demands the two flat key lists be equal, so the moment a mission
has two script-loading triggers the orders diverge. The Persian Gulf demo has one; the editor-shaped
fixture has two. Verified by mutation: restoring the faulty line turns
`test_the_result_passes_check_editor` red with the exact disagreement.

## What this lot does not touch

**JUnit XML.** CTLD's runner writes it and nothing consumes it, there or here. A printed table and an
exit code are what a consultative step needs; the day something reads a report, it can be added.
David's call, 2026-09-21.

**Sharing the runner with the other two repositories.** Three implementations of the same client is
the argument for pulling it into `VEAF-dcs-bridge`, and it should be proposed — but after ours has
run against a real DCS, not before. Designing the shared thing from two examples and a guess is how
you get a third thing nobody uses. Also David's call, same day.

**The legacy suites.** The *Smoke tests* entry asked what to replace them with. That is
`CHORE-PROFESSIONALIZE-THE-REPO` ticket 04's migration, which is done: a suite whose every assertion
runs standalone has already left both copies. What stays in a `.miz` stays because a stub cannot
answer it.

## Definition of done

- `python build-tools/run-smoke.py --list` names seven checks across two targets.
- **The demo target can actually be reached**: `build --with-bridge` wires the bridge in, a plain
  `build` does not, the committed archives never change, and the injected copy is byte-identical to
  the one `last-line-of-defence` carries.
- `python -m unittest discover -s test/python` covers the runner's own logic, including the sweep
  that no expectation accepts a lost reply.
- With no DCS running, the runner **skips and exits 0**, and says nothing was measured.
- The two flown runs answer `IDLE`, `RUNNING`, `PASS` or `FAIL: <reason>` to a single call.
- The `release` skill runs the checks before the version is bumped, consultatively.
- `unit-tests/README.md` says how to run it and how to add a check.
- The *Smoke tests* entry in `docs/evolutions.md` is replaced by a pointer here.
- **Measured against a real DCS**, and the figures written into ticket 2 — including the two counts
  `networks-built` deliberately does not pin yet, because nobody has counted them.
