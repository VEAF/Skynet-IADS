# An in-sim anti-regression suite, run through dcs-hotload

Status: in-progress

## The problem

Nothing checks, in DCS, that a change to `skynet-iads-source/` has not broken what the simulator does with Skynet.

- `test/lua/` runs on a stub. It covers the logic, not whether DCS calls the code, what real radars report, or how real groups and statics are composed. It stays as it is.
- `unit-tests/skynet-unit-tests.miz` is the legacy in-sim suite. Half of it mocks DCS away (`getDetectedTargets`, `getAge`, `informOfContact` overridden), so it proves little a stub cannot. It is read off the screen. It is to be replaced, then removed. Its tests that read the real world are worth rewriting.
- `build-tools/run-smoke.py` sends one-word checks through dcs-bridge. It stays, as a complement.
- `feat/insim-tests` built a tier before dcs-hotload existed: its own coroutine scheduler, wait loop and F10 menu. It is to be dropped. Its fixture and isolation design is reused below.

The SkynetMunitionTests campaign (`D:\Projects\DcsMissions\SkynetMunitionTests`, 300+ runs through hotload) showed that hotload can drive long series of DCS tests reliably. Each test there was a free-standing script (`t1.lua` … `t8.lua`) that repeated the same scaffolding: a results writer, an event handler, a tracking loop, cleanup, a verdict. Each wrote its own markdown table. Each series had its own bash driver.

## The goal

A suite a contributor runs before a pull request that touches `skynet-iads-source/`, as they run `test/lua/`:

1. open the test mission in DCS (the one manual step);
2. run one command;
3. read a summary: every scenario `pass`, `fail`, `invalid` or `crashed`, and an exit code.

No agent is needed. It is recommended in `CONTRIBUTING.md`, not required: CI has no DCS.

**This piece of work is the plumbing**: the engine, the Skynet layer, the test mission and the driver, proven by the scenarios in *The proving scenarios*. Choosing and writing the anti-regression scenarios is the next piece of work.

### What success looks like

- The command runs the proving scenarios against the current build, unattended once the mission is open, and prints a summary.
- A scenario that fails, raises, or times out is reported as such, and the run carries on to the next one.
- A run interrupted by a DCS crash resumes where it stopped.
- A scenario is a folder of short files that declare setup, stimulus and verdict, without scaffolding.

### Anti-goals

- A green run against a stale build. The run checks the mission's build against the file on disk first, and refuses on a mismatch.
- A verdict that is really a broken precondition. A scenario that cannot set up what it tests reports `invalid`, never `fail` or `pass`. Both wrong conclusions of the munition campaign came from an unchecked precondition.
- Engine code that knows about Skynet. The engine starts in this repository, but must be extractable as is, for other DCS projects or into dcs-hotload.
- A driver core that assumes a test suite. The driver is meant to become hotload's own, the one a campaign like SkynetMunitionTests uses instead of writing a bash driver per series. Its core runs a list of commands, stores each result table as it comes back, stops a hung run, resumes, and reports progress. The verdict vocabulary (`pass`, `fail`, `invalid`, `crashed`) and the scenario chain are the test layer, above it. What only a campaign needs (confirmation re-runs, measurement columns) is not built now.

## What to build

### The layers

| Layer | Knows about | Holds | Meant to move to hotload |
|---|---|---|---|
| **driver core** | the mailbox | runs a list of mailbox commands, records each result as it comes back, resumes, stops a hung run, reports progress | yes |
| **test layer** | the driver core, DCS | the scenario format and the setup → run → teardown → cleanup chain; in the mission, `ctx` and the cleanup; the verdicts | yes |
| **Skynet layer** | the test layer, Skynet | in the mission, `ctx:iads`; outside, preparing the Skynet script under test | no |
| **scenarios** | all of the above | one folder each | no |

The driver core and the test layer together are **the engine**. Neither has a Skynet name in it, and their files could be copied into another project and work. The chain lives in the test layer, never in the core: a campaign like SkynetMunitionTests would use the core with a policy of its own, and no test layer.

### A scenario

One folder per scenario, under `test/insim/scenarios/`, with normalized file names:

```
test/insim/scenarios/smoke-iads-builds/
  scenario.lua     -- metadata only
  setup.lua        -- add fixtures, create the IADS; may call ctx.invalid(reason)
  run.lua          -- may wait; returns its measurements, or calls ctx.invalid(reason)
  teardown.lua     -- optional; always runs
  verify.lua       -- outside DCS: judges run's measurements with luaunit
```

```lua
-- scenario.lua
return {
  tier = "minimal",                  -- "minimal" or "full"
  mission = "insim01",               -- test/insim/miz/insim01.miz
  timeout = 120,                     -- sim seconds, for setup and run each
}
```

- The folder's name is the scenario's name. The driver knows which phases a scenario has from its file names, without running Lua.
- Each phase file receives `ctx` and is re-read from disk by its command, so an edited phase is live at the next run, without a mission restart (only the Skynet script needs one).
- **Nothing else goes in a scenario's folder.** Shared code is a library in hotload's `user-lib/`, loaded where it is needed with `Hotload.load("name")` (read fresh once per run). There is no list of libraries in `scenario.lua`: `Hotload.load` at the point of use is the one place a dependency is named, and a missing library already fails its phase with a clear message. Helpers private to one scenario are not provided for until a scenario proves the need.

**Measured in DCS, judged outside.** Nothing in the mission asserts. `run.lua` returns a table of measurements (`{ sam = 1, ew = 1 }`, `{ detected = true, after = 23.5 }`); a wait that times out is a measurement (`detected = false`), not an error. The driver records it, then runs `verify.lua` on it with plain Lua 5.1 and luaunit (`test/lua/luaunit.lua`, which cannot load in the mission anyway: `require` and `os` at its top level):

```lua
-- verify.lua
return function(result, lu)
  lu.assertEquals(result.sam, 1)
  lu.assertEquals(result.ew, 1)
end
```

Recorded results can be judged again without DCS: `run.py --verify` re-runs the `verify.lua` files on the latest results, after one is edited.

Every wait a scenario writes is bounded: `Hotload.waitFor(fn, timeout)`, never an open-ended loop.

### `ctx`, a scenario's context

`ctx` is the one table the engine passes to each phase. Each phase is a separate mailbox command, so a local of `setup` is gone when `run` starts: `ctx` lives in a guarded global keyed by the scenario's name, created by the setup command, dropped by the cleanup command.

It is **normalized, and free beyond that**. The line is what the engine relies on: cleanup and verdicts depend on the members below, so they are fixed; what a single scenario needs goes in `ctx.state`.

**The test layer's members** (no Skynet in them):

| Member | Does |
|---|---|
| `ctx.name`, `ctx.mission` | the folder's name, and `scenario.lua` |
| `ctx.state` | free, the scenario's own: whatever `setup` passes to `run` |
| `ctx.invalid(reason)` | ends the phase as `invalid`: raises a string with a mark the engine recognizes. Hotload writes an error with `tostring`, so it must be a string |
| `ctx:add(fixtureName)` | adds a fixture from `env.mission` under a scoped name, records it, returns the group or static |
| `ctx:onCleanup(fn)` | a function the cleanup command calls, through `callOnMain`, last registered first |

What `run.lua` returns is the scenario's result, reported beside its verdict (a detection time, a count).

**The cleanup command** destroys every recorded entity still alive, then calls the `onCleanup` functions. That hook is what keeps the engine free of Skynet: the Skynet layer cleans up what it creates by registering there.

**The Skynet layer**, on top:

| Member | Does |
|---|---|
| `ctx:iads(name)` | creates an IADS through `callOnMain`, and registers its deactivation with `onCleanup` |

**What goes in `ctx`.** Only what has to know the scenario: its record, its state, its verdict. A helper that needs none of that — clearing wrecks in a zone, a bearing between two points — is a plain function in a `user-lib/` library, used with `Hotload.load`.

**What grows, and where.** A helper two scenarios need — an aircraft spawned on a leg, a HARM fired at a site, a munition tracked — goes into the layer it belongs to, never copied between scenarios. The munition campaign is the counter-example: `t1` to `t8` each wrote their own launchers and tracking. Only the members above are built in this work.

### A scenario is a string of mailbox commands

The driver runs each phase as **its own mailbox command**, in this order:

1. **setup** — the scenario's `setup`;
2. **run** — only if setup ended `done`;
3. **teardown** — the scenario's `teardown`, if it has one, **whatever happened before**;
4. **cleanup** — the engine's own, always sent last (see *`ctx`*).

Each command is its own hotload run, so a raise in one fails only that command (hotload writes `fail` and the message in its outbox) and the driver still sends the next. No `pcall` around the scenario's code, which could not hold a pause in Lua 5.1. What a phase leaves for the next lives in `ctx`.

The driver builds the verdict from the commands' outcomes:

| What happened | Verdict |
|---|---|
| setup and run `done`, and `verify.lua` passes | `pass` |
| setup and run `done`, and `verify.lua` fails | `fail`, with luaunit's message |
| `ctx.invalid(reason)` in setup or run | `invalid`, with the reason |
| a raise in setup or run | `fail`, with the message |
| setup or run past its `timeout` | `fail`, "timed out after N s" |
| teardown or cleanup `fail` | the verdict above, plus a warning: the next scenario may start from a dirty world |

**A phase that hangs** (a wait that never ends, despite the rule above) is stopped by the driver: past the phase's `timeout` (teardown and cleanup get the same), it sends `Hotload.stop("inbox/<name>")` as another mailbox command, records the timeout, and goes on to teardown. Runs take turns, so a hung run does not block the commands that stop it. The timeout is counted in sim time, so a paused DCS does not set it off: the driver asks the mission for `timer.getTime()` through the mailbox, or, if that proves impractical, waits in real time with a generous margin.

**Hotload is committed in this repository, at a pinned release**: the release's `dcs-hotload/` folder, extracted as is, with its version stated beside it: **2.0.0**, the first with `Hotload.stop`. A run depends on no external tooling — no plugin, no setup script, no download. The files a release ships (`dcs-hotload.lua`, `README.md`, `LICENSE.md`, `bin/`, `examples/`) are never edited here: a change goes to hotload's repository, and an upgrade replaces those files only. The folders that belong to the mission stay: `user-lib/`, where the engine and the Skynet layer live, and the mailbox folders `user-inbox/` and `user-outbox/`, git-ignored. Scenarios and the Skynet script under test are reached from `Hotload.root` by relative path.

Anything that arms a timer or registers an event handler (creating or activating an IADS, `world.addEventHandler`) goes through `Hotload.callOnMain`. A timer armed from a run crashes DCS once the run has ended.

### The driver, outside

One command, a Python script (stdlib only), which also needs Lua 5.1 for `verify.lua` (`lua5.1` on `PATH`, Lua for Windows at its default path, or `--lua`), for example:

```
python test/insim/run.py                      # the minimal tier
python test/insim/run.py --tier full          # everything
python test/insim/run.py smoke-iads-builds    # by name, as test/lua/run.lua filters
python test/insim/run.py --verify             # judge the latest results again, without DCS
```

It:

1. prepares the Skynet script the mission loads (see *The Skynet script under test*);
2. prepares the mission DCS opens (see *The test mission*), and if the mission does not answer, says which file to open in DCS and waits for it;
3. checks that the mission loaded the script as it now is on disk — or stops and says to restart the mission;
4. runs each scenario as its string of mailbox commands, each named `<scenario>-<phase>-<unique>` (hotload stamps every `Hotload.log` line with it, so a scenario logs with `Hotload.log` and no wrapper), runs `verify.lua` on what `run` returned, and prints a line per scenario as it ends;
5. records each result as it arrives, and the command in flight, so a run resumes after a crash. What to do with the command in flight is the layer above the core's call: the test layer records its scenario `crashed`, which counts as a failure, and does not re-run it, since a scenario that crashes DCS every time would otherwise loop;
6. writes the summary to the terminal and a report to a git-ignored results folder, and exits non-zero if anything was not `pass`.

It does not stop at the first failure.

**Paused or dead.** Hotload's mailbox polls on a DCS timer, so a paused mission does not answer either, and silence alone tells nothing. The driver never decides on silence: while the mission does not answer, it waits and says so ("no answer: paused, or DCS is down — restart the mission to resume"). A crash is established from sim time, which restarts from 0 with the mission: the mission answers with a sim time earlier than the in-flight command's start, or a stop finds no such run. A restart that has already run past that start goes unseen until then; that is accepted, since a crash compromises the run anyway. Scenarios run one at a time, never in parallel: several engagements at once froze DCS in the munition campaign.

### The Skynet script under test

The test mission loads a script of its own, `build/insim/skynet-iads-insim.lua` (git-ignored, under the existing `/build/`), never `demo-missions/skynet-iads-compiled.lua`: a test build and the shipped artifact cannot be mixed up.

- **By default**, the Skynet layer rebuilds it from `skynet-iads-source/` with the repository's build, **unless the file is already the build of the current sources**: it records which sources produced the file and what the file was, and rebuilds when either no longer matches. The build stamps a `BUILD TIME` to the minute, so an unconditional rebuild would make every run look like a new script; and a file left by a forced run is rebuilt at the next default run, never tested by mistake.
- **Forced**: `run.py --skynet <file>` copies the given script there instead of building — a release build, or a branch build such as the munition campaign's `skynet-iads-evasion-off.lua`.
- **Loaded by the Skynet layer**: the mission's third MISSION START action calls it, and it keeps the text it loaded.
- **Stale check**: before running anything, the driver has the Skynet layer compare that text with the file on disk; on a mismatch it says to restart the mission and runs nothing.

### The test mission

- Caucasus, the free map. One neutral Game Master slot.
- At mission start: load hotload, then the Skynet script under test, both **from disk, not embedded**. A change to the code then needs a build and a mission restart, never a mission rebuild.
- **One absolute path, in one variable.** As in `D:\Projects\DcsMissions\GroundStrikeSandboxSyria` (`FgDynamicPath`), the first MISSION START action is a DO SCRIPT that sets a Lua global, and only that: `BASE_HOTLOAD_PATH = [[<path>]]`. The next one loads hotload from it, `assert(loadfile(BASE_HOTLOAD_PATH .. "/dcs-hotload.lua"))()`. The third has the Skynet layer load the Skynet script under test, found relative to `Hotload.root`. Nothing else in the mission names a path.
- **Two files per mission, side by side in `test/insim/miz/`.**
  - `insim01.template.miz`, committed, is the reference. It holds a placeholder in `BASE_HOTLOAD_PATH`, and it is the one edited in the Mission Editor (a placeholder does not stop the editor, only the run).
  - `insim01.miz`, git-ignored, is the working copy DCS opens. Its `BASE_HOTLOAD_PATH` holds this checkout's path.
- **Several missions are possible.** There is one in this work, `insim01`, but nothing assumes it is the only one: each scenario names its mission (`mission = "insim01"`), and a mission is known by its own name, the Mission Editor's sortie, which the test layer reads (`env.getValueDictByKey(env.mission.sortie)`). The driver runs the scenarios of the mission DCS has open, and lists the others as skipped, naming the mission they need.
- **The driver keeps the working copy right**, before every run, at the hotload level since it is only about where hotload is. It creates the copy when missing; it rewrites it when the template has changed or the path is not this checkout's; otherwise it leaves it alone. No separate preparation script. `BASE_HOTLOAD_PATH` is the only thing it checks or writes. DCS stores each action's text twice in the `mission` file (`trigrules` and the compiled `trig.actions` string): both are rewritten.
- Trigger zones where scenarios need them. A scenario uses none, one or several, by name; the engine does not assume any.
- Fixtures late-activated, named `FIXTURE-<Scenario>-<Role>`. `ctx:add` reads a fixture's table out of `env.mission` and adds it as `<scenario>/<Role>`: the same name every run, so adding over a live leftover replaces it. `ctx:iads` builds from the prefix `<scenario>/` only. That prefix never matches a template, which may matter: Skynet's `addEarlyWarningRadarsByPrefix` has no check for inactive units (`addSAMSitesByPrefix` has one), and whether DCS lists late-activated units there is not measured, and the `/` keeps a scenario whose name begins another's out of its prefix.
- First built with the `dcs-missions` plugin of dcs-agent-skills (`building-dcs-missions`), from the empty Caucasus template it embeds. Florent then adjusts positions in the Mission Editor. From then on `insim01.template.miz` is the reference: a later scripted change uses it as its base, never the empty template, or the adjustments are lost.

Isolation, from `feat/insim-tests`' design:

| Operation | On a live entity | On an exploded one |
|---|---|---|
| **add** under the same name | replaces it | a new one beside the wreck |
| **destroy** | removed, no wreck | no effect |
| `removeJunk` over a zone | — | wreck cleared |

So `ctx:add` replaces a live leftover, the cleanup's `destroy` leaves no wreck, and wrecks from explosions are cleared by a `clearWrecks(zoneName)` helper in a `user-lib/` library, which a scenario calls on the zones it uses.

### The proving scenarios

1. **Instant**: the IADS builds from the mission's fixtures, and the counts of SAM sites and EW radars match what is placed. Taken from `testCaclulateNumberOfSamSitesAndEWRadars` in `unit-tests/test-skynet-iads.lua`.
2. **Waiting**: something that needs sim time and a real DCS answer. The minimum is an EW radar that detects an aircraft the scenario spawns, within a timeout. A failing variant, whose `verify.lua` rejects what `run` measured, proves that a `fail` reaches the report.

Plus scenarios that prove the engine's own paths, kept out of the tiers and run by name, so that a tier can exit 0:

- **broken**: raises in `setup`; `run` is skipped, `teardown` and cleanup still run, the run carries on;
- **invalid**: calls `ctx.invalid` in `setup`; reported `invalid`, with its reason;
- **hanging**: a `run` that waits past its `timeout`; the driver stops it with `Hotload.stop`, reports `fail` "timed out", and teardown runs.

**Resume** is checked by hand once: DCS killed during a scenario, the mission restarted, the same command run again; the scenario in flight is reported `crashed`, the ones before it are not re-run.

### Documentation

- `test/insim/README.md` is the suite's door: setup once (`MissionScripting.lua`), how to run, how to add a scenario.
- `CONTRIBUTING.md`'s table of suites gains a row, recommending a run before a pull request that touches `skynet-iads-source/`.
- `CLAUDE.md`'s rule "never edit a `.miz` by hand; `miz-suite.py` is what writes into one" gains its exception: the test mission's template is edited in the Mission Editor, and its working copy is written by the driver.
- A note in `miz-suite.py`'s header that the test mission is not one of its archives.

## Decisions

| Decision | Turned down | Why |
|---|---|---|
| Built on dcs-hotload | `feat/insim-tests`' own scheduler and F10 menu | hotload already has the waits, the main-state executor and the mailbox, proven over 300 runs |
| The mission loads a dedicated script, `build/insim/skynet-iads-insim.lua`, from disk | embedding it at build time; loading `demo-missions/skynet-iads-compiled.lua` | no mission rebuild per change; a script can be forced for a specific test without touching the shipped artifact; the stale check covers a rebuild during a session |
| The compiled deliverable, not the sources one by one | loading `skynet-iads-source/` in `listToMerge.txt` order | it saves only a two-second build, adds a load path that can differ from what users get, and does not allow a reload within a session: Skynet arms long-lived timers |
| One mailbox command per phase, strung by the driver | one in-sim run that loops all scenarios; a command per scenario running its phases as child runs | a raise fails only its phase and teardown still runs, with hotload as it is; a crash costs one scenario, and the driver can resume |
| A Python driver, talking to the mailbox itself | bash, or wrapping `bin/hotload.sh` | dcs-agent-skills chose Python for all its tooling, and `hotload.sh` is to be converted to Python; this driver's mailbox client is the seed of that conversion. It also parses Lua result tables and writes a report, and the repository's tooling is Python, tested in `test/python/` |
| Measured in DCS, judged outside by luaunit | assertions in the mission | luaunit cannot load in the mission; recorded results can be judged again without DCS |
| A report in Markdown | JUnit XML | no reader needs a machine format yet |
| The driver keeps a git-ignored copy of the mission, whose `BASE_HOTLOAD_PATH` is this checkout's | a config file under `Saved Games\DCS\Config\`; a step in `miz-suite.py build` | one command, nothing to set up by hand, and no separate step anybody has to remember |
| Hotload committed at a pinned release | deployed by its setup script or the Claude Code plugin into a git-ignored folder | a contributor runs the suite with nothing but the repository, DCS and Python |
| Waits bounded by `Hotload.waitFor`; a hung phase stopped by the driver with `Hotload.stop` | a timeout on each inbox command, in hotload | the driver already knows how long it will wait; one primitive covers every way a run can hang |
| The mission built by `dcs-missions` from its Caucasus template, then adjusted by hand | a generator in `miz-suite.py`; a mission made entirely in the Editor | the plugin already builds and checks missions; positions are a visual call |

## Left to the builder

- Where hotload is vendored (`test/insim/dcs-hotload/` is a guess). The engine and the Skynet layer live in the vendored hotload folder's `user-lib/` (the mission's own folder, not part of hotload's release): their file names, and the signatures of the `ctx` members (what they do is fixed above).
- The placeholder's form, how "the template has changed" is detected, and the form of the driver's probe of the mission (its name and sim time).
- How the build writes `build/insim/skynet-iads-insim.lua`: an output-path parameter on `build-compiled-script.ps1`, or a copy of the deliverable after a normal build. How the Skynet layer records which sources produced the file and what the file was, to tell whether it is still the build of the current sources.
- What of `feat/insim-tests`' code to port (`insim-test-tools.lua`'s `addFromMission`, `addAirFromMission`, `offsetFrom`, and their offline tests), after reading it: what fits the hotload base comes over with its tests, the rest is rewritten.
- The report's layout, and what the resume key is.
- Offline tests for the engine and driver, in `test/lua/` and `test/python/`, as far as a stub reaches.

## Out of scope

- Writing the anti-regression scenarios beyond the proving ones: engagements, HARM defence, go-live and go-dark loops, the `unit-tests/` port. The next piece of work.
- Removing `unit-tests/`.
- Time acceleration: whether Skynet and DCS's AI behave the same at ×4 is to be measured first.
- CI: GitHub runners have no DCS.
- Moving the engine into dcs-hotload or another module.
- Any change to `test/lua/` or `run-smoke.py`.
- Changing `build-tools/miz-suite.py` beyond a note. The test mission is not one of its archives, and it is likely to go with `unit-tests/`.
