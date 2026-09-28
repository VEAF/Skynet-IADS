# 14 — Third review response

**Status**: ✅ done

## Problem

A third review of the whole branch found the three root guidance files consistent with one another,
and four things still open.

**The rule against citing the backlog reached only part of the guidance.** The lot decided that no
guidance file justifies a rule by citing a lot, a ticket, a person or a date, and that no rule names
a consumer. `CLAUDE.md` and `CONTRIBUTING.md` were cleaned; three files that `CLAUDE.md`'s table sends
a reader straight to were not. The `release` skill opens with a pointer to an archived lot whose
directory is gone — the dangling pointer the PRD lists as defect 3 — and cites a sibling project's
model and a person's call. `unit-tests/README.md` and `test/lua/README.md` do the same at length, and
the second names a consumer and hands it a decision. The PRD says "no guidance file" and never says
what one is.

**`CONTEXT.md` was still wrong in its definitions.** The EWR row said it goes dark *only* to evade a
HARM, while an EWR set to stay dark when autonomous goes dark on losing its network. The *acting as
EW* row said the site stays live *permanently*, while HARM defence makes no exception for it — the
same contradiction the previous round fixed one row above. Across three reviews, nearly every error
found in the file was in a definition: a one-line definition invites an absolute, and the absolute is
what goes wrong. Two terms were also used without being defined, and one section contradicted itself.

**The PRD and the tracker had stale lines**: an explanation said to live in `CONTRIBUTING.md` that
now lives in `test/lua/README.md`, consequences written in the present tense of before the work, two
unwrapped paragraphs, and an `IDEAS.md` entry naming a `CLAUDE.md` section that no longer exists and
a `§` pointer as the model to follow.

**The lot threshold contradicted the commit rule.** A lot was required for work that "will land as
several commits", while `CONTRIBUTING.md` says a ticket may need more than one.

## Decisions

Florent's, taken on this review:

- **"Guidance file" means the root instruction files.** The `release` skill is still cleaned here,
  because it opens on a pointer to an archived lot whose directory is gone — this lot's own defect 3,
  in a file the table used to send an agent to. The two test READMEs keep their history for now and
  are recorded in `.backlog/IDEAS.md`: `test/lua/README.md` alone is some 350 lines, much of it a
  record of which lot brought which tests, and sorting that is a lot of its own.
- **`CONTEXT.md` keeps intent only.** The premise and the four concept sections stay, corrected; the
  vocabulary table goes. What survives is a set of reasons — each concept is something that looks
  like a bug and is not, which is what someone about to change the code would otherwise fix. The
  definitions it drops are not owed to the code: `documentation/setting-up` defines the same terms for
  the reader who needs them, so nothing is recorded as displaced.
- **The commits clause leaves the lot threshold only.** A lot is required for more than one
  deliverable or a decision worth recording; how many commits a deliverable takes is the commit
  rule's business, and `CONTRIBUTING.md` keeps it unchanged.

## Work

- `release` skill: no lot, ticket, person, date or sibling project in its reasons.
- `.backlog/IDEAS.md`: an entry for the two test READMEs; the `AGENTS.md` entry corrected.
- `CONTEXT.md`: intent only, and the three places that describe it — its own opening line,
  `CLAUDE.md`'s row, `CONTRIBUTING.md`'s *Layout* row — say so.
- `BACKLOG-CONVENTIONS.md`: the commits clause out of *When a lot is required*; "a closed lot" in
  the shape tree becomes what it means.
- The PRD: the boundary of "guidance file", this ticket's decisions, and the stale lines.

## Done when

No root guidance file cites a lot, ticket, person, date or consumer to justify a rule; the `release`
skill no longer opens on a dangling pointer; `CONTEXT.md` carries no definitions and no claim the
sources contradict; and nothing in the PRD describes the files as they were before the work.

## Changed afterwards

The boundary this ticket drew included the skills, and it was redrawn without them. Bringing a skill
under the guidance rules turned out not to be an editing pass: a skill carries a procedure as well as
reasons, and the `release` skill's procedure contradicts the git flow — a commit on `develop`, a
branch prefix no file allows, and a `develop` → `master` promotion no file describes. That is a lot
of its own, and `.backlog/IDEAS.md` holds it. **Ticket 15.**
