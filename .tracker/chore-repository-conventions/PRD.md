# CHORE-REPOSITORY-CONVENTIONS

**Status**: ✅ done — `feature/repository-conventions`, pull request not yet opened

Put every rule a contributor or an agent follows in one place, and give the files names the
repository's own conventions predict.

## Why

Four files told someone how to work here: `CLAUDE.md`, `contributing.md`,
`docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`. None said which was
authoritative. `CLAUDE.md` (231 lines) and `contributing.md` (153) shared seven subjects, and the
copies had already drifted into defects:

| | Defect |
|---|---|
| 1 | **The two files disagreed on git flow.** `CLAUDE.md` let a change confined to `.backlog/` go straight to `develop`; `contributing.md` forbade any direct commit. An agent and a human following their own file behaved differently on the same change. |
| 2 | **`contributing.md` never mentioned the lint gate**, which `lint.yml` runs on every pull request. The whole section was in `CLAUDE.md`, where a contributor has no reason to look. |
| 3 | **A guidance file justified its rules by pointing at the backlog** — tickets of an archived lot whose directory was gone, and rules argued from who decided them and which lot proved them. |
| 4 | **A sentence in `CLAUDE.md` had no referent**: "`demo-missions/` archives are attached to it" meant *to a release*. |

## CLAUDE.md keeps what prevents a mistake

`CLAUDE.md` is loaded into every agent session; `CONTRIBUTING.md` is not. Every line of `CLAUDE.md`
is paid for in every session, and a long one gets its important rules ignored. The test is the one
from Anthropic's Claude Code best practices: **would removing this line cause Claude to make a
mistake?** If not, it goes.

That keeps inline the commands that cannot be guessed, environment quirks, and the mistakes that are
costly or silent: editing the compiled deliverable, a pull request against an upstream archive, a
commit to `develop`, abandoning surgical mode. It moves out the long explanations: the bilingual
documentation rules, the coverage floor, the mission tooling, the history of the archives. The file
also stays readable by a person; nothing in it assumes a reader who is not one.

What leaves is reached through a table indexed by **task**, not by section: *about to change a source
file → CONTRIBUTING.md*. A single "read CONTRIBUTING.md first" is easy to skim and gives no reason
to comply. A row names a file, never a heading, and a new row means a new kind of task, never a
subsection of one already listed; otherwise the table grows back into the reference file it
replaced.

`CONTRIBUTING.md` becomes the guide, at the name GitHub surfaces in the issue and pull request
composer. It absorbs what `CLAUDE.md` held, including the lint gate, and is ordered the way the work
is done: prerequisites, layout, build, test, lint, documentation, git, changelog.

## What may be stated twice

**Judgement is stated once.** A rule's reasons and edge cases live in one file; every other file
points at it. Defects 1 and 2 were both drifted judgement: a reader of either copy got a different
answer with no way to know.

**Two things may be repeated**, because a drifting copy fails loudly rather than silently:

- **a command.** If the copies drift, one of them fails the first time it is run. The Windows
  invocation of the test runner shows the cost of the opposite policy: documented in full in
  `test/lua/README.md` only, it did not exist for an agent working from `CLAUDE.md`, which got
  `command not found` and concluded that no Lua interpreter was installed.
- **a rule, stated bare in `CLAUDE.md`**, with at most a clause of why. What prevents the mistake is
  the prohibition; the reasoning around it is what drifts, and it lives in `CONTRIBUTING.md` only.

The drift this accepts is a rule changed in `CONTRIBUTING.md` and not in `CLAUDE.md`. `CLAUDE.md`
says a rule changes in `CONTRIBUTING.md` first, then in `CLAUDE.md`; there is no gate. Defining the
commands once in a task runner would remove the command copies too; it changes the build and is in
`.backlog/IDEAS.md`.

## How guidance is written

These rules are stated in `CONTRIBUTING.md`, and `CLAUDE.md` has a row pointing at them for anyone
about to edit a guidance file.

- **Guidance files are the root instruction files**: `CLAUDE.md`, `CONTRIBUTING.md`,
  `BACKLOG-CONVENTIONS.md`, `CONTEXT.md`, `README.md`. The skills under `.claude/skills/` and the two
  test READMEs are outside that boundary, and whether a skill belongs inside it is a question this lot
  does not answer: a skill also carries a procedure, and the `release` skill's procedure contradicts
  the git flow in ways no deletion of citations repairs. That is a lot of its own, and
  `.backlog/IDEAS.md` holds what the skills and the two READMEs still carry. The `release` skill was
  edited here for one thing only — it opened on a pointer to an archived lot whose directory is gone,
  which is this lot's defect 3, in a file the table used to send an agent to.
- **A rule states its own reason.** It never cites a lot, a ticket, a commit, a person or a date.
  Those records answer *why* for whoever asks; a guide whose rules only make sense with the tracker
  open cannot be followed from one file. The reason stays, in general form: *two subjects in one
  commit cannot be read, reverted or bisected apart*. The rule applies to guidance only; files under
  `.backlog/` are records, and guidance may point at `BACKLOG-CONVENTIONS.md` for the tracker's
  rules.
- **No consumer is named.** Skynet has no consumer of its own to single out. The reason survives in
  general form: what this project ships is vendored by other repositories, and a change reaches no
  mission until one of them takes a new copy.
- **Pointers name files, never headings or anchors.** A heading is reworded as a matter of course
  and the link dies silently; a file is rarely renamed, and never quietly. An agent following a
  pointer reads the whole file anyway, and a person has GitHub's outline. `README.md`'s `#en` and
  `#fr` anchors stay: they are its language switcher, not a cross-reference.

## CONTEXT.md keeps intent

`CONTEXT.md` holds the premise — what Skynet is for and where its responsibility ends — and a few
concepts, each something in the design that looks like a bug and is not. That is what someone about
to change the code would otherwise fix.

It holds no definitions and no code names. One-line definitions invite absolutes — "only",
"permanently" — and the absolute is what goes wrong; `documentation/setting-up` defines the terms for
the reader who needs them. A code name is read as true until somebody searches for it, and someone
about to change the code finds the class in seconds without it. A concept says why something is the
way it is; a transcription of what a function checks belongs to the function.

## The tracker

**Its rules sit at the root, its index does not.** A change confined to `.backlog/` may go straight
to `develop` without review; that exception covers status changes and index lines. Rules inside that
directory would become editable without review too. As `BACKLOG-CONVENTIONS.md` at the root they
are reviewed like any other guidance. The index changes every week and the rules almost never, which
is the same split.

`BACKLOG.md` would have read as *the list of work*, which is the index's job. Inside `.backlog/`,
`INDEX.md` says what it is and sits beside `IDEAS.md`. The cost: GitHub renders a directory's
`README.md` inline and not an `INDEX.md`, so browsing `.backlog/` shows a bare listing; the root file
links straight to it.

**A lot is required for more than one deliverable or a decision worth recording**, not for every
change. A lot holds reasoning; a one-line fix has none to hold, and a branch and a pull request are
enough however many commits it takes.

**✅ done means committed, and it is the last status a lot carries.** A lot at ✅ has all its work on
its branch, which is when its pull request is worth opening. A *merged* status was tried and dropped:
it split one state into two to answer a question — which of these ✅ lots is already in `develop`? —
that archiving answers better. A lot leaves the index a few days after its pull request lands, so a
lot still listed is either unmerged or newly merged, and the glyph has nothing left to add.

## Git flow and the changelog

- **A commit must not touch more than one ticket.** The rule is against mixing, not about counting:
  opening a lot is its own commit, a ticket may take several, and a review response is appended
  rather than squashed back.
- **Pull requests are merged with a merge commit**, never squashed or rebased: a squash destroys the
  per-ticket history the commit rule keeps. The repository setting can change, so the rule is
  written down.
- **The changelog records source changes only.** Its reader is whoever decides whether a new build is
  worth taking, and repository conventions are noise between the entries that reader needs.
- **`README.md` is authoritative for joint maintenance.** It is where a newcomer lands, and it is
  bilingual. `CONTRIBUTING.md` keeps only what a contributor needs: the work happens here, and the
  fork trap — `gh pr create` and the compare banner default to the read-only parent.

## Agents

- **The shipped `settings.json` pre-approves no shell command.** It applied `Bash(*)` and
  `PowerShell(*)` to every contributor who opened the repository, and an instruction file cannot
  grant or withhold anything: permissions are enforced by settings. The two read-only `WebFetch`
  domains stay.
- **Merging is a maintainer's call**, and an agent merges only when asked. Read as a list of steps,
  a workflow ending in "merge" is an instruction to merge.
- **Planning and analysis skills follow the repository's conventions over their own.** Superpowers
  writes specs and plans under `docs/superpowers/` by default, which would bring back `docs/` and
  start a tracker beside `.backlog/`. A spec is a lot's PRD; a plan becomes tickets or stays in the
  session.

## What this makes more fragile

**Delegated knowledge does not survive compaction.** The project `CLAUDE.md` is re-injected after a
compaction; a `CONTRIBUTING.md` read as a tool result is not. A long session can lose what was
delegated with no sign that anything is missing. Accepted, because keeping 231 lines in every
context degrades every session rather than some. It makes the pointer table load-bearing: it is the
route back, and it is not to be dropped when the file feels long.

## Refused

- **Two self-contained files, one per audience, kept in sync by checklist.** That is what the
  repository had, and defects 1 and 2 are drift between the copies.
- **Shared subjects extracted into a third directory**, with both files pointing at it. It adds files
  without removing the drift, and rebuilds `docs/`.
- **Renaming `listToMerge.txt`** to match its kebab-cased siblings. The build, `.luacheckrc`, `.luacov`
  and two test files reference it; the change buys consistency only. The naming conventions record it
  as an inherited exception, so it reads as a decision rather than an oversight.
- **`.claude/rules/` with `paths:` frontmatter.** More reliable than a pointer table, but specific to
  one agent; Copilot's equivalent has its own format. Revisit with the `AGENTS.md` lot.
- **A `.backlog/CLAUDE.md`, or a rule scoped to that path.** Both load when a file in the directory is
  read. The backlog rules are needed when a lot is *created*, possibly in a directory that does not
  exist yet. The pointer stays in `CLAUDE.md`, which is always loaded.

## Deferred

All in `.backlog/IDEAS.md`:

- **One instruction file for Claude and Copilot alike (`AGENTS.md`).** This lot comes first: it makes
  `CONTRIBUTING.md` the single source an `AGENTS.md` would point at.
- **The skills and the two test READMEs.** Whether they are guidance, what in them contradicts the
  root files, and the `release` skill's procedure against the git flow.
- **The commands defined once, in a task runner.**

## Consequences a reader will notice

- **`docs/` is gone.** The idea tracker is `.backlog/IDEAS.md`, the backlog rules are
  `BACKLOG-CONVENTIONS.md`. `docs/` and `documentation/` were one letter apart in name and a whole
  concept apart in content.
- **`CONTRIBUTING.md` is the file to read**, and longer for it.
- **`CLAUDE.md` is behaviour, commands and gotchas.** No line count was a target; the test above
  decides. Cutting a release is not among them: the tag workflow does the release, the skill that
  drives the rest is the user's to invoke, and a row an agent cannot act on fails the test.
- **The naming conventions are written down**, in `CONTRIBUTING.md`. Only `<LOT-ID>` had been
  specified; the rest was practice, so outliers could not be told from exceptions.

## Scope

`CLAUDE.md`, `CONTRIBUTING.md`, `CONTEXT.md`, `README.md`, `CHANGELOG.md`, `BACKLOG-CONVENTIONS.md`,
`.backlog/`, `docs/agents/`, `.claude/settings.json`, `.claude/skills/release/SKILL.md` and
`test/lua/README.md`. One test file lost a comment citing a tracker entry that no longer exists.

No change to `skynet-iads-source/`, the build, the tests or `documentation/`. History is left as
written: `CHANGELOG.md` and the archived records name paths that later moved.

## Tickets

| # | Ticket | Status |
|---|--------|--------|
| 01 | [The idea tracker moves into the backlog](tickets/01-ideas-into-backlog.md) | ✅ |
| 02 | [contributing.md takes the name the repository predicts](tickets/02-rename-contributing.md) | ✅ |
| 03 | [The tracker documents itself; docs/ disappears](tickets/03-backlog-conventions.md) | ✅ |
| 04 | [CONTRIBUTING.md becomes the single source](tickets/04-single-source.md) | ✅ |
| 05 | [CLAUDE.md keeps what prevents damage](tickets/05-claude-md-shrinks.md) | ✅ |
| 06 | [What CONTEXT.md is for, and what survives](tickets/06-context-corrections.md) | ✅ |
| 07 | [Streamline CONTRIBUTING.md](tickets/07-streamline-contributing.md) | ✅ |
| 08 | [The commit rule, and four corrections to the instruction files](tickets/08-commit-rule-and-instruction-fixes.md) | ✅ |
| 09 | [The shipped settings stop pre-approving every shell command](tickets/09-settings-blanket-grants.md) | ✅ |
| 10 | [*done* means committed, and *merged* becomes a status](tickets/10-done-means-committed.md) | ✅ |
| 11 | [Review response](tickets/11-review-response.md) | ✅ |
| 12 | [Second review response](tickets/12-second-review-response.md) | ✅ |
| 13 | [Pointers name files, not headings](tickets/13-pointers-name-files.md) | ✅ |
| 14 | [Third review response](tickets/14-third-review-response.md) | ✅ |
| 15 | [Fourth review response](tickets/15-fourth-review-response.md) | ✅ |
