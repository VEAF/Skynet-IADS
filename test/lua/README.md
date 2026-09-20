# Standalone Lua tests

Logic tests for the Skynet-IADS source, run on a plain Lua 5.1 interpreter —
no DCS, no mission editor. This is where new **logic** tests go.

For behaviour that genuinely needs the simulator (terrain elevation, radar
detection geometry, real in-game events) see the in-sim functional/smoke
suites in `unit-tests/*.miz`.

## Run

Where `lua5.1` is on PATH (Linux, macOS, CI):

    lua5.1 test/lua/run.lua                          # all suites
    lua5.1 test/lua/run.lua contact                  # suites whose filename contains "contact"
    lua5.1 test/lua/test_skynet_iads_contact.lua     # one suite directly

On Windows without `lua5.1` on PATH, use the "Lua for Windows" binary
(`C:\Program Files (x86)\Lua\5.1\lua.exe`).

PowerShell needs the call operator `&` because the command line starts with a
quoted path:

    & "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua

cmd.exe takes the quoted path as-is:

    "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua

## Test coverage

How much of `skynet-iads-source/` the suite actually executes. Beware the word: in Skynet,
*coverage* is what an early warning radar does to a SAM site — this is **test**
coverage, and the two never travel alone.

Run the suite with the hook, then report. Both commands run from the repository
root, because that is where `.luacov` and the stats file live:

    SKYNET_TEST_COVERAGE=1 lua5.1 test/lua/run.lua
    lua5.1 build-tools/report-test-coverage.lua

In PowerShell, with the Lua for Windows binary — which already ships `luacov`, so
there is nothing to install:

    $env:SKYNET_TEST_COVERAGE = "1"
    & "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua
    & "C:\Program Files (x86)\Lua\5.1\lua.exe" build-tools\report-test-coverage.lua
    Remove-Item Env:\SKYNET_TEST_COVERAGE

`SKYNET_TEST_COVERAGE` unset — the normal case — runs the suite with no debug hook
installed, exactly as before.

The report prints a per-file summary, worst first, then the total and a verdict.
The per-line detail lands in `luacov.report.out`, where a `****0` marks a line the
suite never ran. What counts and what does not is in `.luacov` at the repository
root, with the reasons; the same two commands run in CI on every pull request.

**There is a floor**, in `build-tools/test-coverage-floor.txt`, and CI fails below
it — exit 1, distinct from exit 2, which means the measurement did not happen at
all. The floor only ever goes up: when your tests push the figure past it, raise it
in the same pull request. The report tells you when it can be raised and to what.

## What stays uncovered, and why

Measured at **94.63%**. Everything reachable is covered except the four entries below, so
nothing is left in the report with nobody having looked at it. Re-check this list whenever the
figure moves for a reason you did not expect.

**`skynet-iads-abstract-radar-element.lua` — 89 lines, and porting the legacy suite could not
close them,** because the legacy suite never covered them either. Four blocks:

- **`informOfHARM()`** — the geometry and the decision behind a HARM evasion: aspect, distance,
  time to impact, whether to remember the track as a HARM, whether to wake the point defences,
  whether to go dark and for how long. The largest single block left in the project.
- **`weaponFired()`** — the `S_EVENT_SHOT` handler that puts a launched missile on the
  missiles-in-flight list. The list itself is covered; what fills it is not.
- **The five ammunition helpers behind `shallIgnoreHARMShutdown()`**
  (`hasRequiredNumberOfMissiles`, `hasRemainingAmmoToEngageMissiles`,
  `hasEnoughLaunchersToEngageMissiles`, `pointDefencesHaveRemainingAmmo`,
  `pointDefencesHaveEnoughLaunchers`). The truth table above them is covered, by a test that
  mocks all five away — which is what the legacy test did too, and why they stay dark.
- **`addHARMDecoy()`, the deprecated `setIgnoreHARMSWhilePointDefencesHaveAmmo()`,
  `calculateImpactPoint()`'s `land.getIP` call, and the debug-log branches.**

That is work for a lot of its own, not for the port: writing these tests means deciding what
`informOfHARM` should do, not recording what a legacy test already said.

**Continuation lines — 34 lines, and no test can ever reach them.** The second and later lines of
a multi-line concatenation or `return`. Lua 5.1 attributes the whole expression to its first
line, so no debug hook fires on the rest. Nineteen of them are in the logger's status page, where
every field sits on its own line; the others are scattered. Counting them as work left to do is
how a coverage target becomes unreachable for no reason.

**`inheritsFrom`'s `class()`, `isa()` and the default `create()` — 11 lines.** Dead inside this
repository: all ten classes built with `inheritsFrom()` define their own `create`, and
`isa`/`class` appear nowhere outside their own definition — checked across `skynet-iads-source`,
`test/lua` and `unit-tests`. They are still methods on every Skynet object, and the artifact is
vendored by VEAF-Mission-Creation-Tools, so a mission script may be calling them without this
repository knowing. Deleting undocumented public surface from a vendored deliverable is a
decision for VEAF, not a side effect of a test-coverage ticket.

**`SkynetIADSUtils`'s `maxn` fallback — 5 lines.** It runs only where `table.maxn` is absent,
which means Lua 5.2 and later. DCS and this runner are both 5.1, so the shim cannot execute here.
It is not dead: it is what keeps the file loadable under a newer interpreter.

## Ported suites

**Six legacy suites are gone**, both copies — the loose `unit-tests/*.lua` and
the one baked into `skynet-unit-tests.miz`: `abstract-dcs-object-wrapper`,
`abstract-element`, `contact`, `harm-detection`, `jammer` and `sam-site`. Every
test each of them asserted runs here, none of them asserted anything only DCS
can answer, and two copies that drift are worse than one. David's call,
2026-09-19; done by `CHORE-PROFESSIONALIZE-THE-REPO` ticket 04.

`moose-a2a-connector` stays: one of its three tests is ported and the other two
enumerate the 17-EW / 17-SAM demo world.

`test_skynet_iads.lua` is the `SkynetIADS` suite. It carries the narrow
regression test for the `3a94937` fix
(`testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage`, ported straight off
the real `addEarlyWarningRadar`/`addSAMSite`/`activate` API) and, since
`CHORE-TEST-COVERAGE-FLOOR` ticket 05, the network facade: the getters
`documentation/api.md` shows on the `SkynetIADS` object, the enrolment calls and
what a mistyped group name gets you, the radio menu, and `getCoalitionString`.
Three of those tests pin behaviour that is probably wrong and say so where they
do -- they record what the code does today so that changing it is a decision
somebody takes on purpose. It does not port the rest of
`unit-tests/test-skynet-iads.lua`; the `.miz` copy stays the in-sim
functional/smoke suite for the rest of the `iads` class.

Five suites have no `unit-tests/` ancestor — they were written with the work
they cover. Two came with `FEAT-LAST-LINE-OF-DEFENSE`:
`test_skynet_iads_last_line_of_defence.lua` (18 tests) and
`test_skynet_iads_coverage_refresh.lua` (13 tests). Almost every test in them
drives the real `SkynetIADS.evaluateContacts()` or `refreshRadarCoverage()`
rather than calling the wake-up directly: the failure mode that feature had to
avoid is a wake-up that is perfectly tested and never called by the cycle.

Two more came with `FIX-STALE-HARM-SILENCE`:
`test_skynet_iads_harm_silence_cleanup.lua` (5 tests), for issue #3 — a site
cleaned up mid-HARM-evasion that never came back — and
`test_skynet_iads_bulk_re_add.lua` (5 tests), for the discarded elements a
`*ByPrefix` call left wired into the coverage graph. Same principle: they drive
the doors a mission uses (network designation, the last line of defense,
`reportContact`; a battery going autonomous when its radar leaves the IADS) and
only then assert state.

`test_skynet_iads_logger.lua` (26 tests) came with `CHORE-TEST-COVERAGE-FLOOR`
ticket 03, for the status page the `skynet-runtime-debug` skill reads back out of
a `dcs.log`. It drives the real `printSystemStatus()` over a network whose damage
is known, and asserts each line **field by field** — names, order and values —
rather than by string equality: a test that fails on a changed dash teaches people
to delete tests. Every counter in that network is non-zero on purpose, so a
printer stuck at zero cannot pass a presence check.

`test_skynet_iads_coverage_update_notification.lua` (10 tests) came with
`FIX-COVERAGE-UPDATE-DARKENS-SITES`, for the extinction order that recording a
radar's coverage used to carry. Its leading test lights a battery through a real
`evaluateContacts()` cycle and then adds a radar to the running IADS, so it fails
on what a player sees; the call count during `activate()` is a separate test, and
it is the one that proves the N^2 noise was removed rather than moved.

`abstract-radar-element` is **partly** ported, in slices.
`test_skynet_iads_abstract_radar_element.lua` carries, of that suite's 50 test
methods:

- **slice 1 — the autonomy / coverage cluster** (8 tests): `testGoDark`,
  `testGoLive`, `testGoDarkDueToHARMTestIfAIisOff`,
  `testInformChildrenOfStateChange`,
  `testSAMSiteAndEWRadarLoosesConnectionAndPowerSourceThenAddANewOneAgain`,
  `testSetToCorrectAutonomousState`,
  `testWillGoLiveWhenAutonomousAndHARMDefenceFinished`,
  `testActAsEarlyWarningRadar`. That is the cluster
  `FEAT-LAST-LINE-OF-DEFENSE` needs a regression net for.
- **slice 2 — HARM timing, defence states and the radar bookkeeping**
  (15 tests): `testHARMDefenceStates`, `testGoLiveFailsWhenInHARMDefenceMode`,
  `testFinishHARMDefence`, `testHARMTimeToImpactCalculation`,
  `testSlantRangeCalculationForHARMDefence`, `testShutDownTimes`,
  `testCalculateAspectInDegrees`, `testShallIgnoreHARMShutdown`,
  `testCleanUpOldObjectsIdentifiedAsHARMS`, `testCanEngageAirWeapons`,
  `testCanEngageHARM`, `testAddParentRadarAndClearParentRadars`,
  `testAddChildRadarAndClearChildRadars`, `testGetUsableChildRadars`,
  `testDaisychainSAMOptions`.

- **slice 3 — ammunition, missiles in flight and the engagement zone**
  (16 tests): `testUpdateMissilesInFlight`, `testShutDownWhenOutOfMissiles`,
  `testShutDownShilkaWhenOutOfAmmo`,
  `testWillSAMShutDownWhenItLoosesPowerAndAMissileIsInFlight`,
  `testCreateSamSiteFromInvalidGroup`,
  `testSamSiteGroupContainingOfOneUnitOnlySA8`,
  `testInformOfContactInRangeWhenEarlyWaringRadar`,
  `testSA2InformOfContactTargetInRangeMethod`,
  `testSA2WillNotGoDarkIfTargetIsInRange`,
  `testSA2WillNotGoDarkIfOutOfMisslesAndMissilesAreStillInFlight`,
  `testSA2WillGoDarkWithTargetsInRangeAndHARMDetected`,
  `testSA2WillgoDarkIfOutOfAmmoNoMissilesAreInFlightAndTargetStillInRange`,
  `testSA2OutOfMissilesNoMissilesInFlightIsInformedOfTargetByIADSHasNotDetectedTargetWithOwnRadar`,
  `testSA2GoLiveRangeInPercentInKillZone`,
  `testSA2GoLiveRangeInPercentSearchRange`, `testSA8GoLiveRangeInPercent`.

Several of those are **not** faithful copies, on purpose, and each departure is
argued in a comment where it happens:

- The slice-2 order assertions on `addParentRadar`/`addChildRadar` compared bare
  `{}` mocks with `assertEquals`, and luaunit compares tables by value — two
  empty tables are equal, so those assertions could not fail whatever order the
  code produced. They use `assertIs` here, and a mutation that reverses the
  insertion order turns both red.
- `testCleanUpOldObjectsIdentifiedAsHARMS` never called the method it is named
  after; here it pins the 60-second age boundary the method actually enforces.
- `testSA8GoLiveRangeInPercent` informed the site a second time without
  reopening the target cycle, so `informOfContact()` returned on its
  `targetsInRange == false` guard: the site was never going to light up whatever
  the range said. Here each half runs through a real `targetCycleUpdateStart()`.
- The ammunition tests change what a launcher carries through the stub's
  `__setAmmo` rather than through a mock `getAmmo()` that rewrites its own
  counts as a side effect of being called.

**What did not come with them.** The `.miz` versions of the SA-2 range tests
assert the figures the real DCS units report — 53499.2265625 m for the Flat
Face's detection range. That number belongs to DCS, not to Skynet, and asking
the stub the same question would only prove that `dcs-fixtures.lua` says what
`dcs-fixtures.lua` says. Those assertions stay in the `.miz`; what came across
is the decision built on top of them — which of the search radar, tracking radar
and launcher has to reach a contact, and what `setGoLiveRangeInPercent()` does
to that.

- **slice 4 — point defence and the detected-target cache** (7 tests):
  `testSetPointDefence`, `testPointDefencesGoLive`,
  `testPointDefenceActiveWhenSAMGoesDarkDueToHARMDefence`,
  `testPointDefencesAreNotActivatedWhenNoHARMSRemoved`,
  `testPointDefenceLitByHandIsNotStoodDownWhenItsSAMGoesDark`,
  `testCacheDetectedTargets`,
  `testCacheInvalidatedFirstfewSecondsAfterControllerIsActivated`.

**The port is complete.** The legacy suite has 50 test methods, of which 3 are
commented out upstream and 1 has an empty body; all **46** live ones now run
standalone.

The last of them is a **finding**, not a port, and it is the fourth legacy test
in this suite that could not fail.
`testPointDefenceWillGoDarkWhenSAMItIsProtectingGoesDark` lights a point defence
by hand, sends the site it protects dark and asserts the point defence followed
it down. Its point defence is built without `setupElements()`, so it has no
launchers and no radars, `SkynetIADSSamSite:isDestroyed()` answers true and
`goLive()` never lit it — the assertion read a site that had never been on.
With a real point defence it stays lit: `pointDefencesStopActingAsEW()` is
called from `goLive()` and from the last remembered HARM ageing out, and from
nowhere else. That is not a hole in the live mechanism — a point defence is only
ever lit by `pointDefencesGoLive()`, which `goDark()` runs only during HARM
evasion — but it is one for a mission that lights one by hand. The standalone
test pins what the code does today under a name that says so.

Still DCS-only, nothing ported (need the demo-IADS-world fixture — a later
milestone): `early-warning-radar`, most of `iads`,
`red/blue-sam-sites-and-ew-radars`.

## The figures DCS states

`dcs-figures.lua` is **generated** -- by `python build-tools/dcs-figures.py generate`, from a pinned
commit of the [`Quaggles/dcs-lua-datamine`](https://github.com/Quaggles/dcs-lua-datamine) dump of the
DCS databases. Do not edit it by hand.

It holds the figures that belong to Eagle Dynamics rather than to Skynet: every missile's reach
(`Range_max`) and firing ceiling (`H_max`), and the raw detection distance of every radar
`samTypesDB` names. Those are exactly what `SkynetIADSSAMLauncher:getRange()`,
`getMaximumFiringAltitude()` and `getMaxRangeFindingTarget()` report at runtime.

**Why it exists.** The in-sim suite used to assert those numbers directly -- `getRange() == 35000`
for the SA-11. ED has since made it 46000, which means a Buk battery now wakes 11 km further out in
every mission that places one, and nothing here said so: the assertion only went red when somebody
ran the mission in DCS, which nobody had done since December 2023. Recording the figures turns that
into a diff instead of a discovery.

Two things keep it honest:

- CI runs `python build-tools/dcs-figures.py check`, which regenerates against the pin and fails on
  any difference — so the committed file cannot claim a pin it no longer matches.
- `.github/workflows/dcs-data-drift.yml` bumps the pin every Monday and opens a pull request when a
  figure moved. **That pull request is the point.** Read the diff; there is nothing to fix.

`test_dcs_figures.lua` guards the generator, not Skynet: a regex that stops matching writes a
well-formed empty file, and one that matches half of what it should writes a plausible one. It
checks the table is populated, that every entry states a usable figure, that the figures match what
a real DCS run reported on 2026-09-20, and — from the Lua side, reading the real `samTypesDB` — that
no radar Skynet models is missing. That last check is what caught a non-greedy regex reading only
the first entry of each block, which had silently dropped two radars.

**What the dump cannot say** is which launcher fires which missile: `type_ammunition` is pruned by
the exporter. So missiles are recorded by missile, unfiltered, and the display name carries the
connection — the entry that moved is called `9M38M1 Buk-M1 (SA-11 Gadfly)`.

## Building and editing the `.miz`

Two archives carry an in-sim suite — `unit-tests/skynet-unit-tests.miz` and
`unit-tests/highdigitsams/highdigitsams-unit-tests.miz` — and everything below applies to both.

**Neither of them contains the scripts it runs.** Each holds a placeholder for every script, and the
mission you open in DCS is assembled on demand:

    pwsh -File build-tools/build-compiled-script.ps1     # the deliverable is generated too
    python build-tools/miz-suite.py build                # writes build/missions/*.miz

Copy what that writes into your DCS `Missions` folder and open it there. `build/` is git-ignored: it
is output, like the deliverable.

**Why it works that way.** A copy of the code committed beside the code it copies goes stale without
a sound. Both of these archives held Skynet 3.3.0 from December 2023 until 2026-09-20 while
`develop` moved to 3.5.0, so every in-sim run for three years measured code this project had stopped
shipping — and three tests written into the loose copies during 2026 had never run at all, because
nobody remembered to bake them in. An assembled mission cannot be out of date, and one opened
unbuilt prints a message on screen instead of quietly measuring the wrong thing.

### The wiring, and the rest of the commands

A `.miz` is a zip, and a script baked into one is wired in **four** places: the file under
`l10n/DEFAULT/`, its `ResKey_Action_NNN` line in `l10n/DEFAULT/mapResource`, the
`a_do_script_file(...)` call in `mission`'s compiled `trig.actions`, and the Mission Editor's own
structured copy of the same trigger in `mission`'s `trigrules` — an array whose indices have to stay
contiguous. Forgetting the fourth is the trap: the two copies of the trigger disagree, and the
mission runs the script while the editor shows an empty trigger, or the reverse.

    python build-tools/miz-suite.py check                # wiring, and that git holds no copies
    python build-tools/miz-suite.py stub                 # placeholders back in (adding a suite)
    python build-tools/miz-suite.py extract <dir>
    python build-tools/miz-suite.py remove test-skynet-iads-jammer.lua

Every command works on both archives; `--miz <path>` narrows it to one. `build`, `stub` and `remove`
re-check the result and refuse to write if anything is off, so a failed run leaves the `.miz`
untouched. `check` also reports a suite that exists in `unit-tests/` but that no trigger loads —
which is the drift running the other way, and how three tests sat outside the mission for months.

**CI runs this** (`.github/workflows/lua-tests.yml`, job *In-sim mission archive*): `check`, then a
build of the deliverable, then `build`, then a Lua parse of every file in the **assembled** missions
— including `mission` and `mapResource`, which are Lua too and are the two the tool edits. Parsing
the placeholders instead would prove nothing. Verified against three deliberate breakages: a
`trigrules` entry removed by hand, a `mapResource` line removed, and a script truncated. Each is
caught, and the first two are caught *only* by `check`.

## Needs the simulator

Behaviour that stays in `unit-tests/*.miz` on purpose, because a standalone test
would only be asking the stub to repeat what the fixture told it:

- **How a DCS unit is put together.** How many launchers and radars a group has,
  which is a search radar and which a tracking one, the NATO name DCS gives a
  type. A stub asked about that would only repeat its fixture.
- **The numeric figures ED states about a unit** — a missile's reach, its firing
  ceiling, a radar's detection distance — used to be asserted here and are not any
  more. `abstract-radar-element` pinned 53499.2265625 m for the Flat Face and the
  SA-11's reach at 35000 m; ED made the latter 46000 and the suite read as a red
  test rather than as news. Those figures now live in `dcs-figures.lua`, where a
  change to one arrives as a pull request. See *The figures DCS states* above.
- **Terrain.** Elevation, line of sight, `land.getIP` — the standalone `land`
  stub answers "visible, no intersection" and says so.
- **Real detection geometry**, as opposed to the range arithmetic Skynet does on
  top of it: what a DCS radar actually holds, and when.

## Files

| File | Purpose |
|------|---------|
| `luaunit.lua` | Vendored luaunit 3.4 (upstream, unmodified) |
| `dcs-stub.lua` | Fake DCS scripting environment + fixture factories; provides `coord`, a controllable `timer.scheduleFunction` for the real `SkynetIADSUtils` scheduler, and recorders for what the code prints — `dcsStub.logs` for `env.*`, `dcsStub.screenText` for `trigger.action.outText` , `dcsStub.radioItems` for `missionCommands` |
| `dcs-fixtures.lua` | Reusable fixtures — SAM group builders (positioned, coalition-aware, movable), connection nodes, the EW radar builders (a bare unit, or one in a group for prefix discovery) and the AWACS unit builder, hostile aircraft groups, the IADS-contact factory |
| `skynet-loader.lua` | Loads `skynet-iads-source/*.lua` in dependency order |
| `test_skynet_iads_utils.lua` | Unit tests for the real `skynet-iads-utils.lua` (math + scheduler) |
| `run.lua` | Discovers and runs every `test_*.lua`, aggregates exit codes |
| `test_skynet_iads_range_data.lua` | How a battery learns its own range: `setupRangeData` on the search radar and the launcher, and the delegation between them |
| `test_*.lua` | Test suites — self-contained, self-executing |
