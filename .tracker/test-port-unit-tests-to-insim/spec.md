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

## Open

- The order relative to `chore-demo-missions-carry-their-script`, which removes `miz-suite.py`, the tool that also handles the legacy missions.
- Which scenarios form the minimal tier.

## Out of scope

- Changes to the in-sim suite's engine beyond what a scenario needs.
- The demo missions: `chore-demo-missions-carry-their-script`.
