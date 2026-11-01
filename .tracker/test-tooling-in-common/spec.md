# The test tooling lives with the tests, and the runners find every suite

Status: open

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

## The target

- **Every test lives under `test/`**, wherever the code it tests lives.
- **One folder per place tests run**, and `test/common/` for what the folders share.
- **The runners find every suite folder themselves.** `lua5.1 test/common/run.lua` with no argument
  runs every Lua suite; `python test/common/run.py` every Python one.

| Folder | Holds |
|---|---|
| `test/lua/` | Skynet's tests |
| `test/common/` | the runners, `luaunit`, the stub, the fixtures, the loader, the coverage report and its floor, and the tests of the stub and the fixtures |
| `test/build-tools/` | the tests of `build-tools/` |
| `test/insim/`, `test/insim-tools/` | unchanged |

## What to build

### The runners

- `run.lua`, with no folder given, runs every folder directly under `test/` that holds a `test_*.lua`.
  `run.py` does the same for `test_*.py`. A folder or a name on the command line narrows the run, as
  today.

### Into `test/common/`

- `dcs-stub.lua`, `dcs-fixtures.lua`, `skynet-loader.lua`, `test_dcs_stub.lua`, `test_dcs_fixtures.lua`,
  from `test/lua/`;
- `report-test-coverage.lua` and `test-coverage-floor.txt`, from `build-tools/`.

Every path to them follows: the suites in `test/lua/` and `test/insim-tools/`, `.luacheckrc`, `.luacov`,
`.github/workflows/lua-tests.yml`, `CONTRIBUTING.md` (*Layout*, *File naming*, the coverage floor),
`test/lua/README.md`.

### The loader

- `skynet-loader.lua` reads `build-tools/listToMerge.txt` instead of holding a copy of the order. It
  skips the `highdigitsams/` entry, as the copy does.
- `reset()` goes: no suite calls it.
- `test_harness_smoke.lua` goes. A broken loader fails every Skynet test at once.

### The figures go

- `build-tools/dcs-figures.py`, `test/lua/dcs-figures.lua`, `test/lua/test_dcs_figures.lua`;
- `.github/workflows/dcs-data-drift.yml`, and the figures check in `lua-tests.yml`;
- the `.styluaignore` entry for the generated file, and the file itself if nothing is left in it;
- the passages of `CONTRIBUTING.md` and `test/lua/README.md` describing them.

`test/lua/README.md` keeps the rule they came from, in one sentence: a test never pins a figure that
belongs to DCS — a range, a ceiling, a detection distance — because ED changes them and Skynet reads
them at runtime.

## Decided

| Decision | Turned down | Why |
|---|---|---|
| Folders are discovered by the runners | a list in the runner | the runner would hold knowledge of the layout, and a new suite would silently not run |
| Folders split by where tests run | by what they test, with `lua-tools/` and `common-tools/` | `insim-tools/` exists because its subject runs in DCS and its tests do not; the shared tooling runs exactly like Skynet's tests |
| Shared tooling and its tests in `test/common/` | in `test/lua/` | `test/insim-tools/` uses them too, and no suite folder then reads a sibling |
| The stub and the fixtures keep their tests | dropping them with the loader's | if they imitate DCS wrongly, Skynet's tests pass against a world that does not exist, silently |
| The loader keeps no test of its own | renaming `test_harness_smoke.lua` | its failure is loud: every Skynet test fails |
| The figures are removed | moving the generator into `test/` | nothing consumes them; a range table in the documentation would be a reason to bring the notice back |
| High Digit SAMs stay as they are | loading them by default | an old, little-used mod; no change touches it |

## Out of scope

- The build and the compiled-script test: `chore-build-in-python`. Whichever of the two lands second
  follows the other's paths.
- The demos' updater and its tests: `chore-demo-missions-carry-their-script`.
- `docs-check.py` and its tests.
