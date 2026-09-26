# Skynet-IADS — Claude Code Instructions

> Skynet gives DCS World an Integrated Air Defence System: early-warning radars feed contacts to SAM
> sites, which stay dark until the network tells them to engage. Pure Lua 5.1 sources in
> `skynet-iads-source/` are concatenated into a single deliverable `skynet-iads-compiled.lua` by a
> PowerShell build. Only the deliverable has to be pure Lua 5.1; tooling may be anything.

**`CONTRIBUTING.md` is the guide.** This file holds what you can get wrong before you would have any
reason to open it. Everything else is there.

## Behaviour (surgical mode)

- **Surgical**: never modify adjacent code, comments or formatting unrelated to the request. No
  opportunistic refactor.
- **Simplicity**: the minimum code that solves the problem. No speculative abstraction.
- **Zero assumptions**: if a specification is ambiguous or missing, stop and ask. Never invent DCS
  API behaviour — verify it against the [dcs-lua-datamine
  dataset](https://github.com/Quaggles/dcs-lua-datamine) or a real log.

## Never

- **Edit `demo-missions/skynet-iads-compiled.lua`.** It is the deliverable, concatenated from
  `skynet-iads-source/*.lua`. An edit there is lost at the next build, silently.
- **Edit a `.miz` by hand.** A script is wired into it in four places, and
  `build-tools/miz-suite.py` is what keeps them consistent.
- **Open a pull request against an upstream repository.** This repository is a GitHub *fork* of
  `regroupement-patrouille/Skynet-IADS`, so `gh pr create` without `--repo` targets the parent, and
  so does the web UI's "Compare & pull request" banner. Both that repository and walder's are
  read-only archives. Always `gh pr create --repo VEAF/Skynet-IADS --base develop`.
- **Commit directly to `develop` or `master`.** Work on `feature/*` or `fix/*` cut from `develop`.
  The one exception: a change confined to `.backlog/` may go straight to `develop`.
- **Add a source file to the build script.** The order lives in `build-tools/listToMerge.txt`.

## Commands

```
pwsh -File build-tools/build-compiled-script.ps1     # build the deliverable
lua5.1 test/lua/run.lua                              # the standalone suite; a name filters
bash build-tools/lint.sh                             # luacheck + stylua, as CI runs them
python build-tools/miz-suite.py build                # assemble the missions, before testing in DCS
```

If `lua5.1` is not on `PATH` — common on Windows — call the interpreter by its path. *Lua for
Windows* installs to the location below by default, and PowerShell needs the call operator because
the command line starts with a quoted path:

```powershell
& "C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua
```

`build-tools/lint.sh` exists because of that platform too: a luarocks `luacheck` often targets a
newer Lua than the interpreter that has to run it, and `core.autocrlf=true` makes `stylua --check`
flag every file for its line endings alone. The script works around both.

## Git flow

The rules, without their reasons or their edge cases. Those are in `CONTRIBUTING.md`, which is
where they are stated and the only place they may be changed.

- `develop` is the default branch and the target of every pull request. `master` carries releases.
- One branch and one pull request **per lot**. Splitting a lot across several is agreed before the
  first branch is cut, never as the work goes.
- A commit must not touch more than one ticket.
- Merge with a merge commit. Never squash, never rebase.
- Conventional Commits, in English. Branches are deleted on merge.
- Everything written in the repository is in English. What a *user* reads is the exception.

## Default workflow

Sync (`git pull --ff-only` on `develop`) → open or pick a lot **if the work needs one**
(`BACKLOG-CONVENTIONS.md` says when) → branch → implement
with its tests → run the suite → rebuild if the sources changed, and add a `CHANGELOG.md` entry if
they did → commit and push → pull request to `develop` → address review and CI → merge.

Nothing to do about the mission archives: they hold placeholders, and the mission DCS opens is
assembled on demand. That is the step to run before testing in DCS, not before committing.

If the change can only be judged inside DCS, stop and wait for explicit approval before continuing.

## Before you do these, read

| About to… | Read |
|---|---|
| change a source file | `CONTRIBUTING.md` — testing first, the build, the lint gate |
| add or change a test | `CONTRIBUTING.md` for which suite; `test/lua/README.md` for how to run and add one |
| touch `documentation/` | `CONTRIBUTING.md` — three conventions, all gated |
| touch a `.miz`, or test in DCS | `CONTRIBUTING.md`; `unit-tests/README.md` for the in-sim smoke gate |
| open a pull request | `CONTRIBUTING.md` — git flow and the changelog |
| create or edit a lot, a PRD or a ticket | `BACKLOG-CONVENTIONS.md` |
| change how sites, radars or the network behave | `CONTEXT.md` — what Skynet is for, and what in its design looks like a bug and is not |
| cut a release | the `release` skill |
| diagnose in-game behaviour from a log | the `skynet-runtime-debug` skill |

A row here means a new *kind* of task, never a new subsection of one already listed. A row names a
file, never a heading inside it.
