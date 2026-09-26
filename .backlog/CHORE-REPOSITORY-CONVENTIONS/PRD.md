# CHORE-REPOSITORY-CONVENTIONS

**Status**: ✅ done — `feature/repository-conventions`, pull request not yet opened

Put every rule a contributor or an agent follows in exactly one place, and give the files names the
repository's own conventions predict.

## Why

Four files tell someone how to work here: `CLAUDE.md`, `contributing.md`,
`docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`. Nothing says which is
authoritative, and two of them restate each other at length.

**Measured, 2026-09-22.** `CLAUDE.md` is 231 lines, `contributing.md` 153. Seven subjects appear in
both: joint maintenance, English-everywhere, the generated deliverable and the build command, git
flow, the three bilingual-documentation rules, test-first and the stub warning, and the changelog
rule. The bilingual rules are near-verbatim — `CLAUDE.md` carries them as bullets, `contributing.md`
as a table.

The principle being broken is one this repository already states, in `CLAUDE.md` itself: *prose lives
in exactly one place*. It was written about `documentation/` and `README.md`, and never applied to
the instruction files.

Duplication is not a theoretical risk here; it has already produced defects. Four, found while
reading:

| | Defect |
|---|---|
| 1 | **The two files disagree on git flow.** `CLAUDE.md` grants the `.backlog/`-only exception — a tracker-only change goes straight to `develop`. `contributing.md` says never commit directly to `develop`, with no exception. An agent and a human following their respective files behave differently on the same change. |
| 2 | **`contributing.md` never mentions the lint gate.** No luacheck, no stylua, no `build-tools/lint.sh`, no Windows workarounds — yet `lint.yml` runs on every pull request. A contributor's first pull request fails on a gate their guide does not know exists. The whole section is in `CLAUDE.md`, where a contributor has no reason to look. |
| 3 | **A guidance file justifies its rules by pointing at the backlog.** Two dangling pointers — "see ticket 06 / ticket 03 in `CHORE-PROFESSIONALIZE-THE-REPO`", a lot archived on 2026-09-20 whose directory is gone — and three passages that argue a rule from lot history: *"David's call, 2026-09-19, after `CHORE-PROFESSIONALIZE-THE-REPO` reached nine pull requests…"*, *"`FEAT-LAST-LINE-OF-DEFENSE` shipped … as a single commit (`0ebbc01`) … Flogas caught it"*. |
| 4 | **`CLAUDE.md` line 130 is garbled.** "The directory is also what a release reads: `demo-missions/` archives are attached to it, `unit-tests/` ones never are" — "it" has no referent. It means *attached to a release*. |

One claim was checked and is correct: `contributing.md`'s CI description matches `lua-tests.yml`
exactly — pull requests, plus pushes to `develop` and `master`. An older note under `.superpowers/`
called it overstated; it is not, today.

## The governing decision

`CLAUDE.md` is loaded into every agent context automatically. `CONTRIBUTING.md` is not. Every line of
`CLAUDE.md` is therefore paid for in every session, and a bloated one is not merely wasteful — it
makes the rules that matter get ignored. So the test is Anthropic's own, from the Claude Code best
practices:

> **For each line, ask: would removing this cause Claude to make a mistake?** If not, cut it.

Their include/exclude table resolves most cases directly. **Include**: bash commands Claude cannot
guess, testing instructions and preferred test runners, repository etiquette, developer environment
quirks, common gotchas, architectural decisions. **Exclude**: anything derivable from the code,
detailed reference documentation — link to it instead — long explanations or tutorials, and
information that changes frequently.

So editing the compiled deliverable, opening a pull request against an upstream archive, committing
to `develop`, abandoning surgical mode: all mistakes, all inline. The three commands stay too, under
*bash commands Claude cannot guess* — and so does the Windows `lint.sh` quirk, under *developer
environment quirks*. What leaves is the long-explanation half: the bilingual-documentation rules, the
coverage-floor mechanics, the `miz-suite.py` essay, the mission-archive history.

The same guidance adds a second requirement the earlier draft of this PRD missed: *keep it short and
**human-readable***. `CLAUDE.md` is not an agent-only artifact, and nothing in it may assume a reader
who is not a person.

The delegation is made verifiable rather than hoped for: for every section removed from `CLAUDE.md`,
a task-indexed row says where it went — *about to change a source file → CONTRIBUTING.md*. A single "read CONTRIBUTING.md first" at the top is the version that fails; it is easy
to skim and gives no reason to comply.

## Duplicate identifiers if you must; never duplicate judgement

Three commands — the build, the suite, the lint gate — appear in both `CLAUDE.md` and
`CONTRIBUTING.md`. That is deliberate, and it is not a retreat from the single-source rule, because
not all duplication carries the same risk.

Both defects this lot exists to fix are duplicated **judgement**: a git-flow rule that contradicts
itself, and the bilingual rules stated twice in two shapes. A reader of either copy gets a *different
answer* and has no way to know. Apply the same test to `lua5.1 test/lua/run.lua` in two files: if the
copies ever drift, nobody gets a wrong answer — one of them fails loudly the first time it is run,
and a missing script is the least silent failure there is.

A command is an identifier, like `skynet-iads-source/`, which appears in a dozen files without anyone
calling it duplication. What must never be stated twice is anything encoding a decision. So the three
commands are repeated; their explanations — why the suites are split, what the stub warning means,
how the coverage floor moves — live only in `CONTRIBUTING.md`.

The cost of the opposite policy was measured here, 2026-09-24. The Windows invocation of the test
runner is documented, correctly and in full, in `test/lua/README.md` — and in that one place only.
An agent working from `CLAUDE.md` ran `lua5.1 test/lua/run.lua`, got `command not found`, and
reported that the machine had no Lua interpreter. A command that lives in exactly one file, which
nothing points at from where the work starts, is indistinguishable from a command nobody wrote down.

The zero-duplication version exists: commands defined once in a task runner, with both files saying
`make test`. It is recorded in `.backlog/IDEAS.md` rather than built here — it changes the build,
which this lot's scope excludes, and it needs `make` or `just` on a Windows-first project.

### A second allowed duplication: rules without their reasons

Review found the one place the policy above had not been applied, and the copies had already drifted
inside this lot. Git flow was written out in full in both files: on splitting a lot one said the
split is *announced in the plan and approved before the first branch is cut*, the other *agree the
split before starting*, and where the `.backlog/` exception stops was in one only.

`CLAUDE.md` now carries the git rules **bare** — no reasons, no edge cases — and says outright that
`CONTRIBUTING.md` is where they are stated and the only place they may be changed. That is a second
kind of duplication this lot allows, and it needs naming rather than leaving as an exception nobody
wrote down.

**Why it is allowed**: what prevents the mistake is the prohibition, and a prohibition is close to an
identifier — short, and wrong loudly rather than quietly. What was drifting was the *reasoning*
around it, which is judgement and now exists once.

**The drift it accepts**: a rule could still be changed in `CONTRIBUTING.md` and not in `CLAUDE.md`.
The mitigation is the sentence naming one file as the only place a rule may change; there is no gate.
If a third copy of anything appears, this exception is the first thing to re-examine.

## A guidance file never argues from the backlog

**A rule states itself.** No guidance file explains or justifies a convention by pointing at a PRD, a
ticket, a lot or a commit — Florent's call, 2026-09-24. Those records are history: they are there to
be consulted when someone asks *why*, not to be read before someone can follow a rule. A guide whose
rules only make sense with the tracker open is a guide nobody can follow from one file.

**Keep the reason, drop the citation.** This is not a licence to strip rationale. *"Two subjects in
one commit cannot be read, reverted or bisected apart"* is the reason, it is general, and it stays.
*"`FEAT-LAST-LINE-OF-DEFENSE` shipped the proximity wake-up and the coverage rebuild as a single
commit (`0ebbc01`) … Flogas caught it"* is the citation, and it goes — into the archived record, which
already holds it.

This applies in one direction only. A file **under** `.backlog/` that serves backlog management —
`INDEX.md`, `IDEAS.md` — is self-contained and unaffected, and guidance files may point at
`BACKLOG-CONVENTIONS.md` for the tracker's own rules. What is forbidden is a guidance file leaning on
a *lot* to make its case.

## The tracker's rules sit at the root, its index does not

`BACKLOG-CONVENTIONS.md` is a root file and `.backlog/INDEX.md` stays in the directory. That is not
symmetry for its own sake — it closes a hole this lot would otherwise open.

**A rule that guidance files depend on must be reviewed.** The git-flow exception sends any change
confined to `.backlog/` straight to `develop` with no pull request; it was written for status changes
and index lines. Put the tracker's rules inside that directory and they become editable with no
review at all, by an exception never intended to cover them. At the root they are reviewed like
everything else, and the exception keeps exactly the scope it was granted.

The split matches how the two files behave anyway: the index changes every week, the rules almost
never.

**The name.** `BACKLOG.md` would have been shorter and would have read as *the list of work*, which
is precisely what the file is not. The index keeps that job. Inside `.backlog/`, `INDEX.md` says what
it is and is symmetric with `IDEAS.md`; it was `README.md`, but once the root file is the door,
"read me first" is false — the thing to read first is no longer there. One cost, accepted: GitHub
renders a directory's `README.md` inline and will not render `INDEX.md`, so browsing `.backlog/`
shows a bare listing. The root file links straight to it.

## What this lot makes more fragile

**Delegated knowledge does not survive compaction.** Project-root `CLAUDE.md` is re-read from disk
and re-injected after a compaction; a `CONTRIBUTING.md` that was read as a tool result is not. So a
long session that compacts mid-task silently loses everything this lot delegated, with no signal that
anything is missing.

That is a real cost of the change and it is accepted, because the alternative — keeping 231 lines in
every context — degrades every session rather than some. But it makes the pointer table **load
bearing**: it survives compaction, and it is the only route back to what was lost. It is not a
courtesy to be dropped later when the file feels long.

For the same reason the table indexes **tasks, not sections**. A new row means a genuinely new kind
of work, never a new subsection of an existing one — otherwise `CLAUDE.md` grows back into the
reference file this lot is deleting, one reasonable-looking row at a time.

## Decisions taken during review

Six, all Florent's, all made after the tickets were written. They are here because the archive
record is compacted from this file.

**The changelog is scoped to source changes only.** `CLAUDE.md`'s workflow had said to update it on
every change while `CONTRIBUTING.md` required an entry only for `skynet-iads-source/` — the same
shape as defect 1 above. The changelog's reader is the repository that vendors the artifact, deciding
whether a build is worth taking, and repository conventions are noise between the entries that reader
needs. The rule is stated in `CONTRIBUTING.md` alone; the workflow says to add an entry if the
sources changed and no longer restates where it goes. This lot's own four entries went with the
decision.

**`CLAUDE.md` states the git rules bare, `CONTRIBUTING.md` explains them.** See *A second allowed
duplication* above.

**`README.md` is authoritative for joint maintenance.** It is user-facing, bilingual, and where a
newcomer lands. `CONTRIBUTING.md` links to it and keeps only what a contributor needs and a user does
not: that the work happens here, and the fork trap — `gh pr create` and the compare banner default to
the parent, so a pull request opened without checking the base lands on a read-only archive and looks
like it worked.

**A lot is not required for every change.** The workflow had said to create or pick one
unconditionally, which read literally means a PRD for a one-line fix. A lot holds reasoning, so it is
required when the work has more than one deliverable, or when it makes a decision worth recording;
otherwise a branch, a commit and a pull request are enough. The rule is in `BACKLOG-CONVENTIONS.md`
and the workflow points at it.

**Pointers name files, never headings, and never anchors.** Every rule stated once means every other
file points at it, and each kind of pointer this lot tried needed a correction: a `§` name dead a day
after it was written, a generated anchor, then an explicit `<a id>` added to keep a link alive. The
heading bought almost nothing — an agent following a pointer reads the whole file, a person has
GitHub's outline — and what makes the table work is the task on its left. A file is rarely renamed,
and never quietly. The rule is stated under `CLAUDE.md`'s table, where the next row gets written.

**`CONTEXT.md` carries no code names.** This reverses the second review, which had added an *In code*
column on the grounds that a stale identifier fails on the first search. It fails only when someone
searches; until then it is read as true, and it is one more reference to keep in step with the code
by hand, for a class anyone about to change the code finds in seconds.

## What was refused, and why

**Splitting by audience, each file self-contained.** The duplication kept deliberately, with a sync
checklist. Refused because it is what the repository has now: defects 1 and 2 are both drift between
the two copies, and neither was caught by anyone reading either file.

**Extracting the shared subjects into a third directory.** Two prefaces pointing at shared topic
files. Refused because it adds files without removing the drift risk, and because it would have
rebuilt `docs/` — see *Consequences*.

**Renaming `listToMerge.txt`** to match its ten kebab-cased siblings in `build-tools/`. It is
referenced by `build-compiled-script.ps1`, `.luacheckrc`, `.luacov`, `test/lua/skynet-loader.lua` and
`test/lua/test_harness_smoke.lua`. Refused: a change to the build and the test harness, needing a
full build and suite run to verify, bought nothing but consistency. It is recorded in the written
conventions as an inherited exception — which is the point. A documented outlier reads as a decision;
an undocumented one reads as an oversight, and that ambiguity is what made the `contributing.md`
rename feel arbitrary in the first place.

**Building `.claude/rules/` with `paths:` frontmatter.** Path-scoped rules fire automatically when a
matching file is read, which is more reliable than a pointer table. Refused *for this lot only*: they
are Claude-specific machinery, and Copilot's equivalent is `.github/instructions/*.instructions.md`
with its own glob frontmatter. Building one vendor's version immediately before a lot about vendor
neutrality means undoing it or duplicating it. Revisit once the `AGENTS.md` lot is decided.

Two mechanisms were ruled out on verified behaviour rather than taste. A `.backlog/CLAUDE.md` looks
ideal and would silently fail on the case that matters most: subdirectory instruction files load
*when Claude reads a file in that directory*, and the moment the backlog conventions are needed is
when a lot is being **created** — possibly in a directory that does not exist yet, with no file to
read. The same objection sinks a path-scoped rule. Hence the pointer stays in `CLAUDE.md`, which is
loaded unconditionally.

## Deferred, not dropped

**One agent instruction file for Claude and Copilot alike** — David's intent, raised 2026-09-22.
Copilot already reads this repository's `CLAUDE.md`; an `AGENTS.md` would make that deliberate rather
than accidental. Deferred to its own lot and recorded in `.backlog/IDEAS.md` with the verified
mechanism and the trap that makes the obvious approach fail silently. **The order matters**: this lot
establishes `CONTRIBUTING.md` as the single source, which is what an `AGENTS.md` would point at.
Taken the other way round there is nothing to point to.

**"One commit per ticket" stated a prohibition and none of its exceptions.** Ticket 04 carried the
wording across verbatim and left the `.backlog/IDEAS.md` entry open, on the grounds that changing how
the project works does not belong inside a documentation merge. Florent decided it during review
instead, which is the right forum: the rule is now *a commit must not touch more than one ticket*,
and the entry is closed. Ticket 08 carries it.

## Consequences a reader will notice

- **`docs/` disappears.** With the idea tracker moved and `docs/agents/` dissolved, nothing is left.
  That removes a real trap: `docs/` and `documentation/` are one letter apart in name and a whole
  concept apart in content. `CLAUDE.md` currently spends a sentence distinguishing them, and a
  newcomer who guesses that `docs/` holds the documentation guesses wrong.
- **`CONTRIBUTING.md` becomes the file to read**, at the name GitHub surfaces in the issue and pull
  request composer. It grows, because it absorbs what `CLAUDE.md` was holding for it — including the
  lint gate it never mentioned.
- **`CLAUDE.md` loses its reference half** and keeps behaviour, commands and gotchas. No line count
  is set as a target: a number gets met by cutting something needed, and the real test is the one
  above — would removing this line cause a mistake?
- **The guidance files stop arguing from the tracker.** Five passages go, and the rules they
  justified stay — stated as rules, with their reasons, and without the lot, ticket or commit that
  produced them. Roughly half the git-flow section is citation today.
- The naming conventions every directory already follows are written down for the first time. Only
  `<LOT-ID>` was ever specified; everything else was practice, which is why two outliers were
  indistinguishable from deliberate exceptions.

## Scope

`CLAUDE.md`, `CONTRIBUTING.md`, `CONTEXT.md`, `README.md`, `CHANGELOG.md`, `docs/agents/`,
`.backlog/`, and — as the work went on — `BACKLOG-CONVENTIONS.md` and the status vocabulary it
defines, `.claude/settings.json`, `.claude/skills/release/SKILL.md` and `test/lua/README.md`.

No change to `skynet-iads-source/`, to the build, to the tests or to `documentation/`. One source
file was touched, `test/lua/test_skynet_iads_contact.lua`, and only to remove a comment citing a
tracker entry that no longer exists.

History is left as written. `CHANGELOG.md` and the archived lot records name paths that later moved;
they describe what was true when written and are not rewritten.

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

One branch, one pull request, and no commit touching more than one ticket.

## Where this lot broke its own rules

Recorded because the archive record is compacted from this file, and a record that only lists
successes is not worth keeping.

- **`79f5bb2`, ticket 01, carries more than ticket 01.** It added the `IDEAS.md` entries belonging to
  the lot opening and to ticket 06 along with the move itself. Named in its own commit message, not
  rewritten.
- **`500a2ce` carries several subjects** — the commit rule, the merge method, the upstream mechanism,
  the Windows note, the `Bash` section. It is one review response and was committed as one; ticket 08
  describes it.
- **Ticket 04 said the commit rule was not to be decided inside this lot** and it was decided inside
  this lot, during review. The forum was right — it was put to Florent as a question — but the
  ticket's own text said otherwise and now says what happened.
- **Ticket 07's done-when was not met when the ticket was closed.** The cross-reference still used a
  generated anchor. Fixed in ticket 11 rather than by quietly amending the condition.

History is not rewritten to tidy any of this.

Ticket 06 waited on Florent, who reported errors in `CONTEXT.md` that a read against the sources had
not surfaced. He amended the file and the review worked from that diff.
