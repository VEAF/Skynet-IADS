# Design: `test/insim/` — a live-DCS test tier

Status: approved by user, pending implementation plan.
Related: [docs/evolutions.md](../../evolutions.md) "Smoke tests" section, VEAF issue #3, the
`evolutions.md` "No coalition check on weapon contacts" item.

## Problem

Skynet-IADS has two test tiers today:

| Tier | Runs where | Job |
|---|---|---|
| `test/lua/` | plain Lua 5.1, no DCS | logic: state machines, math, branching |
| `unit-tests/*.miz` | inside DCS, launched by hand, results read from `dcs.log` | functional/smoke, but mostly still mocks `getDCSRepresentation()` and similar — not actually exercising DCS radar geometry, missile flyout, or terrain |

A number of recent changes (HARM-silence cleanup, the `ad60e92` weapon-contact widening,
the SAM-goes-dark fix) have shipped without being run against a live DCS mission at all.
The existing DCS-tier tests don't close that gap because they mock away the exact behavior
(real detection, real coalition data, real emission state) that would need checking. Running
them today is also manual: launch DCS, alt-tab, grep `dcs.log`.

`evolutions.md`'s own items (VEAF issue #3, the coalition-check question) are cited below only
as *motivating examples* of the kind of scenario this tier exists to make possible — they are
separate, future pieces of work, planned for after this one, and writing them is explicitly
**not** part of this spec or the plan that follows it.

`evolutions.md` asks: can the legacy `unit-tests` be turned into something more usable, and
do MCP-style bridges to a running DCS mission exist that would help? Yes — projects like
[VEAF-dcs-bridge](https://github.com/VEAF/VEAF-dcs-bridge) inject a Lua script into a mission
that exposes an `exec_lua`-style command channel to an external process, replacing "read the
log" with "get a structured result back." This spec borrows that idea and builds a minimal,
purpose-built version for this repo — not a dependency on VEAF-dcs-bridge itself (that project
has ~2 commits at time of writing and no stability guarantee).

## Goals

- A third, durable test tier, `test/insim/` — the pipeline itself (bridge, orchestrator,
  fixture mission, execution model) — capable of running scenarios that need genuine DCS
  behavior (radar detection, terrain, coalition checks, real emission-state changes), not
  more of what `test/lua/` can already cover once ported.
- Fully unattended: launch DCS, run scenarios, collect a pass/fail report, shut down, with
  no human watching or clicking through the DCS UI.
- Minimal, in-repo tooling: no new external service dependency, no binary/ABI-matching risk.

## Non-goals

- Writing any real regression scenario. This work proves the pipeline with one throwaway
  placeholder scenario; actual scenarios (coalition check, SAM-goes-dark, etc.) are separate,
  future work planned after this piece, each getting its own scoping when it's picked up.
- Migrating `unit-tests/*.miz` scenarios. It stays as-is for now, the fallback for anything
  not yet ported. The long-term intent, though, *is* for `test/insim/` to eventually replace
  and extend the entire legacy suite — expect far more scenarios over time than the handful
  cited below as motivating examples. That migration is a large body of future work, planned
  and scoped incrementally as it's picked up, not something this piece of work does.
- CI integration. Running DCS unattended needs a licensed, GPU-capable machine; deciding
  whether/how to run this tier in CI is a separate, later decision.
- Adopting VEAF-dcs-bridge as a dependency. Its architecture is the inspiration; this repo
  gets its own minimal bridge, small enough to maintain here.
- Solving every DCS mission-editor detail (exact fixture unit layout, terrain choice) — that
  is implementation-plan-level detail, decided per scenario.

## Architecture

### Bridge: file-based IPC, not sockets

The mission-side bridge (`test/insim/bridge/dcs-insim-bridge.lua`) is loaded into the shared
test mission via a `DO SCRIPT FILE` trigger (mission-scoped — it does not touch any other
mission or the user's normal DCS profile beyond the one setup step below). Every ~200ms
(`timer.scheduleFunction`) it:

1. Checks for a command file. If present, reads a Lua snippet from it.
2. Runs the snippet with `loadstring`, inside `pcall`.
3. Writes the result (or the error message) to a response file, then deletes the command file.

This was chosen over a TCP-socket bridge (closer to VEAF's own stack) because DCS's Lua 5.1
runtime does not bundle LuaSocket — using real sockets would mean sourcing or building
LuaSocket binaries ABI-matched to DCS's exact Lua build, a fragile, unsupported-by-anyone
dependency for this project's narrow need. File IPC needs only `io`/`os`, which are stock
Lua 5.1 — no extra binaries. Latency (a ~200ms poll) is irrelevant for a test runner that is
waiting on a scenario to finish anyway.

**Setup cost, accepted:** DCS's `Scripts/MissionScripting.lua` sanitizes `io`/`os` out of the
mission scripting environment by default. Unlocking them (commenting out the relevant
`sanitizeModule` calls, the same one-time edit MOOSE/MIST/CTLD-class frameworks have long
required for filesystem access) is install-wide, not scoped to this repo's test mission — it
affects every mission run on that DCS install, including multiplayer integrity checks. The
user has explicitly chosen to make this edit on their primary DCS install rather than keep a
separate install/profile for testing. `test/insim/README.md` must document the edit and how
to revert it.

### Scenario execution model: luaunit inside the mission, unchanged

The bridge does not define its own assertion style. A scenario run means the orchestrator
sends a command that `dofile`s a scenario suite (`test/insim/scenarios/scenario_*.lua`,
shaped exactly like today's `unit-tests/test-*.lua` — `luaunit`-based, `setUp`/`tearDown`,
one file per concern) and calls `lu.LuaUnit.run()`. luaunit's own pass/fail/failure-message
accumulation is what gets serialized back through the bridge as the result payload. This
keeps one mental model across all three tiers and avoids inventing new assertion machinery.

One shared, long-lived test mission (`test/insim/fixtures/skynet-insim-test.miz`), analogous
to today's `unit-tests/skynet-unit-tests.miz`, holds the fixture units every scenario needs.
Scenarios stay isolated from each other via `setUp`/`tearDown`, the same pattern already used
in `unit-tests/*.miz` — there is no need for one DCS launch per scenario; DCS launch is the
expensive part of the whole loop.

### Unattended launch: DCS dedicated-server mode

Launching is done via DCS's own supported unattended path — dedicated-server mode
(`DCS.exe --server`, driven by `Config/serverSettings.lua` naming the test mission) — not by
simulating mouse/keyboard input against the normal game UI. This is the same mechanism real
DCS dedicated servers already use to auto-load a mission with no human present.

### Orchestrator: PowerShell

`test/insim/orchestrator/run.ps1`, matching the existing `build-tools/build-compiled-script.ps1`
convention already in this repo (no new language dependency):

1. Launch DCS in server mode against the test mission.
2. Poll for a "bridge ready" marker file written by the bridge once Skynet's source and the
   mission environment have finished loading.
3. Send the "run this scenario suite" command; poll for the result file.
4. Parse the result into a pass/fail report shaped like `test/lua/run.lua`'s aggregate output
   (suite names, pass/fail counts, failure messages), so a future top-level "run everything"
   script can treat all three tiers uniformly.
5. Terminate the DCS process, clean up command/response/marker files.
6. Exit 0 if everything passed, non-zero otherwise.

## Layout

```
test/insim/
  bridge/dcs-insim-bridge.lua       # polls command file, loadstring+pcall, writes result file
  orchestrator/run.ps1              # launches DCS, drives the command/response loop, reports
  fixtures/skynet-insim-test.miz    # shared test mission
  fixtures/serverSettings.lua       # dedicated-server config naming the test mission
  scenarios/scenario_*.lua          # luaunit suites, same shape as unit-tests/test-*.lua
  README.md                         # setup (MissionScripting.lua edit + revert), how to run
```

## Deliverable of this work: infrastructure only, proven by one placeholder scenario

This spec and the plan that follows it deliver the tier itself — bridge, orchestrator,
fixture mission, scenario execution model, README — not any real regression scenario.
The one scenario written as part of this work is a minimal placeholder whose only job is
to prove the pipeline end-to-end: launch DCS unattended, run a trivial `luaunit` suite
inside the live mission via the bridge (e.g. assert a known fixture unit exists and
`Group.getByName` returns it), and get a correctly-reported pass/fail back out. It is
throwaway scaffolding, not a real check of Skynet behavior.

## Future scenarios this tier is meant to unlock (not part of this work)

The long-term aim is for `test/insim/` to replace and extend the *entire* legacy
`unit-tests/*.miz` suite — every `unit-tests/test-*.lua` file that genuinely needs live DCS
behavior is eventually a migration candidate, not just the examples below. That whole
migration is future work, planned and scoped incrementally, file by file, once this tier
exists — not enumerated in full here. Three examples, recorded only to show *why* this tier
is worth building:

- **Coalition check on weapon contacts** (`evolutions.md`, "Possible issues detected to
  check") — whether `Controller.getDetectedTargets` ever surfaces friendly ordnance is an
  empirical question about DCS's own behavior; a mock cannot answer it.
- **SAM-goes-dark** (`f6d77e6`) — would be worth revisiting as an `insim` scenario if its
  current test turns out to mock `getDCSRepresentation()`/emission state rather than
  exercise real detection.
- VEAF issue #3 (`harmSilenceID` cleanup) is explicitly **not** a candidate for this tier —
  it's internal-state testing (arm a timer, call `cleanUp()`, assert nil), no live DCS
  behavior needed, so it belongs in `test/lua/` once `abstract-radar-element` is ported
  there.

This is not a strict either/or split per scenario. `test/lua/` and `test/insim/` serve
different purposes, not just different capabilities — `test/lua/` is for fast, on-the-fly,
CI-friendly runs; `test/insim/` is heavier to run but proves the same behavior in a real DCS
context. The same underlying scenario can legitimately end up covered in both: a mocked
`test/lua/` port for quick/CI feedback, *and* an `insim` scenario for real-context confidence
on top of it. "Replace and extend" means the legacy suite's coverage is picked up by whichever
tier(s) fit each scenario, including both, not routed to exactly one.

## Risks / open questions for the implementation plan

- Exact `serverSettings.lua` fields needed to auto-load a specific `.miz` unattended (to be
  verified against a real DCS dedicated-server config during implementation).
- How luaunit's result object is serialized into the response file (a hand-rolled
  pass/fail/message table is enough; no need for luaunit's JUnit/TAP output modes).
- Fixture mission unit layout per scenario — decided per scenario, not in this spec.
- `MissionScripting.lua` edit affects the user's whole DCS install, including multiplayer
  integrity checks, by their own explicit choice; `README.md` must document the revert path.
