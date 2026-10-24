# `test/common/`: the test machinery in one place, Skynet's tests apart from the tooling's

Status: in-progress

## The problem

`test/lua/` mixes Skynet's logic tests with the tests of the in-sim suite's tooling (`test_insim.lua`, `test_insim_skynet.lua`, `insim-fixtures/`): one folder, one count, one CI step. `test/python/` holds only tooling tests, of two different tools: the in-sim suite and `build-tools/`. And the machinery every Lua suite uses, luaunit and the runner, lives inside one of them.

## The layout

| Folder | Holds |
|---|---|
| `test/common/` | the machinery the test suites share, whatever their language: today `luaunit.lua` (vendored), and a runner per language: `run.lua`, `run.py` |
| `test/lua/` | Skynet's logic tests, and its test doubles `dcs-stub.lua`, `skynet-loader.lua`, `dcs-figures.lua`, `dcs-fixtures.lua` |
| `test/insim/` | the in-sim suite itself, unchanged: `run.py`, `engine/`, `scenarios/`, `miz/`, the vendored `dcs-hotload/` |
| `test/insim-tools/` | the in-sim tooling's tests, Lua and Python: `test_insim.lua`, `test_insim_skynet.lua`, `test_insim_*.py`, and both fixture folders, merged as `insim-fixtures/` (`scenarios/` from Lua, `verify/` from Python) |
| `test/build-tools/` | the tests of `build-tools/`, renamed from `test/python/`: `test_docs_check.py`, `test_miz_suite.py`, `test_run_smoke.py` |

`dcs-stub.lua` and `skynet-loader.lua` stay in `test/lua/`: they are Skynet's test doubles, and `test_insim_skynet.lua` reaches them by path.

`test/insim-tools/` and `test/build-tools/` sit side by side, each named after the tooling it tests rather than its language.

## The runner

`run.lua` takes the folders to discover in; with none, it runs every suite folder (`test/lua`, `test/insim-tools`):

```
lua5.1 test/common/run.lua                          # every Lua suite
lua5.1 test/common/run.lua test/lua                 # Skynet's logic tests
lua5.1 test/common/run.lua test/insim-tools         # the in-sim tooling's tests
lua5.1 test/common/run.lua test/lua contact         # a name still filters
```

Its behaviour is otherwise unchanged: `test_*.lua` in each folder, each as a child process, exit codes aggregated, the coverage hook under `SKYNET_TEST_COVERAGE`.

`run.py` does the same for Python, with the same arguments: one unittest run over `test_*.py` in each folder, `test/insim-tools` and `test/build-tools` when none is given.

## What changes

- **Every Lua suite** loads luaunit from `test/common/`: one line each, `"/../common/luaunit.lua"`.
- **The in-sim tooling's tests and fixtures** move to `test/insim-tools/`, their paths to `dcs-stub.lua`, `skynet-loader.lua`, the user-lib files and the engine modules adjusted.
- **The judge's runner**, `test/insim/engine/verify.lua`, finds luaunit at its new path.
- **CI**: `lua-tests.yml` and `dcs-data-drift.yml` call the new runner; `lua-tests.yml` runs the Python tests through `run.py`; `docs-check.yml` runs `test_docs_check.py` through it, in `test/build-tools/`.
- **Lint and coverage config**: `.styluaignore` and `.luacheckrc` name the vendored luaunit at its new path; `build-tools/lint.sh` (`TARGETS`) adds `test/common/` and `test/insim-tools/`, so the moved files stay gated, and both tools skip the fixture that is broken on purpose (`insim-fixtures/verify/bad-syntax/`); `.luacov` and `build-tools/report-test-coverage.lua` follow.
- **Docs**: `CLAUDE.md` and `CONTRIBUTING.md` (the commands, the layout table, the file-naming row for the test folders, the lint scope), `test/lua/README.md` (how to run, how to add a suite), `test/insim/README.md` (where its own tests are and how to run them).

The coverage floor does not move: it measures `skynet-iads-source/` only, and CI's coverage run names `test/lua` alone, so the in-sim tooling's tests add nothing to it.

## With the hotload move

Moving the in-sim engine to dcs-hotload takes `test_insim.lua`, `insim-fixtures/` and the driver core's Python tests there in stages. With this refactor first, each stage is a move out of `test/insim-tools/` rather than a pick out of `test/lua/` and `test/python/`.

## Out of scope

- Any change to what a test checks.
- The legacy `unit-tests/`: `test-port-unit-tests-to-insim`.
