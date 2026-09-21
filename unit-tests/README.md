# In-sim checks

Everything in this directory needs DCS running. The standalone suite is `test/lua/` and runs
anywhere; what is here is what a stub cannot answer — terrain, real detection geometry, in-game
events, how a DCS group is composed, and above all *whether the simulator ever calls the code at
all*. That last one is the failure no unit test can reach: a mechanism that is perfectly tested and
never invoked.

| | what it is | how it runs |
|---|---|---|
| `skynet-unit-tests.miz` | the legacy in-sim suite, luaunit, being migrated into `test/lua/` | open it in DCS, read the screen |
| `highdigitsams/highdigitsams-unit-tests.miz` | the same, for the High Digit SAMs mod | open it in DCS, read the screen |
| `last-line-of-defence/` | two checks driven from outside, no player task | `build-tools/run-smoke.py`, or by hand |

**Build before you open anything.** The archives in git carry placeholders, not the scripts they
run — a committed copy of the code goes stale in silence, and did, for three years. Assemble the
playable missions first:

```
pwsh -File build-tools/build-compiled-script.ps1
python build-tools/miz-suite.py build --with-bridge
```

They land in `build/missions/`, which is git-ignored. A mission opened unbuilt says so on screen.

`--with-bridge` wires `dcs-bridge.lua` into every archive that does not already carry it, which is
what lets the smoke gate reach the demo. Leave it off and you get exactly what a release attaches —
the demos are release assets, and a mission somebody downloads must not open a socket on their
machine. The bridge is copied out of `last-line-of-defence`, so both smoke targets are driven
through byte-identical code.

## The smoke gate

`build-tools/run-smoke.py` sends small pieces of Lua into a running DCS through VEAF's
[dcs-bridge](https://github.com/VEAF/VEAF-dcs-bridge), reads back one word per check, and prints a
table.

It is **consultative, not a gate**: it informs a release, it does not block one. David's call,
2026-09-21. And it cannot become a CI job — GitHub runners have no DCS, no licence and no GPU. Both
sibling VEAF projects landed in the same place and wrote it down, CTLD_Next in
`docs/developer/integration-testing.md` and VMCT in `doc/developer/smoke-harness.md`. When there is
nothing to talk to, this says so and exits 0 rather than failing for the absence of a simulator.

### Once, on the DCS machine

1. De-sanitise `Scripts/MissionScripting.lua` in your DCS install, or the bridge cannot open its
   socket. See dcs-bridge's [prerequisites](https://veaf.github.io/VEAF-dcs-bridge/guide/prerequisites/).
2. Have `dcs-serve` running. `/api/exec` is gated to the **superuser** role, so an operator token is
   refused — the runner says so instead of reporting every check as failed.

### Each time

```
python build-tools/run-smoke.py --list
python build-tools/run-smoke.py --target demo
python build-tools/run-smoke.py --target lastline --tier slow
```

The token comes from `--token`, else `$DCS_BRIDGE_API_KEY`, else the `api_key` line of a
`dcs-client.yaml` in a `VEAF-dcs-bridge` checkout beside this repository.

`--target` says which mission has to be open. `--tier fast` (the default) answers in seconds;
`--tier slow` flies an aircraft and takes minutes, so it is never in the default sweep.

### What is checked, and against which mission

**`--target demo`**, with `build/missions/skynet-test-persian-gulf.miz` open. Nothing is spawned and
nothing is modified; the runner only asks questions. These check what we actually ship.

| check | goes red when |
|---|---|
| `artifact-loaded` | the artifact did not load in the real engine, or reports no version |
| `networks-built` | prefix discovery enrolled no site or no radar |
| `named-elements-found` | one of the six elements the demo configures by name is not in the network |
| `jammer-alive` | the demo destroyed its own jammer — which it did, on every load, from 2020 to 2026 |
| `no-mist` | MiST came back; its event handler puts a popup on the player's screen |

**`--target lastline`**, with `build/missions/skynet-insim-last-line-of-defence.miz` open. These
spawn aircraft and watch them fly.

| check | goes red when |
|---|---|
| `last-line-of-defence` | a dark battery does not wake on proximity, **or** never goes quiet again |
| `coverage-follows-what-moves` | a battery covered only by an AWACS is not held, **or** never handed back |

Both halves, in both cases. A run that only ever shows one of them proves nothing.

### Driving it by hand instead

The scenario is usable without the runner, which is how it was built. Through the bridge's
`exec_lua`:

```lua
SKYNET_TEST.geometry()          -- separation, ranges, radius, parents, ground: is the montage sane
SKYNET_TEST.launchIntruder()    -- run 1
SKYNET_TEST.startCoverageRun()  -- run 2, in a network of its own
SKYNET_TEST.verdict()           -- IDLE | RUNNING | PASS | FAIL: <reason>
SKYNET_TEST.coverageVerdict()   -- the same, for run 2
```

Both runs write their status into `dcs.log` every 5 s on their own. The verdict says whether it
passed; the log says how it went, which is what you want when it did not.

## Adding a check

Append a `Check` to `CHECKS` in `build-tools/run-smoke.py`. Four things it must have:

1. **It must be able to go red**, and for a reason worth holding a release over. A check that cannot
   fail is a line of output, not a test.
2. **Its Lua must return a word.** Never a boolean, never a table. `handleExec` in `dcs-bridge.lua`
   ends on `tostring(result ~= nil and result or "")`, and that idiom turns `false` into the empty
   string — indistinguishable from nil, from a crash, and from success. Tracked upstream as
   [VEAF/VEAF-dcs-bridge#35](https://github.com/VEAF/VEAF-dcs-bridge/issues/35), which proves all
   four cases against a live DCS. VMCT paid for the same lesson twice and CTLD reached the same rule
   independently. `test/python/test_run_smoke.py` sweeps every
   expectation against the empty string and fails the build if one of them would accept it; it
   caught exactly this defect in `artifact-loaded` while that check was being written.
3. **A `why` worth reading on the day it fails**, because that is the only day it is read.
4. **A tier.** If it waits on an aircraft, it is `slow`.

Then run `python -m unittest discover -s test/python`, which covers the runner's own logic — never a
real DCS.

## What does not belong here

**Figures Eagle Dynamics states about a unit** — a missile's reach, its firing ceiling, a radar's
detection distance. Those live in `test/lua/dcs-figures.lua`, generated from a pinned datamine
commit, with a weekly workflow that opens a pull request when one moves. Asserting them inside a
mission means a red test nobody sees for three years, which is what happened.

**Anything a stub can answer.** A suite whose every assertion runs standalone is removed from both
copies — the loose `unit-tests/*.lua` and the one inside the `.miz`. See `test/lua/README.md`.
