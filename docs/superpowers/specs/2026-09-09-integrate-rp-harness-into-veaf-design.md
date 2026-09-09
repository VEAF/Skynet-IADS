# Integrate the RP standalone test harness into VEAF/Skynet-IADS — design

**Date:** 2026-09-09
**Status:** approved, pending implementation plan
**Where the work happens:** the local **VEAF** clone at
`D:\Projects\DcsLua\Skynet-IADS-VEAF` (`origin` → `VEAF/Skynet-IADS`), on branch
`feat/integrate-rp-test-harness` cut from `origin/master` (`cde577d`). RP is
pulled in as a second remote (`rp` → `regroupement-patrouille/Skynet-IADS`) in
that same clone. The local RP clone at `D:\Projects\DcsLua\Skynet-IADS` is
read-only for this milestone — nothing is committed there; RP `master` is
consumed only via `rp/master` (`d94e8c8`) fetched into the VEAF clone.
**Predecessors (RP fork):**
`docs/superpowers/specs/2026-09-03-standalone-lua-tests-design.md` (M1),
`docs/superpowers/specs/2026-09-06-standalone-lua-tests-m2-design.md` (M2) —
both removed from RP `master` in `35db8db` as working docs; summarised below.

## Problem

`walder/Skynet-IADS` has two active downstream forks that diverged at `f18b919`:

- **`regroupement-patrouille/Skynet-IADS`** (RP, `master` = `d94e8c8`) added a
  standalone Lua test harness under `test/lua/` — luaunit on a plain Lua 5.1
  interpreter, no DCS — plus a CI workflow. 8 of the 12 `unit-tests/` suites now
  also run there. Two one-function source fixes rode along.
- **`VEAF/Skynet-IADS`** (`master` = `cde577d`) added four gameplay / infra
  fixes: the SAM-goes-dark fix (`3a94937`), the MiST removal + `skynet-iads-utils.lua`
  (`fe40c4a`), the destroyed-group discovery fix (`458b64f`), and the scheduler
  past-start clamp (`cde577d`).

VEAF is now the reference fork for RP's missions and the repo is consolidating
under the VEAF organisation. The two histories need to become one, with VEAF as
the canonical line.

The merge is **clean in both directions** — verified by trial merge, zero
conflicts, 22 files auto-merged, the only both-sides file
(`skynet-iads-source/skynet-iads-contact.lua`) resolved automatically because
the two forks changed different functions in it. The forks are disjoint in
practice: RP's surface is almost entirely new files under `test/lua/`, VEAF's is
in `skynet-iads-source/` and `demo-missions/`.

## Goal

One branch on `VEAF/Skynet-IADS` that is a strict superset of both forks:

- the RP standalone harness and CI, **green against MiST-free source**
- the `feature-inform-bomb-contact` feature merged in
- the build script hardened against the README-truncation failure (VEAF issue #4)

Then a PR into `VEAF/master`; VEAF becomes canonical and `regroupement-patrouille/Skynet-IADS`
is archived.

## Non-goals

- **VEAF issue #3** (`cleanUp()` leaves `harmSilenceID` stale). Real bug, present
  in this codebase, but out of scope here. The issue stays open.
- **Porting the DCS-only orchestrator suites** (`test-skynet-iads.lua`,
  `abstract-radar-element`, `early-warning-radar`, `red/blue-sam-sites-and-ew-radars`)
  and building the demo-IADS-world fixture. That is the **next milestone**, with
  its own spec, to be started immediately after this one lands. The SAM-dark
  regression test and an inform-of-bomb-contact test are part of that milestone.
- Recompiling for a version bump, luacheck/StyLua/luacov, `highdigitsams/`.

## What each fork brings

### RP `master` (`f18b919..d94e8c8`) — full inventory

| Type | Path | Origin |
|---|---|---|
| add | `.github/workflows/lua-tests.yml` | CI: `lua5.1 test/lua/run.lua` on push + PR |
| add | `test/lua/` — 18 files (harness + 8 ported suites + `README.md`) | M1 + M2 |
| modify | `contributing.md` | documents the standalone suite |
| modify | `skynet-iads-source/skynet-iads-contact.lua` | `ef37ead` — `getTypeName` returns the type name for WEAPON contacts, not only UNIT |
| modify | `skynet-iads-source/skynet-iads-supported-types.lua` | `d94e8c8` — `Zues` → `Zeus` |

No changes to `unit-tests/`, no deletions anywhere. The `test/lua/` suites are a
**parallel** re-implementation; the `unit-tests/*.miz` originals are untouched
and remain the simulator-dependent functional/smoke suites.

`test/lua/` layout (M1 + M2):

| File | Purpose |
|---|---|
| `luaunit.lua` | vendored luaunit 3.4, unmodified |
| `skynet-loader.lua` | loads `skynet-iads-source/*.lua` in build order; `load(name)` / `loadAll()` |
| `dcs-stub.lua` | fake DCS scripting env + fixture factories (`makeUnit/makeGroup/makeStatic`), a **controllable fake scheduler exposed as `mist.scheduleFunction`/`mist.removeFunction`**, `timer.getAbsTime`, `AI.Option`, `land`, `world` event registry |
| `mist-stub.lua` | the pure-math slice of `mist` the source calls — `mist.utils.round/toDegree/metersToNM/metersToFeet/get2DDist/get3DDist`, `mist.random`, `mist.getHeading` — each `-- copied from demo-missions/mist_4_5_107.lua` |
| `dcs-fixtures.lua` | SAM/EW group builders, connection-node units, `iadsContact()` factory |
| `run.lua` | discovers and runs every `test_*.lua` as a child process, aggregates exit codes |
| `test_*.lua` | 8 ported suites + `test_harness_smoke`, `test_dcs_stub`, `test_dcs_fixtures`, `test_mist_stub` |

Ported suites: `harm-detection`, `abstract-dcs-object-wrapper`,
`moose-a2a-connector` (1 of 3 tests), `jammer`, `abstract-element`, `sam-site`,
`contact` (M1 pilot). Still DCS-only: `early-warning-radar`,
`abstract-radar-element`, `iads`, `red/blue-sam-sites-and-ew-radars`.

### VEAF `master` (`f18b919..cde577d`) — already on the branch

`skynet-iads-utils.lua` (new) reproduces 13 MiST helpers with no outside
dependency: the arithmetic (`round`, `metersToNM`, `metersToFeet`, `toDegree`,
`get2DDist`, `get3DDist`, `makeVec3`), headings (`getNorthCorrection`, `getDir`,
`getHeadingPoints`, `getHeading`), `random`, a repeating **scheduler**
(`scheduleFunction`/`removeFunction`, built on the real
`timer.scheduleFunction`, with a `MINIMUM_DELAY = 0.01` clamp on the first run
and MiST's pcall-guard on repeating tasks), and two mission listings
(`getUnitNames`, `getGroupNames`, via `forEachLiveGroup` which skips destroyed
groups). All 31 call sites across 8 source files now call `SkynetIADSUtils.*`
instead of `mist.*`. `demo-missions/mist_4_5_107.lua` stays (demo `.miz` files
still inject it); the compiled artefact is regenerated and holds no `mist.` call.

## The collision, and the work

After the squash-merge the source calls `SkynetIADSUtils.*`. The RP harness was
built against source that called `mist.*`. Concretely:

1. **`mist-stub.lua` is now dead for the source path.** Its functions duplicate
   `skynet-iads-utils.lua` (both copied from `mist_4_5_107.lua`). The real
   module should be loaded instead and the stub deleted.
2. **The fake scheduler moves down a layer.** `dcs-stub.lua` exposes the
   controllable scheduler as `mist.scheduleFunction`/`mist.removeFunction`. The
   source now calls `SkynetIADSUtils.scheduleFunction`/`removeFunction`, whose
   real implementation calls the DCS API `timer.scheduleFunction(fn, arg, time)`
   — which the stub does **not** provide. Decision: the stub grows a
   controllable `timer.scheduleFunction` and the **real** `SkynetIADSUtils`
   scheduler runs on top of it, so the tests exercise the seam the source
   actually uses (not a parallel fake).
3. **Semantics differ slightly.** The M2 fake `mist.removeFunction(id)` returns
   the id on a hit / `nil` otherwise; `SkynetIADSUtils.removeFunction` returns
   `true` / `false`. `test_dcs_stub.lua` and `test_skynet_iads_jammer.lua`
   assert the old shape.
4. **`skynet-iads-utils.lua` reaches DCS globals the stub lacks.**
   `getNorthCorrection` calls `coord.LOtoLL` / `coord.LLtoLO` (no `coord` in the
   stub today); `getUnitNames`/`getGroupNames` call `coalition.getGroups` /
   `coalition.side` (no `coalition`). The module only touches these inside
   functions, so it *loads* fine without them — they are needed only where a
   suite exercises that path.

## Plan

### Step 1 — prep  *(done)*

In `D:\Projects\DcsLua\Skynet-IADS-VEAF`:

```
git remote add rp https://github.com/regroupement-patrouille/Skynet-IADS.git
git fetch rp && git fetch origin
git checkout -b feat/integrate-rp-test-harness origin/master
```

`rp/master` = `d94e8c8`; `rp/feature-inform-bomb-contact` = `ad60e92`, identical
to `origin/feature-inform-bomb-contact`. The spec doc is committed on this branch
(`17e90c4`).

### Step 2 — squash-merge RP `master`

```
git merge --squash rp/master
git commit
```

One commit. Message records the squashed range (`f18b919..d94e8c8`), names the
M1/M2 specs by path, and carries `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
Brings the CI workflow, `test/lua/`, `contributing.md`, and the two source
fixes. `skynet-iads-source/skynet-iads-contact.lua` auto-merges.

At this point `lua5.1 test/lua/run.lua` is **expected to fail** — that is Step 3.

### Step 3 — repair the standalone harness  *(the real work; TDD)*

Gate: `lua5.1 test/lua/run.lua` green, exit 0, every suite passing.

1. **Loader** — add `skynet-iads-utils` to `skynet-loader.lua` `ORDER` as the
   **first** entry, ahead of `skynet-iads-supported-types` — the position
   `build-tools/build-compiled-script.ps1` concatenates it (it is a leaf
   dependency, no `require`s of its own). Confirm the smoke test's
   `loader.loadAll()` still succeeds.
2. **`dcs-stub.lua`** —
   - add a controllable `timer.scheduleFunction(fn, arg, time)` and the matching
     internal removal, so the **real** `SkynetIADSUtils` scheduler runs on it;
     keep a `dcsStub.scheduledCount()` helper and a way to fire due tasks
     explicitly (no auto-fire, matching M2). Remove the `mist.scheduleFunction` /
     `mist.removeFunction` shim.
   - add `coord.LOtoLL` / `coord.LLtoLO` returning values that make
     `getNorthCorrection` evaluate to `0` (grid heading == true heading in the
     standalone world, matching the current `mist-stub.lua` header decision).
   - add a minimal `coalition` (`.side`, `.getGroups`) **only if** a suite or the
     smoke test reaches it; otherwise leave it out and note why.
   - `dcsStub.reset()` clears any new mutable state.
   - extend `test_dcs_stub.lua` for the new scheduler shape and `coord`.
3. **Delete `mist-stub.lua`** and `test_mist_stub.lua`. Repoint every `test/lua`
   file that `dofile`s `mist-stub.lua` to load the real
   `skynet-iads-source/skynet-iads-utils.lua` via the loader. Where a test asked
   `mist.utils.round(...)` etc. directly for its own arithmetic, switch to
   `SkynetIADSUtils.*`. Drop the `mist` column from `test/lua/README.md` and the
   "every stubbed mist fn carries a copied-from comment" constraint.
4. **`test_skynet_iads_jammer.lua`, `test_dcs_stub.lua`** — replace the
   `mist.removeFunction(0..N)` iterate-count idiom and its `== id` assertions
   with `dcsStub.scheduledCount()` / the `true|false` return of
   `SkynetIADSUtils.removeFunction`.
5. **`contributing.md`, `test/lua/README.md`** — update the prose that describes
   `mist-stub.lua` and the MiST dependency.

Stub growth is reactive per failure, the M2 rule: if a call needs real simulator
behaviour rather than a stub, that suite is deferred and noted, not forced green.

### Step 4 — merge `feature-inform-bomb-contact`

```
git merge origin/feature-inform-bomb-contact
```

`ad60e92`, single commit, based on the shared ancestor `62aab46`. It rewrites
the contact-category filter in `SkynetIADS.evaluateContacts` (correctly handling
`Object.Category.WEAPON` so a Phalanx is told about inbound bombs). Touches lines
that neither `3a94937` nor `fe40c4a` touched — **expected clean; verify**. Rerun
`test/lua/run.lua`.

### Step 5 — harden the build script (VEAF issue #4)

In `build-tools/build-compiled-script.ps1`, before the README is regenerated:

```powershell
$toc = ./bin/gh-md-toc.exe --hide-footer ../skynet-iads-source/README_source.md
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($toc)) {
    Write-Error "Table of contents generation failed; leaving README.md untouched."
    return
}
```

Close VEAF issue #4.

### Step 6 — recompile + verify

- run the (now PS7-safe, now guarded) `build-tools/build-compiled-script.ps1`
- assert: all 20 `skynet-iads-source/*.lua` parse; `demo-missions/skynet-iads-compiled.lua`
  parses and contains **no `mist.` token**; the artefact still matches the
  previous one function-for-function apart from the inform-of-bomb-contact
  change and the two RP source fixes
- `git diff` shows no unintended `README.md` truncation
- CI green on the branch push

### Step 7 — PR into `VEAF/master`

- open the PR from `feat/integrate-rp-test-harness`; body cites both forks,
  the squashed RP range, and lists the deferred items (issue #3, the
  orchestrator-suite milestone)
- David reviews and merges
- archive `regroupement-patrouille/Skynet-IADS`; close RP PR #4 with a note that
  the fix landed here via the fork consolidation
- start the next milestone spec (demo-IADS-world fixture + orchestrator suites)

## Testing

- **Primary gate:** `lua5.1 test/lua/run.lua` — all suites green, exit 0 — after
  Step 3, again after Step 4, again after Step 6. Locally on Windows:
  `& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua`.
- **Parse check:** every `skynet-iads-source/*.lua` and the compiled artefact
  load under `luac -p` / `loadfile`.
- **No-MiST check:** `grep -rn 'mist[.:]' skynet-iads-source/` is empty;
  `grep -n 'mist' demo-missions/skynet-iads-compiled.lua` finds only
  `mist_4_5_107` unrelated strings, no calls.
- **CI:** `.github/workflows/lua-tests.yml` runs and passes on the branch.
- The `unit-tests/*.miz` suites are unchanged and still require a mission run;
  not part of this gate.

## Global constraints (carried from M1 / M2)

- Lua 5.1 only. No `goto`, `//`, bitwise ops, `table.unpack` (the source's
  `unpack or table.unpack` fallback stays). `os` / `io` only in `run.lua` and
  `test_*.lua` — never in `dcs-stub.lua`, `dcs-fixtures.lua`, `skynet-loader.lua`.
- `skynet-iads-source/*.lua` is loaded by the harness, not modified by it. The
  only source edits in this milestone are Step 5 (a build script, not source)
  and whatever Step 4's merge carries.
- Magic numbers in tests are recomputed from code-defined fixtures with the
  arithmetic shown in a comment; adjust the fixture, not the assertion.
- Commit trailer on every commit: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- `// FGA` trigram marks any customisation in a vendored / third-party file.

## Risks

- **Scheduler rewiring (Step 3.2/3.4).** The M2 fake scheduler and the real
  `SkynetIADSUtils` scheduler have different entry points and return shapes. The
  jammer suite's "is anything still scheduled?" checks are the brittle spot;
  they must move to `dcsStub.scheduledCount()` and assert intent (count → 0
  after `masterArmSafe()` / emitter destruction), not a specific id. Mitigated
  by porting through `test_dcs_stub.lua` first (scheduler semantics get their
  own tests before a suite depends on them).
- **`feature-inform-bomb-contact` merge (Step 4).** Expected clean but it and
  `3a94937` both live in `evaluateContacts`. If git flags a conflict, resolve by
  keeping both: `3a94937` changed the SAM-collection filter at the top of the
  loop, `ad60e92` changed the per-contact category test lower down.
- **`coord` / `coalition` stub fidelity.** If a ported suite does reach
  `getNorthCorrection` or `forEachLiveGroup`, a wrong stub silently shifts a
  heading or returns an empty listing rather than erroring. Mitigated by making
  `coord` yield exactly zero north-correction (documented, tested) and by adding
  `coalition` only when a suite forces it, with a fixture-backed assertion.
- **Squash loses M1/M2 commit granularity** from the canonical history. Accepted
  (decision E). The design rationale survives because the `docs/superpowers/`
  files come along in the squash; the squash message cites the range.
- **Divergent `skynet-iads-compiled.lua`.** RP let the artefact go stale (not
  rebuilt since `f18b919`); VEAF regenerates it every change. Step 6 makes VEAF's
  discipline the rule. If the recompiled artefact differs from VEAF's current one
  by more than the three intended changes, stop and diff before committing.

## Out of scope

- VEAF issue #3 (`harmSilenceID` cleanup).
- The demo-IADS-world fixture and the four DCS-only suites — next milestone.
- SAM-dark and inform-of-bomb-contact **standalone** regression tests — next
  milestone (they need the orchestrator fixture). VEAF's in-`.miz`
  `testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage` (from `3a94937`) is the
  interim coverage and rides in on the branch already.
- Version bump / release tagging.
- luacheck, StyLua, luacov, `.luarc.json`, devcontainer.
- Removing any `unit-tests/*.miz` suite.
