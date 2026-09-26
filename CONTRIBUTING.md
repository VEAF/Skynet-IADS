# Contributing

Skynet-IADS was built by [walder](https://github.com/walder/Skynet-IADS), whose repository has not
moved since 2024. It was forked to
[regroupement-patrouille](https://github.com/regroupement-patrouille/Skynet-IADS), and that fork was
forked again to the VEAF home you are reading now.

**VEAF and regroupement-patrouille (BFR, NAWACS) maintain the project jointly, here.** Both upstream
repositories are historical, so this is where issues, discussions and pull requests belong. One
practical consequence: because this repository is a GitHub *fork*, `gh pr create` and the web UI's
"Compare & pull request" banner both default to the parent. Check the base before opening one.

Before spending time on a feature, propose it: open an issue, or bring it to the
[VEAF Discord](https://discord.gg/veaf). Feedback before code saves more time than it costs.

## What you need

- **Lua 5.1.** The deliverable runs inside DCS, which is Lua 5.1 — no `goto`, no `<const>`, no
  `table.move`, no `utf8.*`. The standalone suite refuses to run on anything else. Where `lua5.1` is
  on `PATH` it is `lua5.1 test/lua/run.lua`; if it is not — common on Windows — install *Lua for
  Windows* and call it by its path, which PowerShell needs the call operator for:

  ```powershell
  & "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua
  ```

- **PowerShell**, for the build. `pwsh` (PowerShell 7) works on every platform.
- **Python**, for the documentation gate and the mission tooling.
- **DCS** is *not* required for most contributions. It used to be: the whole suite lived inside a
  mission. Logic is now testable on a plain interpreter, and DCS is needed only for what a stub
  cannot answer.
- **Any editor that speaks Lua.** With no preference, [VSCode](https://code.visualstudio.com/) and a
  Lua extension put the suite in the sidebar.

## Layout

| | |
|---|---|
| `skynet-iads-source/*.lua` | **the sources.** This is what you edit |
| `demo-missions/skynet-iads-compiled.lua` | **a build artifact.** Generated, git-ignored, never edited by hand |
| `test/lua/` | the standalone Lua 5.1 suite — **see its `README.md`** |
| `unit-tests/` | what needs DCS running — **see its `README.md`** |
| `demo-missions/*.miz` | what somebody downloads to see Skynet work. Not tests |
| `build-tools/` | the build script and its helpers |
| `documentation/` | the published site |
| `.backlog/` | what is planned, in progress and done |
| `BACKLOG-CONVENTIONS.md` | how the tracker works |

## File naming

| Where | Pattern |
|---|---|
| root markdown | `UPPERCASE.md` |
| `skynet-iads-source/` | kebab-case, `skynet-iads-*.lua` |
| `build-tools/` | kebab-case |
| `documentation/` | kebab-case, with an `.en.md` twin |
| `test/lua/`, `test/python/` | kebab-case for infrastructure, `test_<snake_case>` for a test file |
| `.backlog/` | `UPPERCASE.md` for files, `<LOT-ID>/` for a lot, `NN-slug.md` for a ticket |

The snake_case in the test directories is not an inconsistency: Python cannot import a module whose
name contains a hyphen, so `test/python/` has no choice, and `test/lua/` mirrors it.

Two exceptions:

- `build-tools/listToMerge.txt` is inherited camelCase, referenced by the build script,
  `.luacheckrc`, `.luacov` and two test files. Renaming it changes the build and the test harness in
  exchange for nothing but consistency.
- `.claude/skills/<kebab-name>/SKILL.md` is uppercase inside a kebab-cased directory because Claude
  Code requires that name.

## Building

Run from anywhere in the repository — paths resolve from the script's own location:

```powershell
pwsh -File build-tools/build-compiled-script.ps1
```

It produces `demo-missions/skynet-iads-compiled.lua`, the concatenation of every source listed in
`build-tools/listToMerge.txt`, in the order that file states. **That is where a new source file gets
added — never to the script.** The version in the artifact's first line comes from
`SkynetIADS.version` in `skynet-iads-source/skynet-iads.lua`; there is no argument to pass.

CI runs the same build on every push and pull request (`.github/workflows/build.yml`), then loads and
executes the artifact against `test/lua/dcs-stub.lua` — a build proves the sources concatenate, not
that the result runs without raising. A tag matching `v*` (`.github/workflows/release.yml`) builds,
verifies and publishes a GitHub release carrying the artifact and the changelog's `[Unreleased]`
section; a tag that is not a plain `vX.Y.Z` publishes as a pre-release.

### The missions are assembled, not committed

No `.miz` in git contains the scripts it runs — not the three under `unit-tests/`, not the three
under `demo-missions/`. Each holds a placeholder, and the mission DCS opens is built on demand:

```
pwsh -File build-tools/build-compiled-script.ps1
python build-tools/miz-suite.py build
```

They land in `build/missions/`, which is git-ignored. Run that **before testing in DCS**, never
before committing — there is nothing to commit, which is the point. A committed copy of the code
goes stale in silence, and did: the in-sim archives ran a December 2023 build for three years.

**Never edit a `.miz` by hand.** A script is wired into one in four places, and
`build-tools/miz-suite.py` is what keeps them consistent. `test/lua/README.md` has the wiring and the
rest of the commands.

Only `demo-missions/` archives are attached to a release. Everything under `unit-tests/` is developer
material and never is.

## Test first

Write the failing test, make it pass, then refactor. It takes a little longer the first time and
saves the afternoon you would otherwise spend re-testing by hand after a two-line change.

**Do not open a pull request with tests failing.**

There are two suites, and which one you want is decided by whether a stub can answer the question:

| | Where it runs | What belongs in it | Its door |
|---|---|---|---|
| `test/lua/` | plain Lua 5.1, and CI on every pull request and on pushes to `develop` and `master` | **logic** — state machines, parsing, arithmetic, branching. **New logic tests go here** | [`test/lua/README.md`](test/lua/README.md) |
| `unit-tests/` | inside DCS | what a stub cannot answer — terrain, real detection geometry, in-game events, how a DCS group is composed, and whether the simulator calls the code at all | [`unit-tests/README.md`](unit-tests/README.md) |

Those two files are the reference: how to run each suite, how to add to it, what is covered and what
deliberately is not, and how the coverage floor works. None of it is repeated here, because a summary
of a procedure is a second copy of it.

Two rules worth knowing before you get there:

- **A test that passes only because `dcs-stub.lua` returned something convenient proves nothing.**
  When a test needs the stub extended, extend it deliberately and write down which real DCS behaviour
  it stands in for.
- **The figures ED states about a unit are not ours to assert** — a missile's reach, its firing
  ceiling, a radar's detection distance. They are generated into `test/lua/dcs-figures.lua` from a
  pinned data dump, and a weekly workflow opens a pull request when one moves. Asserted inside a
  mission instead, a changed figure is a red test nobody sees for three years, which is what
  happened.

## Static analysis and formatting

`skynet-iads-source/` and `test/lua/` are gated by `luacheck` and `stylua --check`
(`.github/workflows/lint.yml`). Run both the way CI does:

```
build-tools/lint.sh            # or: build-tools/lint.sh luacheck
```

On a Windows checkout that script is the only thing that works without fiddling: a luarocks
`luacheck` often sits in a tree built for a newer Lua than the interpreter that has to run it, and
`core.autocrlf=true` makes `stylua --check` flag every file for its line endings alone. The script
works around both and exits non-zero only on a real finding.

`.luacheckrc` lists the DCS Scripting Engine's globals and this project's own — every class is a bare
global, because DCS has no module system and the sources are concatenated rather than required.
`stylua.toml` excludes the vendored `test/lua/luaunit.lua` through `.styluaignore`.

`.luacheckrc` also pins a **ratchet**: the warnings the first run already had, scoped to their exact
file and code, so a *new* warning of the same kind in the same file still fails. Fix new code instead
of extending the list — it exists to erode, never to grow.

## Documentation

`README.md` is a short, hand-written entry point. The documentation is `documentation/*.md`, built
with MkDocs Material, versioned with `mike` (`.github/workflows/docs.yml`) and published at
<https://veaf.github.io/Skynet-IADS/>. Preview it with
`pip install -r build-tools/docs-requirements.txt && mkdocs serve`. **Prose lives in exactly one of
the two places, never both** — check before adding to either.

The site is served in French at the root and in English under `/en/`: `page.md` is the French text,
`page.en.md` its English twin, through `mkdocs-static-i18n`. `README.md` carries both languages in
one file, English first. Three rules come with that, all checked by
`python build-tools/docs-check.py`:

| Rule | Why |
|---|---|
| A page ships with its twin, or not at all | The plugin falls back instead of failing: the URL of an untranslated page serves the other language, and nothing says so — not even `--strict`, which logs a page outside the nav as `INFO` |
| A heading a cross-page link targets declares its anchor — `## Point defence {#point-defence}` — with the same id in both languages | A generated anchor comes from the heading text, so it differs between the twins and dies on the next reword |
| An English page links to `page.en.md` | Style, not breakage: measured on a real build, the plugin rewrites either spelling to the same URL. The rule keeps what the file says and what the reader gets from drifting apart |

Run the gate and `mkdocs build --strict` before pushing; both also run on the pull request
(`.github/workflows/docs-check.yml`).

**Which version the site shows.** `develop` publishes as `dev`, the site default while no stable
release exists. A tag publishes its own version, plus the `latest` alias if it is a plain `vX.Y.Z` —
a pre-release publishes its own version only, so a release candidate never becomes what a newcomer
reads by default. `master` publishes nothing of its own: a tag is always on `master`, so between two
releases `master` is not on the site.

A documentation fix landing between two releases therefore reaches nobody until the next tag.
`gh workflow run docs.yml -f version=3.5.0` republishes that version's **pages** from the current
branch and leaves the tag, the artifact and the version number alone. Run it from `develop`, and only
when the pages genuinely describe the released code; omit `version` to redeploy `dev`. It does not
move `latest` and does not need to — mike rebuilds every alias directory a version already owns, so
republishing the newest release refreshes `/latest/` on its own. `-f set_latest=true` makes a version
*become* `latest`, which on an older one drags the site default back to old documentation while the
run stays green.

## Language

**English for everything inside the repository**: code, comments, commit messages, pull requests, the
backlog, this file. The users of this project are not only French-speaking.

What a *user* reads is the exception, and only there: the site is French at the root with English
under `/en/`, and `README.md` carries both. See [Documentation](#documentation).

## Git flow

- `develop` is the default branch and the target of every pull request. `master` carries releases.
- Branch from `develop`: `feature/<something>` or `fix/<something>`. Never commit directly to
  `develop` or `master`.
- **One exception**: a change confined to `.backlog/` — a new lot, a status change, an index line —
  goes straight to `develop`. A pull request whose entire diff is the tracker costs a review cycle
  and protects nothing CI can check. The moment a change touches `skynet-iads-source/`, `test/`,
  `documentation/`, `CHANGELOG.md` or the build, it goes through a branch and a pull request,
  including a one-line change.
- One branch and one pull request per lot, not per ticket. A lot can be split across several pull
  requests when its tickets are genuinely independent — agree the split before starting, rather than
  discovering it halfway through.
- A commit must not touch more than one ticket. Two subjects in one commit cannot be read, reverted
  or bisected apart. The rule is against mixing, not about counting: opening the lot is its own
  commit, a ticket may need more than one, and a review response is appended rather than squashed
  back into the ticket it amends.
- Pull requests are merged with a **merge commit**, never squashed or rebased. A squash collapses the
  branch into one commit and destroys the per-ticket history the rule above exists to keep.
- [Conventional Commits](https://www.conventionalcommits.org/), in English.
- Branches are deleted on merge — this is automatic.

## Changelog and versioning

Every pull request that changes `skynet-iads-source/` adds an entry to `CHANGELOG.md`, appended at
the **end** of the `[Unreleased]` section.

This is not bookkeeping. The main consumer of this project is another repository —
[VEAF-Mission-Creation-Tools](https://github.com/VEAF/VEAF-Mission-Creation-Tools) vendors the built
artifact under `src/scripts/community/` — and the changelog is how they know whether a new build is
worth taking. A change here reaches missions only once that repository re-vendors it, a deliberate
step on their side; that copy has run a month behind without anyone noticing.

[Semantic versioning](https://semver.org/), continuing the **artifact's** lineage rather than the
inherited tags, because the artifact's number is what people read in a log. A change to what a
mission sees at runtime is at least a minor. `CHANGELOG.md` carries how the two numbering schemes
were reconciled, and is the only place that story is told.
