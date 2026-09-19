# 01 — measure test coverage in CI, and publish the number

Status: 🔄 in-progress — on `feature/measure-test-coverage-in-ci`

The suite already runs in CI and tells you pass or fail. This ticket makes it also tell you **how
much of the source it ran**. No threshold yet — ticket 02 adds the gate. Splitting the two keeps
the first pull request about a measurement nobody can argue with.

## What to build

**1. `.luacov` at the repository root.** The denominator policy, written down where it is executed:

```lua
return {
	include = { "skynet%-iads%-source" },
	-- Pure data: nested tables of SAM types, radar names and NATO designations. luacov scores
	-- every line of a table constructor as executed the moment the file loads, so counting them
	-- hands the project ~500 free lines and turns the floor into a formality. The second pattern
	-- is the high-digit file, whose name carries an upstream typo ("suported", one p) — match it
	-- as spelled, do not rename the file.
	exclude = { "supported%-types$", "suported%-types$" },
	runreport = false,
	deletestats = false,
}
```

`include` is what keeps `test/lua/luaunit.lua`, the stub and the suites themselves out of the
numbers — the tests are not the thing being measured.

**2. `run.lua` runs the children under `luacov` on demand.** It builds each child command as
`"<interp>" "<suite>"`; add the hook when `SKYNET_TEST_COVERAGE` is set:

- `SKYNET_TEST_COVERAGE=1 lua5.1 test/lua/run.lua` → each child becomes
  `"<interp>" -lluacov "<suite>"`.
- Unset, nothing changes. The plain run stays exactly what it is today, hook-free.

`luacov` merges into an existing `luacov.stats.out` rather than overwriting it, which is what makes
18 separate child processes add up to one report. It also wraps `os.exit`, which every suite calls
through `luaunit`, so the stats of a suite are written even on a failing exit code. **Check both of
those on the branch** rather than trusting this paragraph — a silent merge failure looks exactly
like low test coverage.

**3. `build-tools/report-test-coverage.lua`.** Runs the reporter over the merged stats and prints
the total, so CI and a developer's machine produce the same line from the same code:

```
test coverage: 70.22%  (1679 / 2391 lines)
```

Take the figures from the reporter's own summary rather than re-deriving them.

**4. A `test-coverage` job in `.github/workflows/lua-tests.yml`**, beside the existing one, not
inside it: the plain suite must keep running without the debug hook installed. The suite takes
0.7 s, so a second run costs nothing.

The job needs `luacov`, which is pure Lua but has to land in the **5.1** tree:

```yaml
      - name: Install Lua 5.1 and luacov
        run: |
          sudo apt-get update -q
          sudo apt-get install -y lua5.1 liblua5.1-0-dev luarocks
          sudo luarocks --lua-version=5.1 install luacov
```

**This is the one step to verify before anything else** — Ubuntu's `luarocks` is built against the
distribution's default Lua, and `--lua-version=5.1` is what redirects it. If it fights back, the
fallbacks in order of preference are: point `luarocks` at the 5.1 tree explicitly
(`--lua-dir=/usr`), or install into a local tree and export `LUA_PATH`. Pulling in a third-party
action is the last resort, not the first: this repository currently uses `actions/checkout` and
nothing else.

Publish the summary in the job's step summary (`$GITHUB_STEP_SUMMARY`) and upload
`luacov.report.out` with `actions/upload-artifact`, so a reviewer can open the per-line report
without re-running anything.

**5. `luacov.stats.out` and `luacov.report.out` in `.gitignore`.** They land in the working
directory the run started from, which is the repository root.

**6. `test/lua/README.md`** gains the local recipe, both platforms — the Lua for Windows install
already ships `luacov`, so a developer on Windows needs no extra install:

    SKYNET_TEST_COVERAGE=1 lua5.1 test/lua/run.lua
    lua5.1 build-tools/report-test-coverage.lua

**7. A test that the loader still matches the build list.** Added while building the rest, because
the denominator has a hole this ticket would otherwise promise away: **luacov only knows about files
something executed.** A source added to `build-tools/listToMerge.txt` but not to
`test/lua/skynet-loader.lua`'s `ORDER` is never loaded by the suite, so it is not tested *and* not
counted — the percentage does not move, and nothing anywhere says a file is missing.

The loader's comment already claims `ORDER` is verbatim from `listToMerge.txt`; nothing enforced it.
`test/lua/test_harness_smoke.lua` — which is where the loader's own tests live — now reads the build
list and compares. `highdigitsams/` is the one documented omission and is skipped by name, so that
any *other* subdirectory appearing in the list fails the test instead of being skipped quietly.

`includeuntestedfiles` was tried first and rejected: the loader reaches the sources through
`test/lua/../../skynet-iads-source/`, luacov does not normalise that against `skynet-iads-source/`,
and every file ends up counted twice — once with its hits and once at 0%. It reported 35.35%.

## Watch out for

- The word. `test coverage` everywhere, never a bare `coverage` — in this repository that is what an
  EWR does to a battery. Name the job, the files and the environment variable accordingly.
- Do not add `highdigitsams/` to `test/lua/skynet-loader.lua`. Its omission from `ORDER` is
  deliberate and commented; loading it would add ~300 data lines scored 100%.
- `stylua --check` reports eleven pre-existing source files as unformatted on a Windows checkout
  with `core.autocrlf=true`. That is the line endings, not the branch: the same files are clean when
  checked with Unix endings, which is what CI has.

## Definition of done

- A pull request shows a test-coverage percentage without anyone running anything.
- The number matches what a developer gets locally from the same two commands.
- The measured figure at `4125b52` is **70.22%** — a first run landing far from it means the
  denominator policy did not apply, not that the suite changed.
- `lua5.1 test/lua/run.lua` still passes, unchanged, in its own job.
