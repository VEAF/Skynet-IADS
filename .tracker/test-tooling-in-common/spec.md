# The test tooling lives with the tests, and the runners find every suite

Status: in-progress

## The problem

Test tooling is spread between `build-tools/` and `test/lua/`, and the runners carry knowledge they
should not:

- `test/common/run.lua` and `run.py` run a hardcoded list of folders. A new suite folder runs only once
  someone adds it to that list.
- The DCS stub, the fixtures and the source loader live in `test/lua/`, and `test/insim-tools/` reaches
  into that sibling for them.
- `test/lua/skynet-loader.lua` holds its own copy of the build order, and `test/lua/test_harness_smoke.lua`
  exists mostly to check that copy against `build-tools/listToMerge.txt`.
- `build-tools/report-test-coverage.lua` and `test-coverage-floor.txt` are test tooling outside `test/`.
- `build-tools/dcs-figures.py` generates `test/lua/dcs-figures.lua` from a pinned dump of the DCS
  database, and a weekly workflow moves the pin. No Skynet test reads those figures: Skynet reads its
  ranges from DCS while the mission runs, and the only reader is `test/lua/test_dcs_figures.lua`, which
  checks the generator. The machinery watches numbers nothing in the project uses.
- The one part of it worth keeping is a side effect: the generator fails when a radar type
  `samTypesDB` names is not in the dump, so a unit ED renames turns the weekly workflow red. It
  covers only the radars, through a Python parser of the Lua file that needs `test_dcs_figures.lua`
  to keep it honest.
- The tests are described in two READMEs, `test/lua/README.md` and `test/insim/README.md`, and
  `test/lua/README.md` is largely the history of how the suite got here, argued with people and
  dates.

## The target

- **Every test lives under `test/`**, wherever the code it tests lives.
- **One folder per place tests run**, and `test/common/` for what the folders share.
- **One README for the tests**, `test/README.md`.
- **The runners find every suite folder themselves.** `lua5.1 test/common/run.lua` with no argument
  runs every Lua suite; `python test/common/run.py` every Python one.

| Folder | Holds |
|---|---|
| `test/lua/` | Skynet's tests, and the check of `samTypesDB` against the DCS database |
| `test/common/` | the runners, `luaunit`, the stub, the fixtures, the loader, the coverage report and its floor, and the tests of the stub and the fixtures |
| `test/build-tools/` | the tests of `build-tools/` |
| `test/insim/` | unchanged, but for its driver's name |
| `test/insim-tools/`, `test/demo-missions/` | unchanged |

## What to build

### The runners

- `run.lua`, with no folder given, runs every folder directly under `test/` that holds a `test_*.lua`.
  `run.py` does the same for `test_*.py`. A folder or a name on the command line narrows the run, as
  today.
- The in-sim driver, `test/insim/run.py`, becomes `test/insim/run-insim.py`, and its test loads it
  by path. Every command that names it follows.

### Into `test/common/`

- `dcs-stub.lua`, `dcs-fixtures.lua`, `skynet-loader.lua`, `test_dcs_stub.lua`, `test_dcs_fixtures.lua`,
  from `test/lua/`;
- `report-test-coverage.lua` and `test-coverage-floor.txt`, from `build-tools/`.

Every path to them follows: the suites in `test/lua/` and `test/insim-tools/`, `.luacheckrc`, `.luacov`,
`.github/workflows/lua-tests.yml`, `CONTRIBUTING.md` (*Layout*, *File naming*, *Building*, the
coverage floor), and the test README.

### The loader

- `skynet-loader.lua` reads `build-tools/listToMerge.txt` instead of holding a copy of the order. It
  skips the `highdigitsams/` entry, as the copy does. The order stays local to the loader: `ORDER`
  is no longer exported.
- `reset()` goes: no suite calls it.
- The `SKYNET_SRC` override goes: nothing sets it.
- `test_harness_smoke.lua` goes. A broken loader fails every Skynet test at once.

### The figures go

- `build-tools/dcs-figures.py`, `test/lua/dcs-figures.lua`, `test/lua/test_dcs_figures.lua`;
- `.github/workflows/dcs-data-drift.yml`, and the figures check in `lua-tests.yml`;
- the `.styluaignore` entry for the generated file, and the file itself if nothing is left in it;
- the passages of `CONTRIBUTING.md` and the test README describing them.

The check below takes up the `IDEAS.md` entry *Every unit type in `samTypesDB` checked against the
datamine*, which leaves it.

The test README keeps the rule they came from, in one sentence: a test never pins a figure that
belongs to DCS — a range, a ceiling, a detection distance — because ED changes them and Skynet reads
them at runtime.

### The unit-type check

- `test/lua/check-unit-types.lua` fetches the datamine's current head in one go — a shallow fetch
  of its file list alone, no file content, into `build/dcs-lua-datamine/`, git-ignored, read with
  `git ls-tree` — then loads
  `skynet-iads-supported-types.lua` with `dofile` and fails on every unit type `samTypesDB` names,
  in `searchRadar`, `trackingRadar`, `launchers` and `misc`, that has no file under `_G/db/Units/`.
  It fails as well when it finds no type or no unit at all, so that a broken check cannot pass.
- Nothing is committed but the script: no pin, no generated file.
- One workflow, `.github/workflows/dcs-unit-types.yml`, runs it weekly on `develop`, on demand, and
  on a pull request that touches `skynet-iads-supported-types.lua`.
- A failed weekly run opens an issue listing the missing types, one per failed run. Only a scheduled
  run does: a pull request's failure is already seen by its author.
- Not named `test_*`: the runners do not pick it up, since it needs the network. It runs by hand as
  `lua5.1 test/lua/check-unit-types.lua`.

### One README

- `test/lua/README.md` and `test/insim/README.md` merge into `test/README.md`. The vendored
  `test/insim/dcs-hotload/README.md` stays: it is that tool's.
- Each passage keeps its rule and the reason in general form, and loses the history: which piece of
  work brought which tests, who decided, and when. That history is in `.tracker/archive/`. This takes
  up the `IDEAS.md` entry *The test READMEs still argue from the backlog*, which leaves it.
- Every pointer follows: `CLAUDE.md`'s table, `CONTRIBUTING.md` (*Layout*, *Test first*),
  `.claude/skills/release/SKILL.md`, the comments in `test/lua/`, and the other `IDEAS.md` entries
  that name a README. `CHANGELOG.md` and the archive are records, and keep their paths.

## Decided

| Decision | Turned down | Why |
|---|---|---|
| Folders are discovered by the runners | a list in the runner | the runner would hold knowledge of the layout, and a new suite would silently not run |
| The in-sim driver is `run-insim.py` | keeping `run.py` beside the runners' `run.py` | two entry points of one name read as one calling the other, and their tests share one process, where Python keeps one module per name; hyphenated like `build-tools/`'s scripts, whose tests load them by path |
| Folders split by where tests run | by what they test, with `lua-tools/` and `common-tools/` | `insim-tools/` exists because its subject runs in DCS and its tests do not; the shared tooling runs exactly like Skynet's tests |
| Shared tooling and its tests in `test/common/` | in `test/lua/` | `test/insim-tools/` uses them too, and no suite folder then reads a sibling |
| The stub and the fixtures keep their tests | dropping them with the loader's | if they imitate DCS wrongly, Skynet's tests pass against a world that does not exist, silently |
| The loader keeps no test of its own | renaming `test_harness_smoke.lua` | its failure is loud: every Skynet test fails |
| The figures are removed | moving the generator into `test/` | nothing consumes them; a range table in the documentation would be a reason to bring the notice back |
| The unit-type check stays, rewritten | dropping it with the figures | a renamed unit leaves a site classified without it, and nothing else says so |
| The check reads the datamine's head | a pinned commit | a pin is committed state, and needs a workflow to move it; a red run at head is the news itself |
| ED's drift is watched weekly | on every pull request and push | a rename is rare and follows a DCS update; checked on every pull request, it turns unrelated work red and ties it to an external repository |
| A pull request touching `skynet-iads-supported-types.lua` runs it | trusting its review | a DCS type name is an exact string a reviewer cannot confirm without the dump; the trigger is a path filter |
| Nothing at release | a release gated on no open issue | it needs a way to identify the issue; the weekly run covers the window |
| A failed weekly run opens an issue, one per run | the red run alone; commenting on the open issue | GitHub mails a scheduled failure only to whoever last edited its `cron` line; drift is rare enough that duplicates are not worth finding |
| The runners leave the check out | a `test_*` suite | a local run would need the network, and fail offline |
| The check loads `samTypesDB` in Lua | parsing it from Python | `dofile` reads the table Skynet reads; a parser needs a test of its own |
| The check lives in `test/lua/` | a folder of its own | it checks Skynet's core, in Lua; its name keeps it out of the runners |
| One README under `test/` | a README per suite folder | a contributor reads one file to choose a suite and use it; the shared tooling serves every folder |
| The history goes with the merge | merging the text as it is | every passage is moved anyway, so each is checked once |
| The check covers every role | the radars only | a launcher renamed is a site that never fires |
| The check leaves out High Digit SAMs | checking them too | a mod: 46 of its 125 types are not in ED's dump |
| High Digit SAMs stay as they are | loading them by default | an old, little-used mod; no change touches it |

## Out of scope

- The build and the compiled-script test, already moved by `chore-build-in-python`: this work
  follows their paths.
- The demos' updater and its tests, from `chore-demo-missions-carry-their-script`.
- `docs-check.py` and its tests.
