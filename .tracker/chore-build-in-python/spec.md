# The build is in Python, and builds the same bytes everywhere

Status: open

## The problem

`build-tools/build-compiled-script.ps1` is the last PowerShell script in the repository. It is the only
reason CI, the in-sim runner and every contributor need `pwsh`. It writes the compiled script into
`demo-missions/`, a git-ignored file sitting beside missions that will soon be committed. And two builds
of the same commit differ: the banner stamps the build time, and the line endings are the platform's.
A build that is not reproducible can only be compared by its version, so nothing can tell whether a
given file is the build of the current sources.

The test that the compiled script runs, `build-tools/check-artifact.lua`, is a test living outside
`test/`, under a name ("artifact") used nowhere else.

## The target

- **The build is a Python script** that returns the compiled text, and writes it to
  `build/skynet-iads-compiled.lua` by default. The file keeps its name: it is the release asset the
  documentation names.
- **The build is deterministic**: the same commit gives the same bytes on any machine. Whether a file is
  the build of the current sources is answered by building in memory and comparing, never by a hash of
  the sources.
- **The compiled-script test is a test of `test/lua/`**, and builds what it tests.

## What to build

### The build

`build-tools/build-compiled-script.py`, replacing the `.ps1`:

- reads `build-tools/listToMerge.txt` and concatenates the sources it lists, in its order, as today:
  blank lines and `#` comments skipped, every listed file must exist;
- reads the version from `SkynetIADS.version` in `skynet-iads-source/skynet-iads.lua`, and fails if it
  is not found;
- writes a first line `env.info("--- SKYNET VERSION: <version> ---")`, with no build time;
- reads every source as UTF-8, dropping a byte-order mark, and writes UTF-8 with LF line endings, each
  source's lines following the previous source's last line;
- exposes the build as a function returning the text, for the callers below; on the command line it
  writes `build/skynet-iads-compiled.lua`, or the path given by `--output`.

Its tests are `test/build-tools/test_build_compiled_script.py`: the order, the banner, a missing source,
a missing version, CRLF and LF sources giving the same output, a byte-order mark dropped, two builds
equal.

### The compiled-script test

`test/lua/test_compiled_script.lua` replaces `build-tools/check-artifact.lua`:

- it runs the Python build with `--output build/test/skynet-iads-compiled.lua`, never touching
  `build/skynet-iads-compiled.lua`;
- it loads that file against the DCS stub and runs it as a main chunk, failing if it raises — which is
  what the per-file source tests cannot see: a top-level `local` shadowing a later file's name, the
  200-locals limit of a single chunk, two files' lines merging;
- it tries `python3`, then `python`; an interpreter is found when `--version` succeeds through it, since
  on Windows `python3` can be the Microsoft Store alias, which exists and fails. It **skips with a
  visible message**, through `lu.skip`, when neither is found. It never fails because of what is, or is
  not, on disk; once an interpreter is found, a build that fails is a failure.

It is one test, not a suite of them.

### The callers

- `.github/workflows/build.yml`: builds with Python, then runs the compiled-script test instead of
  `check-artifact.lua`. No `pwsh`.
- `.github/workflows/release.yml`: the same, and attaches `build/skynet-iads-compiled.lua`.
- `.github/workflows/lua-tests.yml`: the `mission-archives` job's build step uses Python.
- `test/insim/skynet_script.py`: its copy in `build/insim/` is up to date when it equals an in-memory
  build. `skynet-script.json` and the sources hash go; `--skynet FILE` still forces a copy, which the
  next default run replaces. `test/insim-tools/test_insim_skynet_script.py` follows.
- `.gitignore`: the `demo-missions/skynet-iads-compiled.lua` entry goes; `/build/` already covers the
  output.

### The guidance and documentation

- `CONTRIBUTING.md`: *What you need* loses PowerShell; *Layout* and *Building* name the new script and
  `build/skynet-iads-compiled.lua`, and say the build is reproducible; *The missions are assembled, not
  committed* names the new build command.
- `CLAUDE.md`: the build command, and the compiled script's path in the summary and under *Never*.
- `.claude/skills/skynet-runtime-debug/SKILL.md`: the first line of the compiled script prints its
  version, no longer a build date.
- `test/insim/README.md`: its requirements lose `pwsh`. `test/lua/README.md`: the build command, and the
  compiled-script test.
- `.claude/skills/release/SKILL.md`: the compiled script's path.
- `skynet-iads-source/skynet-iads.lua`: the comment naming the build script.
- `documentation/index.md` and `index.en.md`: the build command a developer runs from a clone.
- `CHANGELOG.md`: the banner no longer carries the build time.

## Decided

| Decision | Turned down | Why |
|---|---|---|
| The build is Python | Lua 5.1, which the compiled-script test could call directly | only the deliverable has to be Lua 5.1; the in-sim runner and the demos' updater are Python and call the build |
| The banner carries the version alone | a build time; a hash of the rest of the file | a build time makes builds differ; a hash of the file cannot be inside the file without a second definition of what it covers. The version is enough to read a user's `dcs.log` |
| A file is identified by comparing it with an in-memory build | a hash of the sources, stored or stamped | it also sees a change to the build itself, and the build costs milliseconds |
| LF line endings in the output | the platform's | the same bytes on every machine; DCS does not care |
| The output goes to `build/` | `demo-missions/` | `demo-missions/` holds committed demos; `build/` is already the git-ignored output |
| The compiled-script test builds what it tests | reading `build/`, and failing or skipping when it is missing or stale | staleness can only be detected by building anyway, and the usual run must not go red on a fresh checkout |
| It skips only when Python cannot be found | failing | a missing interpreter says nothing about the code; CI always has Python |
| Its output goes to `build/test/` | a system temporary file; `.drafts/` | on Windows, Lua 5.1's `os.tmpname()` names a file at the drive's root, where writing may be refused; `.drafts/` is for specs and plans |

## Out of scope

- Where the stub, the fixtures and the loader live: `test-tooling-in-common`. Whichever of the two
  lands second follows the other's paths.
- The demo missions: `chore-demo-missions-carry-their-script`, which builds on this.
- `build-tools/miz-suite.py` and its tests. It still reads `demo-missions/skynet-iads-compiled.lua` and
  names the PowerShell build, so `miz-suite.py build` and the `mission-archives` job fail between the
  two pieces of work. `chore-demo-missions-carry-their-script` replaces it, follows this work at once,
  and both reach a release together.
- `docs-check.py` and the documentation build.
