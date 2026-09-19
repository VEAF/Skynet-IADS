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

## Ported suites

These `unit-tests/` suites now also run standalone (their `.miz` copies are kept):
`harm-detection`, `abstract-dcs-object-wrapper`, `moose-a2a-connector` (1 test),
`jammer`, `abstract-element`, `sam-site`, plus the M1 `contact` pilot.

`test_skynet_iads.lua` additionally carries one narrow regression test
(`testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage`, the `3a94937` fix)
ported straight off the real `addEarlyWarningRadar`/`addSAMSite`/`activate`
API — it does not port the rest of `unit-tests/test-skynet-iads.lua`. The
`.miz` copy stays the in-sim functional/smoke suite for the rest of the
`iads` class until (if ever) that gets a standalone port too.

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

`test_skynet_iads_coverage_update_notification.lua` (5 tests) came with
`FIX-COVERAGE-UPDATE-DARKENS-SITES`, for the extinction order that recording a
radar's coverage used to carry. Its leading test lights a battery through a real
`evaluateContacts()` cycle and then adds a radar to the running IADS, so it fails
on what a player sees; the call count during `activate()` is a separate test, and
it is the one that proves the N^2 noise was removed rather than moved.

`abstract-radar-element` is **partly** ported, in slices.
`test_skynet_iads_abstract_radar_element.lua` carries the autonomy / coverage
cluster — 8 of that suite's 50 tests:
`testGoDark`, `testGoLive`, `testGoDarkDueToHARMTestIfAIisOff`,
`testInformChildrenOfStateChange`,
`testSAMSiteAndEWRadarLoosesConnectionAndPowerSourceThenAddANewOneAgain`,
`testSetToCorrectAutonomousState`,
`testWillGoLiveWhenAutonomousAndHARMDefenceFinished` and
`testActAsEarlyWarningRadar`. That is the cluster `FEAT-LAST-LINE-OF-DEFENSE`
needs a regression net for; the rest of the suite still runs only in the `.miz`.

Still to port out of `abstract-radar-element` (the remaining 42 tests, grouped
as they sit in the file): HARM timing and defence states, point defence, the
SA-2 range / engagement-zone tests, ammo and missiles-in-flight, the parent /
child radar bookkeeping, and the cached-targets and aspect calculations.

Still DCS-only, nothing ported (need the demo-IADS-world fixture — a later
milestone): `early-warning-radar`, most of `iads`,
`red/blue-sam-sites-and-ew-radars`.

## Files

| File | Purpose |
|------|---------|
| `luaunit.lua` | Vendored luaunit 3.4 (upstream, unmodified) |
| `dcs-stub.lua` | Fake DCS scripting environment + fixture factories; provides `coord` and a controllable `timer.scheduleFunction` for the real `SkynetIADSUtils` scheduler |
| `dcs-fixtures.lua` | Reusable fixtures — SAM group builders (positioned, coalition-aware, movable), connection nodes, the EW radar builders (a bare unit, or one in a group for prefix discovery) and the AWACS unit builder, hostile aircraft groups, the IADS-contact factory |
| `skynet-loader.lua` | Loads `skynet-iads-source/*.lua` in dependency order |
| `test_skynet_iads_utils.lua` | Unit tests for the real `skynet-iads-utils.lua` (math + scheduler) |
| `run.lua` | Discovers and runs every `test_*.lua`, aggregates exit codes |
| `test_*.lua` | Test suites — self-contained, self-executing |
