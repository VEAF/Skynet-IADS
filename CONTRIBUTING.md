# Contributing

Who maintains Skynet-IADS, and how it got here, is in [`README.md`](README.md). What
matters for contributing is that **this repository is where the work happens** — issues, discussions
and pull requests belong here, not in either historical repository upstream.

One practical consequence, and it is a trap: this repository is a GitHub *fork*, so `gh pr create`
and the web UI's "Compare & pull request" banner both default to the **parent**. A pull request
opened without checking the base lands on a read-only archive and looks like it worked. Use
`gh pr create --repo VEAF/Skynet-IADS --base develop` — `--base master` only for a release's
promotion.

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
- **`gh`**, the GitHub CLI, logged in with `gh auth login`, to open pull requests from the command
  line. A browser does the same job.
- **`luacheck` and `stylua`**, for the lint gate. On Windows, `build-tools/lint.sh` looks for them
  and says in its header which variables to set — `LUACHECK_BIN`, `LUACHECK_TREE`, `LUA51` — when it
  cannot find them.
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
| `CONTEXT.md` | what Skynet is for, and what in its design looks like a bug and is not |
| `.tracker/` | work in progress and work done, and `IDEAS.md` — see *Tracking work* below |
| `.drafts/` | local working space, git-ignored |
| `.agents/` | configuration for agent toolsets — maps these rules onto a toolset, never restates them |
| `.github/pull_request_template.md` | the sections a pull request description is suggested to have |

## File naming

| Where | Pattern |
|---|---|
| root markdown | `UPPERCASE.md` |
| `skynet-iads-source/` | kebab-case, `skynet-iads-*.lua` |
| `build-tools/` | kebab-case |
| `documentation/` | kebab-case, with an `.en.md` twin |
| `test/lua/`, `test/python/` | kebab-case for infrastructure, `test_<snake_case>` for a test file |
| `.tracker/` | `<type>-<slug>/` for a piece of work, `archive/YYYY-MM-DD-<type>-<slug>/` once archived, lowercase kebab, the types as in *Git flow*; `spec.md` lowercase inside it; `IDEAS.md` uppercase |

The snake_case in the test directories is not an inconsistency: Python cannot import a module whose
name contains a hyphen, so `test/python/` has no choice, and `test/lua/` mirrors it.

Three exceptions:

- `build-tools/listToMerge.txt` is inherited camelCase, referenced by the build script,
  `.luacheckrc`, `.luacov` and two test files. Renaming it changes the build and the test harness in
  exchange for nothing but consistency.
- `.claude/skills/<kebab-name>/SKILL.md` is uppercase inside a kebab-cased directory because Claude
  Code requires that name.
- Records archived before these conventions keep their uppercase names —
  `.tracker/archive/YYYY-MM-DD-<NAME>.md` or `/` — because they are not rewritten.

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

One rule worth knowing before you get there:

- **The figures ED states about a unit are not ours to assert** — a missile's reach, its firing
  ceiling, a radar's detection distance. They are generated into `test/lua/dcs-figures.lua` from a
  pinned data dump, and a weekly workflow opens a pull request when one moves. Asserted inside a
  mission instead, a changed figure is a red test nobody sees for three years, which is what
  happened.

## Static analysis and formatting

`skynet-iads-source/` and `test/lua/` are gated by `luacheck` and `stylua --check`
(`.github/workflows/lint.yml`). Run both the way CI does:

```
bash build-tools/lint.sh       # or: bash build-tools/lint.sh luacheck
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
tracker, this file. The users of this project are not only French-speaking.

What a *user* reads is the exception, and only there: the site is French at the root with English
under `/en/`, and `README.md` carries both.

## Writing guidance

The guidance files are the instruction files at the root — `CLAUDE.md`, this file, `CONTEXT.md` and
`README.md` — and the skills under `.claude/skills/`. They follow six rules.

- **A rule is stated once**, with its reasons and edge cases, and every other file points at it. A
  command may be repeated, and so may a rule in `CLAUDE.md` given bare, with at most a clause of why:
  a drifting copy of either fails loudly. An explanation is never repeated.
- **A rule states its own reason.** It never cites a piece of work, an issue, a commit, a person or a
  date to justify itself; that history is in `.tracker/` and the pull requests, for whoever asks why.
- **No consumer is named.** Other repositories vendor what this one ships; say that, not which. A
  skill describing a procedure may show a consumer's configuration as an example beside the direct
  way, never as the only way.
- **No agent skillset is named**, and no practice is justified by one. What a toolset needs to fit
  these rules is configuration, and lives in `.agents/`.
- **A pointer names a file**, never a heading or an anchor. A heading is reworded as a matter of
  course; a file is rarely renamed, and never quietly.
- **`CLAUDE.md` is read in every agent session**, so each line in it must prevent a mistake. What it
  delegates is reached through its table, one row per kind of task.

## How a change is made

These steps are mandatory, whatever tools you work with.

1. **Check what is already known** before proposing a change to how something behaves: search
   `.tracker/`, its archive and `IDEAS.md` included.
2. **Open the work**, if it needs a spec — see *Tracking work*: commit
   `.tracker/<type>-<slug>/spec.md` straight to `develop` with `Status: in-progress`, then branch
   from that commit. A spec committed as `open` is taken up the same way later. The idea the work
   takes up, if any, leaves `IDEAS.md` in the same commit.
3. **Branch** from an up-to-date `develop`, named as *Git flow* says.
4. **Test first**, then implement — see *Test first*.
5. **Run the suite and the lint gate.** When only DCS can show that the change works, say so.
6. **Add a `CHANGELOG.md` entry** for any change to `skynet-iads-source/` — see *Changelog and
   versioning*.
7. **Commit** as *Git flow* says.
8. **Open a pull request to `develop`.** Its description says what changed and why, and how it was
   verified — including "not flown" when it was not tested in DCS — and carries `Closes #N` when it
   answers a GitHub issue. `.github/pull_request_template.md` suggests sections for it; they are a
   helper, not a required structure. Amendments to the spec ride with the pull request, down to
   `Status: done`, set by the last pull request when the work spans several. A decision that
   warrants it — most do not: the code, the spec and the pull request carry them — goes into
   `CONTEXT.md` or this file in the same pull request.
9. **Merging is a maintainer's call.**
10. **Archive** the work's folder, at your discretion, once its last pull request has merged or it
    has been dropped — see *Tracking work*.

## Tracking work

`.tracker/` records work in progress and work done. It is not a backlog: what might be done some day
is an entry in `.tracker/IDEAS.md`, or a GitHub issue when it comes from outside.

```
.tracker/
  IDEAS.md                           prospective work
  <type>-<slug>/                     one piece of work
    spec.md                          the only required file
    …                                anything else, at the contributor's discretion
  archive/
    YYYY-MM-DD-<type>-<slug>/        a piece of work merged or dropped
```

`<type>` and `<slug>` are those of the branch carrying the work: `fix/stale-harm-silence` goes with
`.tracker/fix-stale-harm-silence/`.

**A spec is worth writing** when there is something to decide before coding, or when the work will
span several pull requests. Otherwise a branch and a pull request are enough. The threshold is your
call. A suggested shape: the problem; what to build; the decisions taken, with the alternatives
turned down and why; what is out of scope; discussion appended under `## Comments`. A spec is kept
true while the work is under way, and is a record once its pull request has merged: from then on it
is not edited.

What is strict is only what a search relies on:

- **The location.** A piece of work is a folder directly under `.tracker/`, with `spec.md` at its
  root.
- **The `Status:` line** is the first line of `spec.md` after its title:

  | Status | Meaning |
  |---|---|
  | `open` | Written, not started |
  | `in-progress` | Someone has taken it on. Its work is carried by the branch `<type>/<slug>`, created from the commit that sets this status |
  | `blocked` | Waiting on something or someone — the line says what, and who is expected to act |
  | `paused` | Deliberately set aside: nobody picks it up and nothing is expected of anyone — the line says what would restart it. For work whose spec, or branch, is worth keeping as it is; work never really started goes back to `IDEAS.md` instead |
  | `done` | The work is complete. Set in the pull request itself, so that it reaches `develop` when the pull request merges and never before |
  | `dropped` | Decided against — the line or the spec says why, so that it is not reopened without a new reason |

  What is under way is found by search, not by an index:
  `grep -l "Status: in-progress" .tracker/*/spec.md`. Only the spec is searched: a file a toolset
  adds beside it may carry a status line of its own. Anything in `archive/` is finished; the records
  archived before these conventions carry no such line, and their outcome is in their text.
- **The archive.** A folder moves as it is to `archive/YYYY-MM-DD-<type>-<slug>/`, the date being the
  day its last pull request merged or, for dropped work, the day it was dropped.
- **`IDEAS.md`** is a free list. An idea taken up leaves it in the commit that opens its spec. A
  dropped idea stays, with its reason, so that the search before a proposal finds it.

The state is never part of a file name: a rename on each change of state would break every link to
the file and scatter its history. The archive's date is set once, when it moves.

**GitHub issues are for reports from outside.** A report that becomes work gets a folder whose spec
links to it, and the pull request closes it.

## Git flow

- `develop` is the default branch and the target of every pull request. `master` carries releases
  and receives them only through *Releasing*.
- Branch from `develop` as `<type>/<slug>`. `<type>` is one of `feat`, `fix`, `docs`, `chore`,
  `refactor`, `test` — the Conventional Commits types — and `<slug>` is lowercase kebab. A release
  uses `release/<x.y.z>`, then `release/<x.y.z>-freeze`. Work spanning several pull requests reuses
  its slug, suffixed `-2`, `-3`… after the first.
- Never commit directly to `develop` or `master`. **One exception, and it is the whole of it**: a
  change confined to `.tracker/` — opening a piece of work, a status change, an idea, archiving —
  goes straight to `develop`. A pull request whose entire diff is the tracker costs a review cycle
  and protects nothing CI can check. Anything outside that directory goes through a branch and a pull
  request, including a one-line change, and including a change to a guidance file: a rule everyone
  then works from is exactly what review is for.
- Split commits sensibly. A commit that mixes unrelated subjects cannot be read, reverted or bisected
  apart; beyond that there is no hard rule.
- Pull requests are merged with a **merge commit**, never squashed or rebased, so that those commits
  stay readable apart.
- [Conventional Commits](https://www.conventionalcommits.org/), in English.
- Branches are deleted on merge — this is automatic.

## Changelog and versioning

Every pull request that changes `skynet-iads-source/` adds an entry to `CHANGELOG.md`, appended at
the **end** of the `[Unreleased]` section.

This is not bookkeeping. What this project ships is a script other repositories vendor into the
missions they build, so a change here reaches no mission until one of them takes a new copy — a
deliberate step on their side, and one that has lagged a long way behind before now. The changelog is
how whoever is deciding knows whether a new build is worth taking.

[Semantic versioning](https://semver.org/), continuing the **artifact's** lineage rather than the
inherited tags, because the artifact's number is what people read in a log. A change to what a
mission sees at runtime is at least a minor. `CHANGELOG.md` carries how the two numbering schemes
were reconciled, and is the only place that story is told.

## Releasing

A release follows these steps. Every one that writes to `develop` or `master` goes through a pull
request.

Before the first, fly the release candidate: the in-sim smoke checks in `unit-tests/README.md` run
where CI cannot, since GitHub runners have no DCS. They are consultative, not a gate — but a release
that goes out unflown says so.

1. **Prepare**, on a `release/<x.y.z>` branch: bump `SkynetIADS.version` in
   `skynet-iads-source/skynet-iads.lua`, and write the release notes under `## [Unreleased]` in
   `CHANGELOG.md`. Pull request to `develop`.
2. **Promote**: a pull request from `develop` to `master`, merged with a merge commit.
3. **Tag** `v<x.y.z>` on `master` and push it. `.github/workflows/release.yml` builds, checks and
   publishes the release, taking its notes from `## [Unreleased]` as it stands. A tag that is not a
   plain `vX.Y.Z` publishes as a pre-release.
4. **Freeze the changelog**, on a `release/<x.y.z>-freeze` branch: rename `[Unreleased]` to
   `[x.y.z] — YYYY-MM-DD` and open a fresh `[Unreleased]` above it. Pull request to `develop`. This
   comes after the tag because the workflow reads `[Unreleased]` literally: renamed earlier, the
   release would ship with empty notes.
5. **Tell whoever vendors the script** that a release is out. Nothing reaches a mission until a
   consuming repository takes the new copy.

A tag is never reused or moved. If a release is wrong, cut the next one.
