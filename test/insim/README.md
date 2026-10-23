# In-sim suite

Scenarios that run inside DCS, driven by one command from a terminal. They answer what neither a stub
nor a read of the code can: that DCS calls Skynet, what real radars report, how real groups and
statics are composed. The logic stays in `test/lua/`; this suite is the check before a pull request
that touches `skynet-iads-source/`. It is recommended, not required: CI has no DCS.

You run the test mission in DCS (the one manual step), run `python test/insim/run.py`, and read a
summary: each scenario `pass`, `fail`, `invalid`, `crashed`, or `skipped` (it needs another mission than the one running),
and an exit code.

## Setup, once

- **Python 3**, standard library only. **PowerShell** (`pwsh`), for the Skynet build. **Lua 5.1**
  outside DCS, to judge results: `lua5.1` on `PATH`, else *Lua for Windows* at
  `C:\Program Files (x86)\Lua\5.1\lua.exe`, else `--lua PATH`.
- **Unlock `io` and `lfs` in DCS.** In `<DCS install>\Scripts\MissionScripting.lua`, comment out
  `sanitizeModule('io')` and `sanitizeModule('lfs')`. Hotload reads and writes its mailbox with
  them, and the mission reads the Skynet script and the scenarios with `io`. The edit is
  install-wide, and a DCS update reverts it.

## Running it

```
python test/insim/run.py                      # the minimal tier
python test/insim/run.py --tier full          # minimal and full
python test/insim/run.py iads-builds          # by name; a named scenario ignores the tier
python test/insim/run.py --skynet FILE        # test this Skynet script instead of the repository's build
python test/insim/run.py --resume             # continue the latest run after a crash
python test/insim/run.py --verify             # judge the latest run's results again, without DCS
python test/insim/run.py --lua PATH           # the Lua 5.1 interpreter
```

The command:

1. prepares the Skynet script the mission loads, `build/insim/skynet-iads-insim.lua`. By default it
   rebuilds it from `skynet-iads-source/` unless the file is already the build of the current
   sources; `--skynet FILE` copies that file instead, and the next default run rebuilds;
2. prepares the mission DCS opens (see *The mission*);
3. waits for the mission to answer. If DCS is not running it, it says which file to run:
   `test/insim/miz/insim01.miz`. **That is the manual step.** Later, if the mission stops answering
   while a command is in flight, it says "paused, or DCS is down" and waits: it never concludes
   anything from silence;
4. checks that the mission runs the Skynet script as it now is on disk. If not, it stops and says to
   **restart the mission**: the script is loaded once, at mission start, so a change under
   `skynet-iads-source/` needs a build (the command does it) and a mission restart. A change to a
   scenario or to a `user-lib/` library does not;
5. runs each scenario one at a time, printing each phase (setup, run, teardown, cleanup) as it starts
   and how it ended, then the scenario's verdict;
6. prints the summary, writes `report.md` into `build/insim/results/<date-time>/` (git-ignored) and
   exits 1 if any scenario is `fail`, `invalid` or `crashed` (`skipped` does not count). It does not
   stop at the first failure. It exits 2 without running when the run is refused: an unknown
   scenario, a scenario folder missing a file, a stale Skynet script, no results to resume or verify.

A named scenario that does not exist is refused before anything is sent.

**After a DCS crash**, restart DCS, run the mission again and run the same command with `--resume`.
The scenario that was in flight is reported `crashed` and counts as a failure; it is not run again,
and the ones already done are not either.

**After editing a `verify.lua`**, `--verify` judges the latest run's recorded results again. It sends
nothing and needs no DCS.

A paused mission does not answer: the driver waits. The timeouts below count sim time, so a pause
sets none off.

## Writing a scenario

A scenario is a folder under `test/insim/scenarios/`; its name is the folder's. Nothing else goes in
it.

```
scenarios/iads-builds/
  scenario.lua     metadata only
  setup.lua        add fixtures, create the IADS; may call ctx.invalid(reason)
  run.lua          may wait; returns its measurements
  teardown.lua     optional; always runs
  verify.lua       outside DCS: judges what run returned
```

```lua
-- scenario.lua
return {
	tier = "minimal",   -- "minimal" or "full"; omit it and the scenario runs only by name
	mission = "insim01",
	timeout = 120,      -- sim seconds, for each phase command: setup, run, teardown, cleanup
}
```

**The phases.** The driver sends each as its own mailbox command: `setup`, then `run` only if setup
ended normally, then `teardown` whatever happened, then the engine's own cleanup. A raise in setup
skips `run`; `teardown` and cleanup are still sent. A raise in any other phase fails that phase
only. Each phase file receives `ctx`
(`local ctx = ...`) and is read from disk by its command, so an edited phase is live at the next
run. Do not wrap scenario code in `pcall`: Lua 5.1 cannot hold a pause across one.

**Measured in DCS, judged outside.** Nothing in the mission asserts. `run.lua` returns a table of
measurements, and a wait that times out is a measurement (`detected = false`), not an error.
`verify.lua` then judges it with plain Lua 5.1 and luaunit:

```lua
-- verify.lua
return function(result, lu)
	lu.assertEquals(result.sam, 1)
	lu.assertEquals(result.ew, 1)
end
```

| What happened | Verdict |
|---|---|
| setup and run ended normally, `verify.lua` passes | `pass` |
| setup and run ended normally, `verify.lua` fails | `fail`, with luaunit's message |
| `ctx.invalid(reason)` in setup or run | `invalid`, with the reason |
| a raise in setup or run | `fail`, with the message |
| setup or run past its `timeout` | `fail`, "timed out"; the driver stops the run with `Hotload.stop` |
| DCS died during the scenario | `crashed` |

`invalid` is for a precondition the scenario could not set up: it is never a `pass` or a `fail`.
A teardown or cleanup that fails adds a warning, since the next scenario may start from a dirty
world.

**`ctx`**, the one table passed to each phase. It lives between the phases of a scenario and is
dropped by cleanup.

| Member | Does |
|---|---|
| `ctx.name`, `ctx.mission` | the folder's name, and `mission` from `scenario.lua` |
| `ctx.state` | free: whatever `setup` hands to `run` |
| `ctx.invalid(reason)` | ends the phase as `invalid` |
| `ctx:add(role)` | adds the mission's fixture `FIXTURE-<scenario>-<role>` as `<scenario>/<role>` and returns the group or static; cleanup destroys it |
| `ctx:onCleanup(fn)` | `fn` is called by cleanup, through `Hotload.callOnMain`, last registered first |

The Skynet layer, loaded with `Hotload.load("insim-skynet")`:

| Function | Does |
|---|---|
| `iads(ctx)` | creates and activates an IADS from the units `ctx:add` put in whose role starts with `SAM` or `EW`, and registers its deactivation with `ctx:onCleanup` |

```lua
-- setup.lua
local ctx = ...
ctx:add("SAM-SA6")
ctx:add("EW")
ctx.state.iads = Hotload.load("insim-skynet").iads(ctx)
```

**Rules for the code of a phase.**

- Every wait is bounded: `Hotload.waitFor(fn, timeout)`, never an open-ended loop. A phase that still
  hangs is stopped by the driver once its `timeout` has passed, and recorded as `fail`.
- Anything that arms a timer or registers an event handler goes through `Hotload.callOnMain(fn)`; a
  timer armed from a run crashes DCS once the run has ended. `iads(ctx)` does it for the IADS.
- Log with `Hotload.log`: it stamps each line in `dcs.log` with the command's name, which carries the
  scenario and the phase.
- Shared code is a library in `test/insim/dcs-hotload/user-lib/`, loaded where it is used with
  `Hotload.load("name")`. A helper two scenarios need goes there, not copied between them.

**A fixture** is a late-activated group or static in the mission, named
`FIXTURE-<scenario>-<role>`. It is added under the same name each run, so adding over a live leftover
replaces it. Place it in the Mission Editor (see below), then use it with `ctx:add(role)`. The IADS
looks only at the prefix `<scenario>/`.

**The tiers.** `minimal` is what a contributor runs before a pull request; `full` adds the scenarios
not wanted every time. A scenario with no `tier` runs only when named. The `selftest-*` scenarios
have none: they prove the engine's own paths (a raise, `invalid`, a hang, a failing `verify.lua`) and
would keep any tier from exiting 0.

## The mission

`test/insim/miz/` holds two files per mission:

- `insim01.template.miz`, committed, is the reference. **It is edited in the Mission Editor**, never
  by hand in the archive. It holds a placeholder where the absolute path of hotload goes.
- `insim01.miz`, git-ignored, is the working copy DCS opens. `run.py` writes it before every run:
  when it is missing, when the template has changed, or when the checkout has moved. Do not edit it.

Scenarios name their mission (`mission = "insim01"`); a mission is known by its sortie name. The
driver runs the scenarios of the mission DCS is running, and lists the others as skipped, naming the
mission they need.

At mission start three actions run: the first sets `BASE_HOTLOAD_PATH`, the only absolute path in the
mission; the second loads hotload from it; the third loads the Skynet script under test, found
relative to hotload's folder. Nothing is embedded, so a change to the code never needs the mission
rebuilt. A later change to the mission starts from the template, never from an empty mission.

`build-tools/miz-suite.py` does not handle these archives.

## Hotload

`test/insim/dcs-hotload/` is dcs-hotload **2.0.0**, committed as released, so a run needs nothing
beyond the setup above. Its shipped files (`dcs-hotload.lua`, `README.md`, `LICENSE.md`, `bin/`,
`examples/`) are never edited here; its own `README.md` is the reference for `Hotload.*`.

What belongs to the suite stays:

- `user-lib/`: `insim.lua`, the engine's side in the mission, and `insim-skynet.lua`, the Skynet
  layer. Only the second names Skynet;
- `user-inbox/` and `user-outbox/`, the mailbox, git-ignored.

**To upgrade**, replace the shipped files and folders with those of the new release and leave
`user-lib/`, `user-inbox/` and `user-outbox/` alone. Then change the version stated above.

## Tests of the suite itself

The driver is tested without DCS: `python -m unittest discover -s test/python -p "test_insim_*.py"`.
The mission-side Lua is tested on a stub, in `test/lua/` (`test_insim.lua`, `test_insim_skynet.lua`).
