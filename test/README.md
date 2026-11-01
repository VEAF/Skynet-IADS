# Tests

Every test of this repository lives under `test/`, one folder per place tests run:

| Folder | Holds | Runs |
|---|---|---|
| `lua/` | Skynet's tests, and the check of `samTypesDB` against the DCS database | plain Lua 5.1 |
| `common/` | the runners, luaunit, the DCS stub and its fixtures, the source loader, the test-coverage report and its floor, and the tests of the stub and the fixtures | plain Lua 5.1 and Python |
| `insim/` | the in-sim suite: scenarios that run Skynet inside DCS | DCS, driven from a terminal |
| `insim-tools/` | the tests of the in-sim suite's own tooling | plain Lua 5.1 and Python |
| `build-tools/` | the tests of `build-tools/` | Python |
| `demo-missions/` | the tests of the demos' updater | Python |

Which suite a new test belongs to is decided in `CONTRIBUTING.md`. This file is how to run each one
and how to add to it.

## The standalone suites

Everything but the in-sim suite runs without DCS, through one runner per language. With no folder,
a runner finds every folder directly under `test/` that holds a `test_*` file of its language, so a
new suite folder runs without being registered anywhere. A folder or a name narrows the run.

Where `lua5.1` is on `PATH` (Linux, macOS, CI):

    lua5.1 test/common/run.lua                       # every Lua suite
    lua5.1 test/common/run.lua test/lua              # one folder
    lua5.1 test/common/run.lua test/lua contact      # the suites whose file name contains "contact"
    lua5.1 test/lua/test_skynet_iads_contact.lua     # one suite directly

On Windows without `lua5.1` on `PATH`, use the *Lua for Windows* binary,
`C:\Program Files (x86)\Lua\5.1\lua.exe`. PowerShell needs the call operator `&`, because the command
line starts with a quoted path:

    & "C:\Program Files (x86)\Lua\5.1\lua.exe" test\common\run.lua

cmd.exe takes the quoted path as it is:

    "C:\Program Files (x86)\Lua\5.1\lua.exe" test\common\run.lua

The Python suites run the same way, on any platform:

    python test/common/run.py                        # every Python suite
    python test/common/run.py test/build-tools       # one folder

### Adding a Lua suite

Create `test/lua/test_<module>.lua`. It pulls in `../common/luaunit.lua` and `../common/dcs-stub.lua`,
loads the source module through `../common/skynet-loader.lua`, and ends with
`os.exit(luaunit.LuaUnit.run())`; the runner finds it by name and aggregates its exit code.
`test_skynet_iads_contact.lua` is the pattern to copy.

The loader reads the order of `build-tools/listToMerge.txt`, the build's own, so a source added to
the build is loaded by the suites too.

One warning about the stub: a test that passes only because `dcs-stub.lua` returned something
convenient proves nothing. When a test needs the stub extended, extend it deliberately and write down
which real DCS behaviour it stands in for. The stub and the fixtures have tests of their own in
`test/common/`: if they imitate DCS wrongly, Skynet's tests pass against a world that does not exist.

### How a test is written

- **Drive the cycle a mission uses**, `SkynetIADS.evaluateContacts()` or `refreshRadarCoverage()`,
  rather than calling the function under test directly, and only then assert state. A wake-up can be
  perfectly tested and never called by the cycle.
- **Assert a printed status field by field** — names, order and values — rather than by string
  equality. A test that fails on a changed dash teaches people to delete tests. Make every counter
  non-zero, so that a printer stuck at zero cannot pass a presence check.
- **A test that pins behaviour which is probably wrong says so**, where it does. It records what the
  code does today, so that changing it is a decision somebody takes on purpose.
- **Compare mocks by identity**, with `assertIs`. luaunit compares tables by value, so two empty
  mocks are equal and an `assertEquals` on them cannot fail.
- **A test that cannot fail is a finding.** Break the code it guards once, and watch it go red.
- **A test never pins a figure that belongs to DCS** — a range, a ceiling, a detection distance —
  because ED changes them and Skynet reads them at runtime. What Skynet decides on top of them is
  Skynet's, and is what a test asserts: which of the search radar, the tracking radar and the
  launcher has to reach a contact, and what `setGoLiveRangeInPercent()` does to that.

### Needs the simulator

Tested in the in-sim suite on purpose, because a standalone test would only be asking the stub to
repeat what its fixture told it:

- **How a DCS unit is put together**: how many launchers and radars a group has, which is a search
  radar and which a tracking one, the NATO name DCS gives a type.
- **Terrain**: elevation, line of sight, `land.getIP`. The standalone `land` stub answers "visible,
  no intersection" and says so.
- **Real detection geometry**, as opposed to the range arithmetic Skynet does on top of it: what a
  DCS radar actually holds, and when.
- **Whether DCS calls the code at all**: events, timers, a group that really dies.

## Test coverage

How much of `skynet-iads-source/` the Lua suite actually executes. Beware the word: in Skynet,
*coverage* is what an early warning radar does to a SAM site — this is **test** coverage, and the two
never travel alone.

Run the suite with the hook, then report. Both commands run from the repository root, because that
is where `.luacov` and the stats file live:

    SKYNET_TEST_COVERAGE=1 lua5.1 test/common/run.lua test/lua
    lua5.1 test/common/report-test-coverage.lua

In PowerShell, with the *Lua for Windows* binary, which ships `luacov`:

    $env:SKYNET_TEST_COVERAGE = "1"
    & "C:\Program Files (x86)\Lua\5.1\lua.exe" test\common\run.lua test\lua
    & "C:\Program Files (x86)\Lua\5.1\lua.exe" test\common\report-test-coverage.lua
    Remove-Item Env:\SKYNET_TEST_COVERAGE

With `SKYNET_TEST_COVERAGE` unset — the normal case — the suite runs with no debug hook installed.

The report prints a per-file summary, worst first, then the total and a verdict. The per-line detail
lands in `luacov.report.out`, where a `****0` marks a line the suite never ran. What counts and what
does not is in `.luacov` at the repository root, with the reasons; the same two commands run in CI on
every pull request.

**There is a floor**, in `test/common/test-coverage-floor.txt`, and CI fails below it — exit 1,
distinct from exit 2, which means the measurement did not happen at all. The floor only ever goes up:
when your tests push the figure past it, raise it in the same pull request. The report tells you when
it can be raised and to what.

### What stays uncovered, and why

Measured at **94.63%**. Everything reachable is covered except the four entries below, so nothing is
left in the report without somebody having looked at it. Re-check this list whenever the figure moves
for a reason you did not expect.

**`skynet-iads-abstract-radar-element.lua` — 89 lines.** Four blocks:

- **`informOfHARM()`** — the geometry and the decision behind a HARM evasion: aspect, distance, time
  to impact, whether to remember the track as a HARM, whether to wake the point defences, whether to
  go dark and for how long. The largest single block left in the project.
- **`weaponFired()`** — the `S_EVENT_SHOT` handler that puts a launched missile on the
  missiles-in-flight list. The list itself is covered; what fills it is not.
- **The five ammunition helpers behind `shallIgnoreHARMShutdown()`** (`hasRequiredNumberOfMissiles`,
  `hasRemainingAmmoToEngageMissiles`, `hasEnoughLaunchersToEngageMissiles`,
  `pointDefencesHaveRemainingAmmo`, `pointDefencesHaveEnoughLaunchers`). The truth table above them is
  covered, by a test that mocks all five away.
- **`addHARMDecoy()`, the deprecated `setIgnoreHARMSWhilePointDefencesHaveAmmo()`,
  `calculateImpactPoint()`'s `land.getIP` call, and the debug-log branches.**

Writing these tests means deciding what `informOfHARM` should do, not recording what it does.

**Continuation lines — 34 lines, and no test can ever reach them.** The second and later lines of a
multi-line concatenation or `return`. Lua 5.1 attributes the whole expression to its first line, so
no debug hook fires on the rest. Nineteen of them are in the logger's status page, where every field
sits on its own line. Counting them as work left to do is how a coverage target becomes unreachable
for no reason.

**`inheritsFrom`'s `class()`, `isa()` and the default `create()` — 11 lines.** Dead inside this
repository: every class built with `inheritsFrom()` defines its own `create`, and `isa` and `class`
appear nowhere outside their own definition. They are still methods on every Skynet object, and the
artifact is vendored by other repositories, so a mission script may be calling them without this
repository knowing. Removing undocumented public surface from a vendored deliverable is a decision
for the maintainers, not a side effect of a test.

**`SkynetIADSUtils`'s `maxn` fallback — 5 lines.** It runs only where `table.maxn` is absent, which
means Lua 5.2 and later. DCS and this runner are both 5.1, so the shim cannot execute here. It is not
dead: it is what keeps the file loadable under a newer interpreter.

## The DCS unit types

`samTypesDB` is maintained by hand, and names DCS unit types that ED may rename. A renamed unit leaves
a site classified without it, and nothing else says so. `test/lua/check-unit-types.lua` checks every
type it names, in `searchRadar`, `trackingRadar`, `launchers` and `misc`, against the current head of
the [`Quaggles/dcs-lua-datamine`](https://github.com/Quaggles/dcs-lua-datamine) dump of the DCS
database:

    lua5.1 test/lua/check-unit-types.lua

It fetches the dump's file list into `build/dcs-lua-datamine/`, git-ignored, and exits 0 when every
type resolves, 1 when some are missing, listing them, and 2 when nothing could be measured. It reads
the head, not a pin, so a red run is the news. It needs the network, so the runners leave it out. The
High Digit SAMs are a mod, whose types are not in ED's dump, and are not checked.

`.github/workflows/dcs-unit-types.yml` runs it weekly, on demand, and on a pull request that touches
`skynet-iads-supported-types.lua`. A failed weekly run opens an issue.

## The in-sim suite

Scenarios that run Skynet inside DCS, driven from a terminal by one command. They check what only the
simulator can show: that DCS calls Skynet, what real radars report, how real groups and statics are
composed, and how a network behaves when it is attacked. Running them before a pull request that
touches `skynet-iads-source/` is recommended, not required: CI has no DCS.

You open a test mission in DCS (the one manual step), run `python test/insim/run-insim.py`, and read
a summary: each scenario `pass`, `fail`, `invalid`, `crashed`, or `skipped` (it needs another mission
than the one running), and an exit code.

### Setup, once

- **Python 3**, standard library only; it also runs the Skynet build. **Lua 5.1** outside DCS, to
  judge results: `lua5.1` on `PATH`, else *Lua for Windows* at
  `C:\Program Files (x86)\Lua\5.1\lua.exe`, else `--lua PATH`.
- **Unlock `io` and `lfs` in DCS.** In `<DCS install>\Scripts\MissionScripting.lua`, comment out
  `sanitizeModule('io')` and `sanitizeModule('lfs')`. Hotload reads and writes its mailbox with them,
  and the mission reads the Skynet script and the scenarios with `io`. The edit is install-wide, and a
  DCS update reverts it.

### Running it

```
python test/insim/run-insim.py                      # the minimal tier
python test/insim/run-insim.py --tier full          # minimal and full
python test/insim/run-insim.py iads-builds          # by name; a named scenario ignores the tier
python test/insim/run-insim.py --skynet FILE        # test this Skynet script instead of the repository's build
python test/insim/run-insim.py --resume             # continue the latest run after a crash
python test/insim/run-insim.py --verify             # judge the latest run's results again, without DCS
python test/insim/run-insim.py --lua PATH           # the Lua 5.1 interpreter
```

`run-insim.py` is the driver: it sends each step of a scenario to the mission through hotload's
mailbox, and waits for the answer. It:

1. prepares the Skynet script the mission loads, `build/insim/skynet-iads-insim.lua`. By default it
   rebuilds it from `skynet-iads-source/` unless the file is already the build of the current
   sources; `--skynet FILE` copies that file instead, and the next default run rebuilds;
2. prepares the mission DCS opens (see *The mission*);
3. waits for a mission to answer. If DCS is not running one, it says which files to run:
   `test/insim/miz/insim-ca-main.miz` or `test/insim/miz/insim-pg-llod.miz`. **That is the manual
   step.** Later, if the mission stops answering while a command is in flight, it says "paused, or
   DCS is down" and waits: it never concludes anything from silence;
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

### Writing a scenario

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
	mission = "insim-ca-main",
	timeout = 120,      -- sim seconds, for each phase command: setup, run, teardown, cleanup
}
```

**The phases.** The driver sends each as its own mailbox command: `setup`, then `run` only if setup
ended normally, then `teardown` whatever happened, then the engine's own cleanup. A raise in setup
skips `run`; `teardown` and cleanup are still sent. A raise in any other phase fails that phase
only. Each phase file receives `ctx` (`local ctx = ...`) and is read from disk by its command, so an
edited phase is live at the next run. Do not wrap scenario code in `pcall`: Lua 5.1 cannot hold a
pause across one.

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

`invalid` is for a precondition the scenario could not set up: it is never a `pass` or a `fail`. A
teardown or cleanup that fails adds a warning, since the next scenario may start from a dirty world.

**`ctx`**, the one table passed to each phase. It lives between the phases of a scenario and is
dropped by cleanup.

| Member | Does |
|---|---|
| `ctx.name`, `ctx.mission` | the folder's name, and `mission` from `scenario.lua` |
| `ctx.state` | free: whatever `setup` hands to `run` |
| `ctx.invalid(reason)` | ends the phase as `invalid` |
| `ctx:add(role, zone, copyName)` | adds the mission's fixture `FIXTURE-<scenario>-<role>`, else the catalogue's `FIXTURE-<role>`, as `<scenario>/<role>` and returns the group or static; cleanup destroys it. With `zone`, the copy stands on that trigger zone's centre, its route moved with it; with `copyName`, it is `<scenario>/<copyName>`, for several copies of one fixture |
| `ctx:track(object)` | something the scenario spawned itself, destroyed by cleanup with the rest |
| `ctx:onCleanup(fn)` | `fn` is called by cleanup, through `Hotload.callOnMain`, last registered first |

The Skynet layer, loaded with `Hotload.load("insim-skynet")`:

| Function | Does |
|---|---|
| `iads(ctx, configure)` | creates an IADS, registers its deactivation with `ctx:onCleanup`, adds the units `ctx:add` put in whose role starts with `SAM` or `EW`, calls `configure(iads)` if given, and activates it |

```lua
-- setup.lua
local ctx = ...
ctx:add("SAM-SA6")
ctx:add("EW")
ctx.state.iads = Hotload.load("insim-skynet").iads(ctx)
```

Two more libraries, loaded the same way:

| Library | Function | Does |
|---|---|---|
| `insim-watch` | `start(ctx, probes, interval)` | samples each probe (`{ name = function() return value end }`) every `interval` seconds and keeps the values it goes through, so a scenario judges a transition rather than an end state. A probe that raises is recorded as `"error: …"`; cleanup stops the watch |
| | `watch:waitFor(name, values, timeout)` | true once the values of `name` start with `values` |
| | `watch:sequence(name)`, `watch:report()` | one sequence, or all of them for `run` to return |
| `insim-world` | `pointFrom(zone, bearing, km)` | a point measured from a zone's centre |
| | `spawnAircraft(ctx, spec)` | an aircraft on a route, tracked for cleanup, with the flags `immortal`, `invisible`, `holdFire`, `ignoreThreats`. Its tasks go on `via`, a point just after the start: DCS ignores a task on an air-started group's first waypoint and starts one on a later waypoint only when it is reached |
| | `attackTask(group, weaponType)` | an `AttackGroup` task, `weaponType` from the Mission Editor's `weaponTable` |
| | `recordShots(ctx)`, `fired(shots, unit)` | every shot fired until cleanup, and how many one unit fired: a scenario whose attacker never fired is `invalid`, not `fail` |
| | `clearWrecks(zone)` | removes the debris inside a zone |

**Rules for the code of a phase.**

- Every wait is bounded: `Hotload.waitFor(fn, timeout)`, never an open-ended loop. A phase that still
  hangs is stopped by the driver once its `timeout` has passed, and recorded as `fail`.
- Anything that arms a timer or registers an event handler goes through `Hotload.callOnMain(fn)`; a
  timer armed from a run crashes DCS once the run has ended. `iads(ctx)` does it for the IADS.
- Log with `Hotload.log`: it stamps each line in `dcs.log` with the command's name, which carries the
  scenario and the phase.
- Shared code is a library in `test/insim/dcs-hotload/user-lib/`, loaded where it is used with
  `Hotload.load("name")`. A helper two scenarios need goes there, not copied between them.

**A fixture** is a late-activated group or static in the mission. `FIXTURE-<scenario>-<role>`
belongs to one scenario and stands where its geometry needs it; `FIXTURE-<role>` is the catalogue's,
any scenario's, copied into a trigger zone. A copy is added under the same name each run, so adding
over a live leftover replaces it, and setup cleans up what an aborted run of the same scenario left.
The IADS looks only at the prefix `<scenario>/`. A static cannot be late-activated: the catalogue's
stand in the mission from the start, away from every zone.

**The tiers.** `minimal` is the short run, the one worth making before a pull request; `full` adds
the scenarios not wanted every time. A scenario with no `tier` runs only when named. The `selftest-*`
scenarios have none: they prove the engine's own paths (a raise, `invalid`, a hang, a failing
`verify.lua`) and would keep any tier from exiting 0.

### The mission

| Mission | Map | Holds |
|---|---|---|
| `insim-ca-main` | Caucasus | the catalogue and its zones, and every scenario but one |
| `insim-pg-llod` | Persian Gulf | `last-line-of-defence`, whose geometry rests on that map's terrain |

`test/insim/miz/` holds two files per mission:

- `<mission>.template.miz`, committed, is the reference. It holds a placeholder where the absolute
  path of hotload goes.
- `<mission>.miz`, git-ignored, is the working copy DCS opens. `run-insim.py` writes it before every
  run: when it is missing, when the template has changed, or when the checkout has moved. Do not edit
  it.

Scenarios name their mission (`mission = "insim-ca-main"`); a mission is known by its sortie name.
The driver runs the scenarios of the mission DCS is running, and lists the others as skipped, naming
the mission they need: a full run is one run per mission.

At mission start three actions run: the first sets `BASE_HOTLOAD_PATH`, the only absolute path in the
mission; the second loads hotload from it; the third loads the Skynet script under test, found
relative to hotload's folder. Nothing is embedded, so a change to the code never needs the mission
rebuilt. A later change to the mission starts from the template, never from an empty mission.

### Hotload

`test/insim/dcs-hotload/` is dcs-hotload, committed as released, so a run needs nothing beyond the
setup above. Its shipped files (`dcs-hotload.lua`, `README.md`, `LICENSE.md`, `bin/`, `examples/`)
are never edited here; its own `README.md` is the reference for `Hotload.*`.

What belongs to the suite stays:

- `user-lib/`: `insim.lua`, the engine's side in the mission; `insim-watch.lua` and
  `insim-world.lua`, the libraries above; and `insim-skynet.lua`, the Skynet layer, the only one that
  names Skynet;
- `user-inbox/` and `user-outbox/`, the mailbox, git-ignored.

**To upgrade**, replace the shipped files and folders with those of the new release and leave
`user-lib/`, `user-inbox/` and `user-outbox/` alone.

### Tests of the suite itself

They are in `test/insim-tools/`, and run without DCS: the driver with
`python test/common/run.py test/insim-tools`, the mission-side Lua, on the stub, with
`lua5.1 test/common/run.lua test/insim-tools`.

## Files

| File | Purpose |
|------|---------|
| `common/run.lua`, `common/run.py` | the runners, one per language |
| `common/luaunit.lua` | luaunit, vendored unmodified |
| `common/dcs-stub.lua` | a fake DCS scripting environment: `coord`, a controllable `timer.scheduleFunction` for the real `SkynetIADSUtils` scheduler, and recorders for what the code prints — `dcsStub.logs` for `env.*`, `dcsStub.screenText` for `trigger.action.outText`, `dcsStub.radioItems` for `missionCommands` |
| `common/dcs-fixtures.lua` | reusable fixtures: SAM group builders (positioned, coalition-aware, movable), connection nodes, the EW radar builders (a bare unit, or one in a group for prefix discovery) and the AWACS unit builder, hostile aircraft groups, the IADS-contact factory |
| `common/skynet-loader.lua` | loads `skynet-iads-source/*.lua` in the order of `build-tools/listToMerge.txt` |
| `common/report-test-coverage.lua`, `common/test-coverage-floor.txt` | the test-coverage report and its floor |
| `lua/test_compiled_script.lua` | builds the compiled script into `build/test/` and runs it against the stub as one chunk, which loading the sources one by one cannot check; skips, saying so, when no Python runs |
| `lua/check-unit-types.lua` | the check of `samTypesDB` against the DCS database |
| `*/test_*.lua`, `*/test_*.py` | the suites, each self-contained and self-executing |
