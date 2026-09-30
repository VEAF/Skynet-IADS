# Repository conventions — how work is tracked

Status: done

The rules this repository adopts for tracking work, replacing `.backlog/` and
`BACKLOG-CONVENTIONS.md`. Once they have landed, they live in `CONTRIBUTING.md`, and this spec is the
record of why they are shaped this way.

The first part of this work — `CONTRIBUTING.md` as the single source, `CLAUDE.md` reduced to what
prevents mistakes, `CONTEXT.md` cut to intent, `docs/` removed — was carried out under the previous
conventions and is recorded beside this file, in `PRD.md` and `tickets/`. This spec covers the
second part: how work is tracked, and everything that follows from it.

## Principles

- **The rules do not depend on a tool.** A contributor may work with any agent or skillset, or with
  none. Every mandatory step can be followed from `CONTRIBUTING.md` alone.
- **No skillset is named outside `.agents/`.** A guidance file never justifies a practice by a
  skillset, and never names one. This spec names Pocock's skills and superpowers only to explain
  why a choice was made; none of those explanations moves into the guidance files.
- **The tracker records work in progress and work done.** It is not a backlog: what might be done
  some day is an entry in `IDEAS.md`, or a GitHub issue when it comes from outside.
- **Flexible by default, strict where something depends on it.** The few hard conventions are the
  ones a tool or a search relies on. Everything else is recommended.
- **Agents propose, people decide.** Every record is plain markdown a person can read without an
  agent to interpret it.
- **Stated once.** A rule, a list or a procedure lives in one guidance file and the others point at
  it. It is repeated only where pointing is not practical — a command someone must run, a
  prohibition an agent could break before it has any reason to open another file.
- **The vocabulary is the tracker's own.** Work is a *piece of work*, described by its *spec*.
  *Lot*, *PRD*, *ticket* and the status glyphs survive only in the historical records, which are not
  rewritten.

## Where everything lives

| What | Where |
|---|---|
| Rules, practices, mandatory steps | `CONTRIBUTING.md` — the single source |
| Design intent: what looks like a bug and is not | `CONTEXT.md` — only when warranted, never code mechanics, never what the code already shows. Updated in the pull request that settles it, or in one of its own when a misunderstanding surfaces outside any change, such as an agent's wrong assumption |
| Work in progress and work done | `.tracker/`, committed |
| Prospective work | `.tracker/IDEAS.md` |
| Reports from outside | GitHub issues |
| Why a change was made, how it was verified | The pull request description, and the spec when there is one |
| Local studies, brainstorms, agent specs and plans | `.drafts/`, git-ignored |
| Agent entry points | `CLAUDE.md` and `.claude/` for Claude Code; another tool's own fixed path when someone needs it |
| Toolset configuration | `.agents/` — maps these rules onto a toolset's vocabulary, never restates them |

## The tracker

### Layout

```
.tracker/
  IDEAS.md                           prospective work
  <type>-<slug>/                     one piece of work
    spec.md                          the only required file
    …                                anything else, at the contributor's discretion
  archive/
    YYYY-MM-DD-<type>-<slug>/        a piece of work merged or dropped
```

`<type>` is one of `feat`, `fix`, `docs`, `chore`, `refactor`, `test` — the Conventional Commits
types — and `<slug>` is lowercase kebab. The branch carrying the work has the same type and slug:
`fix/stale-harm-silence` goes with `.tracker/fix-stale-harm-silence/`. In `CONTRIBUTING.md` the type
list is stated once, in *Git flow*; the tracker and *File naming* point at it.

### File names

Written in `CONTRIBUTING.md`'s *File naming*, as one row for `.tracker/`:

- **Folders** are lowercase kebab: `<type>-<slug>/`, and `archive/YYYY-MM-DD-<type>-<slug>/`.
- **`spec.md`** is a fixed, lowercase name, so that a search or a tool finds it. Whatever else a
  contributor or a toolset puts in the folder is named as they choose. (Chosen to match the name
  Pocock's skills expect, so that they need no more than a mapping in `.agents/`.)
- **`IDEAS.md`** is uppercase, like the root markdown: a fixed file a reader is meant to find.
- **Exception**: the historical records keep their uppercase IDs —
  `archive/YYYY-MM-DD-<HISTORICAL-ID>.md` or `/` — because they are not rewritten.

### Hard conventions

- **The location**: a piece of work is a folder directly under `.tracker/`, and its `spec.md` is at
  the root of that folder.
- **The `Status:` line** is the first line of `spec.md` after its title, with one of six values:

  | Status | Meaning |
  |---|---|
  | `open` | Written, not started |
  | `in-progress` | Someone has taken it on. Its work is carried by the branch `<type>/<slug>`, created from the commit that sets this status |
  | `blocked` | Waiting on something or someone — the line says what, and who is expected to act |
  | `paused` | Deliberately set aside: nobody picks it up and nothing is expected of anyone — the line says what would restart it. For work whose spec, or branch, is worth keeping as it is; work never really started goes back to `IDEAS.md` instead |
  | `done` | The work is complete. Set in the pull request itself, so that it reaches `develop` when the pull request merges and never before — no change is needed afterwards |
  | `dropped` | Decided against — the line or the spec says why, so that it is not reopened without a new reason |

  What is under way is found by search, not by an index:
  `grep -l "Status: in-progress" .tracker/*/spec.md`. Only the spec is searched: a file a toolset
  adds beside it may carry a status line of its own.
  The search covers live work. Anything in `archive/` is finished. The historical records do not
  follow the convention — the compacted ones carry no status line, the uncompacted ones the old
  `**Status**: ✅` form in a `PRD.md` — and their outcome is in their text.
- **The archive**: a folder moves as it is to `archive/YYYY-MM-DD-<type>-<slug>/`, the date being
  the day its last pull request merged or, for dropped work, the day it was dropped. Nothing is
  rewritten on the way.
- **`IDEAS.md`** is a free list. An idea taken up is removed from it in the commit that opens its
  spec. A dropped idea stays, with the reason it was dropped, so that the search before a proposal
  finds it.

The state is never part of a file name. A rename on each change of state would break every link to
the file and make its history harder to follow; the archive's date is set once, when it moves.

### Recommended, not required

- **A spec's shape**: the problem; what to build; the decisions taken, with the alternatives turned
  down and why; what is out of scope. Discussion is appended under a `## Comments` heading.
- **When a spec is worth writing**: when there is something to decide before coding, or when the
  work will span several pull requests. Otherwise a branch and a pull request are enough. The
  threshold is the developer's call.

A spec is kept true while the work is under way and becomes a record once its pull request has
merged. From then on it is not edited.

## The mandatory steps

1. **Check what is already known** before proposing a change to how something behaves: search
   `.tracker/`, its archive and `IDEAS.md` included.
2. **Open the work**, if it needs a spec: commit `.tracker/<type>-<slug>/spec.md` straight to
   `develop` with `Status: in-progress` when you start it now, then branch from that commit. A spec
   committed as `open` is taken up the same way later: set it to `in-progress` on `develop`, then
   branch. The idea the work takes up, if any, leaves `IDEAS.md` in the same commit.
3. **Branch** from an up-to-date `develop` as `<type>/<slug>`, or `release/<x.y.z>` for a release.
   Nothing is committed directly to `develop` or `master` except a change confined to `.tracker/`.
   Work spanning several pull requests reuses its slug for each branch, suffixed `-2`, `-3`… after
   the first.
4. **Test first**, then implement.
5. **Run the suite and the lint gate.** When only DCS can show that the change works, say so.
6. **Add a `CHANGELOG.md` entry** for any change to `skynet-iads-source/`.
7. **Commit** in English, following Conventional Commits. Split commits sensibly — a commit that
   mixes unrelated subjects cannot be read or reverted apart — but there is no hard rule.
8. **Open a pull request to `develop`.** Its description says what changed and why, and how it was
   verified — including "not flown" when it was not tested in DCS — and carries `Closes #N` when it
   answers a GitHub issue. Amendments to the spec ride with the pull request, down to
   `Status: done` — set by the last pull request when the work spans several. A decision that
   warrants it — most do not: the code, the spec and the pull request carry them — goes into
   `CONTEXT.md` or `CONTRIBUTING.md` in the same pull request.
9. **Merging is a maintainer's call**, with a merge commit — never squashed, never rebased.
10. **Archive** the work's folder, at the developer's discretion, once its last pull request has
    merged or it has been dropped. It is a change confined to `.tracker/`, so it goes straight to
    `develop`.

## GitHub

- **Issues are for reports from outside.** A report that becomes work gets a folder in `.tracker/`
  whose spec links to it, and the pull request closes it.
- **The pull request template**, `.github/pull_request_template.md`, suggests three sections. They
  are a helper, not a required structure; what is required is in step 8.
  - **What and why** — the `.tracker/` folder when there is one, `Closes #N` when it answers an
    issue.
  - **Decisions** — anything settled along the way, alternatives turned down included, or "none".
  - **Verification** — the suite, the lint gate, and DCS or "not flown".

## Releasing

A release is a procedure in `CONTRIBUTING.md`, so that a maintainer without an agent can cut one.
Every step that writes to `develop` or `master` goes through a pull request.

1. **Prepare**, on a `release/<x.y.z>` branch: bump `SkynetIADS.version` and write the release notes
   under `## [Unreleased]` in `CHANGELOG.md`. Pull request to `develop`.
2. **Promote**: a pull request from `develop` to `master`, merged with a merge commit.
3. **Tag** `v<x.y.z>` on `master` and push it. The release workflow builds, checks and publishes the
   release, taking its notes from `## [Unreleased]` as it stands.
4. **Freeze the changelog**, on a `release/<x.y.z>-freeze` branch: rename `[Unreleased]` to
   `[x.y.z] — YYYY-MM-DD` and open a fresh `[Unreleased]` above it. Pull request to `develop`. This
   comes after the tag because the workflow reads `[Unreleased]` literally.
5. **Tell whoever vendors the script** that a release is out. Consumers are not named.

## Agents and tooling

### `CLAUDE.md`

It keeps its role — each line prevents a mistake — and restates nothing it can point at:

- the prohibitions stay bare: never commit to `develop` or `master` except a change confined to
  `.tracker/`, never open a pull request upstream, never edit the deliverable;
- the git-flow lines and the default workflow give way to one line: follow the mandatory steps in
  `CONTRIBUTING.md`, branching as `<type>/<slug>` with the types listed there. The steps and the
  type list are not copied;
- one line, because `gh pr create` skips the template: the description carries what step 8 of
  `CONTRIBUTING.md` requires;
- planning skills write their specs and plans to `.drafts/`; what is worth keeping becomes a spec in
  `.tracker/`;
- the table's row for lots becomes a row for the tracker, pointing at `CONTRIBUTING.md`, and its
  rule becomes *a row names a file or a skill*;
- one line points at `.agents/` for toolset configuration;
- the words *lot* and *PRD* appear nowhere in it, and neither does any skillset: the line on
  planning skills no longer says "superpowers and the like".

### `.agents/`

Configuration for a toolset that lets it be placed anywhere, reached from the tool's entry file — a
skill that hardcodes its own paths does not reach it, see *Known gaps, accepted*. Each file maps
this repository's choices onto the toolset's vocabulary and never restates a rule. A toolset gets a
file when someone uses it and it needs one.

- **Pocock's skills**: the three files his setup writes. The tracker is local markdown in
  `.tracker/` rather than `.scratch/`: a folder per piece of work, `spec.md` opening on its
  `Status:` line, `## Comments`. His triage roles map onto the `Status:` values as far as they
  can, which is only partly — see *Known gaps, accepted*. Whatever else his skills write into the
  folder is theirs to shape. The domain docs are `CONTEXT.md` at the root, with no ADR folder:
  lasting decisions go into `CONTEXT.md` or `CONTRIBUTING.md`.
- **Superpowers**: nothing; the `CLAUDE.md` line on planning skills is enough.

### `.drafts/`

Git-ignored personal working space. Nothing in it is a record, so nothing in it has rules. (Why
not `.scratch/`: Pocock's skills use that name for a committed tracker, and reusing it for
untracked files would mislead anyone who knows them.)

### The skills

A skill is guidance and follows the rules for writing it in `CONTRIBUTING.md`: it states its own
reasons, cites no piece of work, person or date, points at files, and never restates a rule it can
point at. One exception, for procedures: a skill may show a consumer's configuration as an example
**beside the direct way**, never as the only way.

- **`release`** becomes the interactive guide through *Releasing*: it confirms each step with the
  user, runs the in-DCS smoke checks, and hands over the tag commands. The rules come from
  `CONTRIBUTING.md`. The direct commit on `develop`, the undescribed "branching model", the
  consuming repository's "vendoring lot" and the repeated versioning and changelog reasoning go.
- **`skynet-runtime-debug`** loses two absolutes the sources contradict — a SAM site acting as EW is
  not a permanent watcher, and a SAM site out of ammunition is not dark for good — each checked
  against `skynet-iads-source/` before it is rewritten. The VEAF configuration stays as an example
  beside the direct `debugOutput` way; the helper's log lines and the vendored copy lagging behind
  are described without naming who ships them. *Battery* becomes *SAM site* throughout: the term
  the log lines, the class and `CONTEXT.md` use.

### `CONTRIBUTING.md`

Beyond the steps, the tracker and *Releasing* above:

- *What you need* gains `gh`, logged in, for opening pull requests from the command line, and the
  two lint tools, which on Windows need no install — see *The lint tools*.
- *Writing guidance* lists the guidance files without `BACKLOG-CONVENTIONS.md`, adds the skills, and
  says the history behind a rule is in `.tracker/` and the pull requests. Its rule against citing
  becomes: never a piece of work, an issue, a commit, a person or a date. It gains the rule that no
  skillset is named outside `.agents/`.
- *Git flow* takes the six branch types and `release/`, the promotion pull request, and the
  `.tracker/` exception.
- *Layout* and *File naming* lose `.backlog/` and gain `.tracker/`, `.drafts/`, `.agents/` and
  `.github/pull_request_template.md`.

## The lint tools

### Problem

The lint gate asks every contributor for a system-wide install of `luacheck` and `stylua`, where a
TypeScript or Python project would keep its linters local to the checkout, at a pinned version.
*What you need* names the two tools and says nothing of how to install them. On Windows the install
is also fragile: a `luacheck` rock built for a newer Lua than the interpreter that must run it dies
before checking anything, and `build-tools/lint.sh` spends most of its length finding the rock, its
module tree and a Lua 5.1 to run it with. When no rock is found at all it reports luacheck as
*broken*, which points at a bad install rather than a missing one. Nothing pins a version locally,
so a contributor can pass the gate with a `stylua` that formats differently from CI's.

### What to build

**`lint.sh` fetches its own tools, and CI runs `lint.sh`.** On first run the script downloads a
pinned release binary of each tool for the platform it runs on into `.tools/`, git-ignored, checks
it against a SHA-256 written in the script, and runs it from there; later runs reuse it. Nothing is
installed system-wide, and the only prerequisites are `bash`, `curl` and `unzip`, which Git for
Windows and the GitHub Linux runners already ship.

| Platform | luacheck v1.2.0 (`lunarmodules/luacheck`) | stylua v2.4.0 (`JohnnyMorganz/StyLua`) |
|---|---|---|
| Windows, under Git Bash | `luacheck.exe` | `stylua-windows-x86_64.zip`, unzipped |
| Linux x86-64 | `luacheck`, made executable | `stylua-linux-x86_64.zip`, unzipped |

Both luacheck builds are standalone executables with their interpreter and dependencies built in. The
platform is read from `uname -s`; on any other platform, macOS included, `lint.sh` runs the tools
from `PATH`, as it does today.

The versions are pinned once, in `lint.sh`, with their hashes; bumping a tool is a change to that
file alone. v1.2.0 is the latest luacheck release and 2.4.0 the stylua CI already pins, so the switch
changes no result.

What changes with it:

- `lint.sh`: the per-platform table, the download, the hash check and the cache. The rock search —
  `find_lua51`, `find_luacheck_rock`, `find_module_tree` and the `LUA_PATH` assembly — goes, and with
  it `LUACHECK_BIN`, `LUACHECK_TREE` and `LUA51`. The CRLF copy for stylua stays: under
  `core.autocrlf=true` stylua still flags every file for its line endings.
- `.github/workflows/lint.yml`: each job runs `bash build-tools/lint.sh <gate>` after the checkout,
  in place of its `apt`, `luarocks` and `curl` steps. Its luacheck job currently installs whatever
  version luarocks resolves; the pin in `lint.sh` ends that.
- `.gitignore` gains `.tools/`.
- `CONTRIBUTING.md`: *What you need* says the lint tools need no install; *Static analysis and
  formatting* loses the rock workaround, keeps the CRLF one, and says CI runs the same script.

### Decisions

- **Release binaries, fetched and pinned by the script**, the way a Gradle or Maven wrapper fetches
  its build tool. Turned down:
  - *a Python dev requirements file* for stylua: covers only one of the two tools, since luacheck is
    not a Python package, and adds an install step and a virtual environment;
  - *vendoring luacheck's sources*, as `luaunit.lua` is: it depends on `argparse` and on
    `luafilesystem`, a C module;
  - *a project-local luarocks tree*: still built by the luarocks that causes the version mismatch;
  - *editor extensions*: they help while editing but cannot be the gate, which needs a command line.
- **CI runs the script, on Linux.** Local and CI then run the same versions through the same code, and
  a version lives in one file. Moving the lint jobs to `windows-latest` would have needed only the
  Windows binaries, and was turned down to keep CI on the runners every other workflow uses; the
  Linux rows cost two lines of the table.
- **The embedded interpreter does not matter.** `luacheck.exe` runs on Lua 5.4; what it checks against
  is `std = "lua51"` in `.luacheckrc`, not the interpreter running it.
- **Each platform downloads only its own build.** Git Bash resolves an extensionless `luacheck`
  before `luacheck.exe` in the same folder, and the Linux build carries that name.
- **If the Linux luacheck binary does not run on `ubuntu-latest`**, the luacheck job goes back to
  `luarocks install luacheck 1.2.0`, pinned, and the table keeps its Windows row alone for luacheck.
  The first CI run of the pull request settles it.

### Out of scope

- **macOS.** luacheck publishes no macOS binary; there `lint.sh` runs the tools from `PATH`.

## Known gaps, accepted

Neither of these is an oversight.

### The mapping for Pocock's skills is partial

- **Some of his skills hardcode their paths.** `code-review` reads `docs/agents/issue-tracker.md`
  and looks for specs in `docs/`, `specs/` and `.scratch/`, so it finds neither the mapping in
  `.agents/` nor a spec in `.tracker/` on its own: the spec's path has to be handed to it. The
  skills that depend on the configuration — `triage`, `to-spec`, `to-tickets` — take it from wherever
  setup points them, so `.agents/` serves them. Bringing back `docs/`, or naming the tracker
  `.scratch/`, would undo two decisions of this spec for the sake of one skill.
- **The pointer to that configuration is generic.** His setup writes a section into `CLAUDE.md`
  that names his skills; here a single line points at `.agents/` instead, since no skillset is named
  outside it. That `triage`, `to-spec` and `to-tickets` find their configuration through that line
  is expected, and is to be confirmed the first time they are used here.
- **His triage roles map onto the `Status:` values only partly, in both directions.**
  `needs-info` → `blocked`, `wontfix` → `dropped`, and both `ready-for-agent` and
  `ready-for-human` → `open`, which loses the distinction between them; when it matters, the spec
  says which. `needs-triage` has no target, because nothing enters the tracker untriaged: what is
  not yet decided lives in `IDEAS.md` or in a GitHub issue. `in-progress`, `paused` and `done` have
  no role, because triage stops at *ready*.

### The work introducing these rules does not follow them

CHORE-REPOSITORY-CONVENTIONS predates the rules it writes. Its branch is
`feature/repository-conventions`, not `chore/repository-conventions`, and is not renamed; its spec
was never committed to `develop` before the branch was cut; its records are a PRD and tickets, and
its commits follow the old one-ticket rule. It takes the new form only where the move below gives it
one — its folder name, this `spec.md` and its `Status:` line. The `✅ done` in `PRD.md` is the
status of the first part, under the old conventions.

## Getting there

All of it on `feature/repository-conventions`, in one pull request. Nothing is published to GitHub.

This work moves first, so that it is tracked under the rules it introduces: its folder becomes
`.tracker/chore-repository-conventions/`, `PRD.md` and `tickets/` stay as they are, and this spec
joins them as `spec.md`.

1. **The rules**: `CONTRIBUTING.md`, `CLAUDE.md`, the pull request template, `.agents/`,
   `.gitignore` for `.drafts/`, the two skills, and the lint tools.
2. **The move**, with `git mv` so that history follows:
   - the eleven compacted records go to `.tracker/archive/YYYY-MM-DD-<HISTORICAL-ID>.md`, the date
     being the one they closed on. They keep their uppercase IDs and stay single files. The in-sim
     test report moves beside its record under the same date;
   - FEAT-BILINGUAL-DOCUMENTATION, CHORE-DOCS-MANUAL-REPUBLISH and CHORE-DOCS-RECENT-BEHAVIOUR,
     merged on 2026-09-21, go to `.tracker/archive/2026-09-21-<HISTORICAL-ID>/` as they are;
   - `IDEAS.md` goes to `.tracker/IDEAS.md` and takes the new form: entries already taken up, by
     this work or earlier, are removed; dropped ones stay with their reason; the ideas below are
     added;
   - `.tracker/chore-repository-conventions/`, already moved, is archived like any other once its
     pull request has merged.
3. **The removal**: `BACKLOG-CONVENTIONS.md`, `.backlog/INDEX.md` and the emptied `.backlog/`.

## Ideas to record

Added to `.tracker/IDEAS.md` as part of step 2.

- **ADRs**: whether Architecture Decision Records would serve this repository better than stating
  lasting decisions in `CONTEXT.md` and `CONTRIBUTING.md`.
- **The tracker on GitHub issues**: the in-repository tracker is the starting point; moving to
  GitHub issues, with the development records migrated, remains an option once it has been used.
- **An `AGENTS.md`** for agents other than Claude Code.
- **The two test READMEs**, which still justify rules by lots, people and dates.
- **The release workflow reads `[Unreleased]` literally**, which forces the changelog freeze into a
  pull request of its own after the tag.
- **Four imprecisions in the guidance**: the CI triggers, the second stylua exclusion, the two
  workflow files left unnamed, and the title of `CONTEXT.md`.
- **_Battery_ beside _SAM site_**: eleven source comments and the published documentation still say
  *battery* (*batterie* in French) where the rest says *SAM site*.
