# Skynet-IADS — Claude Code Instructions

> Skynet gives DCS World an Integrated Air Defence System: early-warning radars feed contacts to
> SAM sites, which stay dark until the network tells them to engage. Pure Lua 5.1 sources in
> `skynet-iads-source/` are concatenated into a single deliverable `skynet-iads-compiled.lua` by a
> PowerShell build. Only the deliverable has to be pure Lua 5.1; tooling may be anything.

**VEAF maintains this project.** `regroupement-patrouille/Skynet-IADS` is read-only and walder has
been inactive for years — the two communities agreed that VEAF takes it over. Never open pull
requests against either upstream, and never treat them as a source of truth.

## Language

English, everywhere: code, comments, commits, pull requests, documentation. The users of this
project are not only French-speaking.

## Behaviour (surgical mode)

- **Surgical**: never modify adjacent code, comments or formatting unrelated to the request. No
  opportunistic refactor.
- **Simplicity**: the minimum code that solves the problem. No speculative abstraction.
- **Zero assumptions**: if a specification is ambiguous or missing, stop and ask. Never invent DCS
  API behaviour — verify it against the [dcs-lua-datamine
  dataset](https://github.com/Quaggles/dcs-lua-datamine) or a real log.

## The generated deliverable — never edit it

`demo-missions/skynet-iads-compiled.lua` is the **deliverable**, concatenated from
`skynet-iads-source/*.lua`. Editing it is lost at the next build, silently.

`README.md` at the root is hand-written and short — a door pointing at the published documentation
in `documentation/`, built with MkDocs. See ticket 06 in `CHORE-PROFESSIONALIZE-THE-REPO`.

Build from any working directory — paths resolve from the script's own location, and the version
comes from `SkynetIADS.version` in `skynet-iads-source/skynet-iads.lua`, not from an argument:

```
pwsh -File build-tools/build-compiled-script.ps1
```

The source order lives in `build-tools/listToMerge.txt`, one path per line, commented with why the
order is what it is — edit that file to add or reorder a source, never the script.

CI (`.github/workflows/build.yml`) runs the build on every push and pull request, then loads and
executes the artifact against the DCS stub with `build-tools/check-artifact.lua` — a build proves
the files concatenate, not that the result runs. A tag matching `v*`
(`.github/workflows/release.yml`) builds, verifies, and publishes a GitHub release carrying the
artifact and the `[Unreleased]` section of `CHANGELOG.md`; a tag that is not a plain `vX.Y.Z` is
published as a pre-release.

## Documentation

The published documentation is `documentation/*.md`, built with MkDocs Material and versioned with
`mike`, deployed by `.github/workflows/docs.yml` to <https://veaf.github.io/Skynet-IADS/>. Prose
lives in exactly one place: either a page under `documentation/`, or the root `README.md` — never
both. `develop` publishes as `dev` (the site default while no stable release exists), `master` as
`latest`, and a tag as its own version — plus `latest` if the tag is a plain `vX.Y.Z`; a
pre-release tag publishes its own version only, so a release candidate never becomes what a
newcomer reads by default.

The deliverable is vendored by
[VEAF-Mission-Creation-Tools](https://github.com/VEAF/VEAF-Mission-Creation-Tools) under
`src/scripts/community/`. A change here reaches missions only once that repository re-vendors it,
which is a deliberate step on their side — the copy has run a month behind before now.

## Static analysis and formatting

`skynet-iads-source/` and `test/lua/` are gated by `luacheck` and `stylua --check`
(`.github/workflows/lint.yml`). `.luacheckrc` lists the DCS Scripting Engine's globals and this
project's own (every class is a bare global — DCS has no module system, and the sources are
concatenated, not required); `stylua.toml` excludes the vendored `test/lua/luaunit.lua` via
`.styluaignore`.

Run both gates the way CI does with `build-tools/lint.sh` (or one of them:
`build-tools/lint.sh luacheck`). On a Windows checkout it is the only thing that works without
fiddling: a luarocks `luacheck` often sits in a tree for a newer Lua than the interpreter that has
to run it and dies before checking anything, and `core.autocrlf=true` makes `stylua --check` flag
every file for line endings alone. The script works around both and exits non-zero on a real
finding.

`.luacheckrc` also pins a **ratchet**: warnings the first run already had, scoped to their exact
file and code, so a *new* warning of the same kind in the same file still fails. Fix new code
instead of extending it — it exists to erode, never to grow.

## Tests

- New **logic** tests go in `test/lua/`, run with `lua5.1 test/lua/run.lua` (a suite name filters:
  `lua5.1 test/lua/run.lua contact`). They use the DCS stub in `test/lua/dcs-stub.lua`.
- `unit-tests/*.miz` is the legacy in-sim suite, being migrated — two archives,
  `unit-tests/skynet-unit-tests.miz` and `unit-tests/highdigitsams/highdigitsams-unit-tests.miz`.
  Only behaviour that genuinely needs the simulator — terrain elevation, real detection geometry,
  in-game events, how a DCS group is composed — stays there. **The numeric figures ED states about a
  unit do not**: a missile's reach, its firing ceiling, a radar's detection distance are recorded in
  `test/lua/dcs-figures.lua`, generated from a pinned datamine commit, and a weekly workflow opens a
  pull request when one moves. A suite whose every assertion runs standalone is removed from both
  copies, the loose `unit-tests/*.lua` and the one inside the `.miz`.
- **The archives in git do not contain the scripts they run.** Each holds a placeholder, and
  `python build-tools/miz-suite.py build` assembles the playable mission into `build/missions/`,
  which is git-ignored — build the deliverable first, it is generated too. A committed copy of the
  code goes stale in silence: both archives ran Skynet 3.3.0 from December 2023 to 2026-09-20, so
  three years of in-sim runs measured code this project had stopped shipping. An assembled mission
  cannot, and one opened unbuilt says so on screen. Never edit a `.miz` by hand: a script is wired
  into it in four places, and `build-tools/miz-suite.py` (`build`, `check`, `stub`, `extract`,
  `remove`) is what keeps them consistent; every command covers both archives unless `--miz <path>`
  narrows it. CI runs `check`, assembles both missions and parses every Lua file in them on every
  pull request. See `test/lua/README.md`.
- **Test first**: write the failing test, make it pass, refactor. New or changed logic ships with
  its tests.
- **Test coverage is measured and gated** (`.github/workflows/lua-tests.yml`, `Test coverage` job):
  `SKYNET_TEST_COVERAGE=1 lua5.1 test/lua/run.lua` then
  `lua5.1 build-tools/report-test-coverage.lua`. It fails below the floor in
  `build-tools/test-coverage-floor.txt`, which **only goes up** — when your tests carry the figure
  past it, raise it in the same pull request; the report says when and to what. What counts is in
  `.luacov`: the pure data tables are out of the denominator, because loading one is not testing it.
- A test that passes only because the stub returns something convenient is worth nothing. When a
  test needs the stub extended, extend it deliberately and write down what real behaviour it stands
  in for.

## Git flow

- `develop` is the default branch and the target of every pull request. `master` carries releases.
- Work on `feature/*` or `fix/*` cut from `develop`. Never commit directly to `develop` or `master`.
- **One exception**: a change confined to `.backlog/` — a new lot, a status change, an index line —
  goes straight to `develop`. David's call, 2026-09-19: a pull request whose entire diff is the
  tracker costs a review cycle and protects nothing CI can check. The moment a change touches
  `skynet-iads-source/`, `test/`, `documentation/`, `CHANGELOG.md` or the build, it goes through a
  branch and a pull request — including a one-line change.
- One branch and one pull request per lot, not per ticket. A lot may be split across several pull
  requests when its tickets are genuinely independent, but **the split is announced in the plan and
  approved before the first branch is cut** — never decided ticket by ticket as the work goes.
  David's call, 2026-09-19, after `CHORE-PROFESSIONALIZE-THE-REPO` reached nine pull requests and
  `CHORE-TEST-COVERAGE-FLOOR` five, none of which he had been asked about. The rule already allowed
  the split; what was missing was his say in it.
- **One commit per ticket** inside a pull request. Two tickets in one commit reads fine at the time
  and is unreadable six months later: `FEAT-LAST-LINE-OF-DEFENSE` shipped the proximity wake-up and
  the coverage rebuild as a single commit (`0ebbc01`), so neither can be read, reverted or bisected
  on its own. Flogas caught it. A lot shared by two tickets does not justify a commit shared by two
  subjects.
- Conventional Commits, in English.
- Branches are deleted on merge.

## Backlog

`.backlog/` is the tracker: one directory per lot, holding `PRD.md` and one file per ticket under
`tickets/`, with `.backlog/README.md` as the hand-maintained index. Lots closed for more than a few
days are compacted into `.backlog/archive/<LOT-ID>.md`.

GitHub issues are for reports arriving from outside. A report that turns into work becomes a lot.
`docs/evolutions.md` is the idea tracker: an evolution is a thought, a lot is committed work.

## Default workflow

Sync (`git pull --ff-only` on `develop`) → create or pick a lot in `.backlog/` → branch → implement
with its tests → `lua5.1 test/lua/run.lua` → rebuild if the sources changed → update `CHANGELOG.md`
under `[Unreleased]`, appending at the **end** of the section → commit and push → pull request to
`develop` → address review and CI → merge.

Nothing to do about the in-sim archives: they hold placeholders, and the mission DCS opens is
assembled on demand by `python build-tools/miz-suite.py build`. That is the step to run **before**
testing in DCS, not before committing.

If the change can only be judged inside DCS, stop and wait for explicit approval before continuing.

## Domain

`CONTEXT.md` holds the vocabulary — what an IADS is here, what "covered" means, and the words the
code uses. Read it before touching the radar element hierarchy; several of its terms mean something
narrower than they sound.

## Agent notes

- Issue tracker and lot conventions: `docs/agents/issue-tracker.md`
- Status vocabulary: `docs/agents/triage-labels.md`
- Runtime diagnosis from a DCS log: the `skynet-runtime-debug` skill
- Cutting a release: the `release` skill (manual today — see
  `CHORE-PROFESSIONALIZE-THE-REPO` ticket 03)

## Bash

All Bash commands are authorized. Never block work waiting for approval on one.
