# Port the legacy in-sim tests to the in-sim suite, then drop them

Status: done

## The problem

`unit-tests/` is deprecated. It holds the legacy luaunit missions (`skynet-unit-tests.miz`, `highdigitsams/highdigitsams-unit-tests.miz`) and the dcs-bridge smoke gate (`build-tools/run-smoke.py`, `unit-tests/last-line-of-defence/`, and the checks it runs against the demo mission). The in-sim suite under `test/insim/` is meant to replace all of it.

## The target

- **Every test** in the legacy missions and **every smoke check** is either ported to a `test/insim/` scenario or dropped, each with a stated reason.
- Then `unit-tests/`, `build-tools/run-smoke.py`, its tests and the dcs-bridge wiring go.
- The in-sim suite covers the anti-regression ground: engagements, HARM defence, go-live and go-dark cycles, and the IADS-building checks that read the real world.

## The baseline

[`inventory.md`](inventory.md) lists every legacy test and smoke check with its fate, and describes each scenario: what it proves, which legacy tests it absorbs, its mission and its tier. It is kept true while the work is under way.

A fate follows two rules:

- **The in-sim suite covers what a stub cannot answer.** A legacy test that mocks DCS away is dropped; whether `test/lua/` covers its logic is a `test/lua/` question.
- **Behaviour before API.** A DCS call is proven by the scenario whose behaviour depends on it. It is checked on its own only where a broken behaviour would not say which call broke: the classification of a live group, in `iads-builds`.

Last line of defence and coverage following an AWACS are ported as they are: same mechanism, same conditions, both halves of each.

## Decisions

| Decision | Turned down | Why |
|---|---|---|
| This work lands before `chore-demo-missions-carry-their-script` | after it | with the legacy suite gone, that chore has only the demos left to handle |
| Two missions: `insim-ca-main` on Caucasus, `insim01` renamed, and `insim-pg-llod` on Persian Gulf for the last line of defence | every scenario in one mission | the last line of defence depends on terrain hiding an aircraft from an EW radar, and its layout is on Persian Gulf |
| Coverage following an AWACS moves to `insim-ca-main` | a Persian Gulf mission | it needs no terrain; it falls back to `insim-pg-llod` or a mission of its own if the layout does not carry over |
| `insim-ca-main` holds a catalogue of late-activated fixtures; a scenario copies what it needs with `ctx:add` | a montage per scenario | one network serves every scenario, and a copy is fresh on every run where an activated group is spent until the mission restarts |
| Ground fixtures are placed in the mission; aircraft are placed or routed by the scenario; named zones give vetted slots | scenarios placing ground units by computation | a ground unit placed blind lands on whatever terrain is there |
| Fixtures and zones are placed with the `building-dcs-missions` tooling, then checked and adjusted in the Mission Editor | the Mission Editor alone | placing a catalogue by hand is slow; the check by eye stays |
| `ctx:add(role)` resolves `FIXTURE-<scenario>-<role>`, then `FIXTURE-<role>` | catalogue names only | the existing scenarios keep working unchanged |
| Runs are made deterministic: HARM detection chance set to 100 where a HARM is detected, attackers immortal where their survival is not under test, waits that allow for the random shutdown times, an invisible attacker where only a munition may wake a site | accepting flaky scenarios | a red that comes and goes is read as noise, and then a real one is too |
| A shared watch helper records transitions as they pass — seen live, seen dark again — in `user-lib/` from the first scenario | a watch per scenario | at least four scenarios judge a transition, which the current state cannot tell from its absence |
| A scenario's `timeout` is set from its expected flight time | one timeout for all | a run of seven minutes and one of seconds share nothing |
| Tier `minimal`: `iads-builds`, `ew-detects-aircraft`, `sam-engages`, one case of `infrastructure-destroyed`. Tier `full`: the rest, the last line of defence and coverage following an AWACS included | the two recent runs in `minimal` | they fly for minutes; `minimal` is what runs before every pull request |
| A release flies `python test/insim/run.py` on the minimal tier, consultative as the smoke gate was | the full tier | two tiers exist so that the routine run stays short |
| The High Digit SAMs suite is dropped | porting it | the mod is not part of the in-sim suite |
| The five smoke checks against the demo mission are dropped here | porting them | what the demo builds, carries and depends on is `chore-demo-missions-carry-their-script`'s business; loading the build is proven by every scenario |

## Carried over from the in-sim suite

Deferred by the in-sim suite to the first anti-regression scenarios. All land in the first pull request:

- `insim-skynet.iads(ctx)` registers no cleanup when adding sites or activating fails after the IADS was created: register the deactivation first.
- A missing fixture, or an `addGroup` returning nil, is reported `fail`; it is a broken precondition, so `invalid`. Match the `INSIM-INVALID: ` mark anywhere in the error, not only at its start (a `ctx.invalid` raised inside a `waitFor` predicate is prefixed by hotload).
- A setup that finds an old context for its scenario (a run aborted earlier in the same mission session) overwrites it and leaves its IADS running: clean the old one up first, or refuse.
- Scenario names starting `probe-` or `stop-`, or containing `"`, collide with the driver's own command names or break the command text: refuse them in discovery.
- `clearWrecks(zoneName)` in a `user-lib/` library, for the scenarios that explode things.
- The driver core's default probe names the test layer (`Hotload.load("insim").status()`): the caller should pass it.

## Pull requests

1. **Everything new**: the engine changes, the catalogue naming, both missions, every scenario, and their documentation — `test/insim/README.md` included, whose rule that the template is edited in the Mission Editor only changes to allow the mission tooling.
2. **The removal**, opened once the first has been flown in DCS:
   - `unit-tests/`, whole;
   - `build-tools/run-smoke.py` and `test/build-tools/test_run_smoke.py`;
   - in `build-tools/miz-suite.py`, the three legacy archives, `--with-bridge` and the bridge copy, and their tests in `test/build-tools/test_miz_suite.py`;
   - `CONTRIBUTING.md`: the `unit-tests/` rows of the layout and of the suites, the mentions in *The missions are assembled, not committed*, and the release's flight, now the minimal tier;
   - `CLAUDE.md`: the row pointing at `unit-tests/README.md`, which points at `test/insim/README.md` instead;
   - `.claude/skills/release/SKILL.md`: its flight, the same way;
   - `test/lua/README.md`: the passages that send a reader to `unit-tests/`;
   - the comments in `.gitignore` and `.github/workflows/release.yml` that describe `unit-tests/` as present.

   Comments that record history — in `build-tools/test-coverage-floor.txt`, in `test/lua/*.lua` — and `CHANGELOG.md` stay.

## Out of scope

- Changes to the in-sim suite's engine beyond what a scenario needs.
- The demo missions: `chore-demo-missions-carry-their-script`. So is the `CLAUDE.md` rule that a `.miz` is never edited by hand.
- Folding the release skill into `CONTRIBUTING.md`: an idea in `IDEAS.md`.
