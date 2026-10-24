# Port the legacy in-sim tests to the in-sim suite, then drop them

Status: open

## The problem

`unit-tests/` is deprecated. It holds the legacy luaunit missions (`skynet-unit-tests.miz`, `highdigitsams/highdigitsams-unit-tests.miz`) and the dcs-bridge smoke gate (`build-tools/run-smoke.py`, `unit-tests/last-line-of-defence/`, and the checks it runs against the demo mission). The in-sim suite under `test/insim/` (`feat-insim-test-suite`) is meant to replace all of it.

## The target

- **Every test** in the legacy missions and **every smoke check** is either ported to a `test/insim/` scenario or dropped, each with a stated reason.
- Then `unit-tests/`, `build-tools/run-smoke.py`, its tests and the dcs-bridge wiring go.
- The in-sim suite covers the anti-regression ground: engagements, HARM defence, go-live and go-dark cycles, and the IADS-building checks that read the real world.

## What to build

- An inventory: each legacy test and smoke check, with its fate — ported (to which scenario) or dropped (why). A test that only mocks DCS away is covered by `test/lua/` or dropped; one that reads the real world is ported.
- The scenarios, with the fixtures they need in `test/insim/miz/`, and the shared helpers in the suite's `user-lib/` libraries as two scenarios come to need them.
- The removals, and the documentation that pointed at them (`CONTRIBUTING.md`, `CLAUDE.md`, the release steps that fly the smoke gate).

## Carried over from the in-sim suite

Deferred by `feat-insim-test-suite` to the first anti-regression scenarios, which meet them first:

- `insim-skynet.iads(ctx)` registers no cleanup when adding sites or activating fails after the IADS was created: register the deactivation first.
- A missing fixture, or an `addGroup` returning nil, is reported `fail`; it is a broken precondition, so `invalid`. Match the `INSIM-INVALID: ` mark anywhere in the error, not only at its start (a `ctx.invalid` raised inside a `waitFor` predicate is prefixed by hotload).
- A setup that finds an old context for its scenario (a run aborted earlier in the same mission session) overwrites it and leaves its IADS running: clean the old one up first, or refuse.
- Scenario names starting `probe-` or `stop-`, or containing `"`, collide with the driver's own command names or break the command text: refuse them in discovery.
- `clearWrecks(zoneName)` in a `user-lib/` library, for scenarios that explode things.
- The driver core's default probe names the test layer (`Hotload.load("insim").status()`): the caller should pass it.

## Open

- The order relative to `chore-demo-missions-carry-their-script`, which removes `miz-suite.py`, the tool that also handles the legacy missions.
- Which scenarios form the minimal tier.

## Out of scope

- Changes to the in-sim suite's engine beyond what a scenario needs.
- The demo missions: `chore-demo-missions-carry-their-script`.
