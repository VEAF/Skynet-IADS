# 15 — Fourth review response

**Status**: ✅ done

## Problem

A fourth review of the whole branch, before the pull request was opened, found the three root
guidance files coherent with one another and with the repository they describe — every pointer
resolves to a file that exists, every repeated command is correct, and nothing outside the backlog
records still names `docs/`, `contributing.md` or `.backlog/README.md`. What it found open was in the
boundary of the work, the tracker's own vocabulary, and the lot's records.

**The lot never settled what a guidance file is.** Four records gave three answers: `CONTRIBUTING.md`
said the five root files, ticket 14 said the root files *and the skills*, the PRD said the skills were
"not covered yet", and `.backlog/IDEAS.md` said they were outside the rules. The behaviour matched
none of them — the `release` skill was cleaned, `skynet-runtime-debug` was not — so ticket 14's
done-when asserted something untrue of the repository.

**A row in `CLAUDE.md` sent an agent to a skill it cannot invoke.** `release/SKILL.md` sets
`disable-model-invocation: true`.

**The `merged` status cost more than it bought.** Added by ticket 10 to separate three lots in
`develop` from this one committed and unmerged, it made a second glyph out of a distinction that
archiving already draws.

**The `.backlog/` exception listed what needs a pull request instead of what does not.** Read as the
exhaustive list it looks like, "the moment a change touches `skynet-iads-source/`, `test/`,
`documentation/`, `CHANGELOG.md` or the build" licenses committing `CLAUDE.md` straight to `develop`.
This branch is its own counter-example.

**Two records were stale**: ticket 11 pointed at a PRD section the last commit had restructured away —
the failure ticket 13 legislated against, two commits after it was legislated — and ticket 10
described a status that is being removed.

## Decisions

Florent's, taken on this review:

- **The skills are out of scope, and a lot of their own, soon.** Bringing one under the guidance rules
  is not an editing pass: a skill carries a procedure as well as reasons, and the `release` skill's
  procedure contradicts the git flow in three places. The boundary in `CONTRIBUTING.md` — the root
  instruction files — is the one that stands; the `release` skill keeps the one fix it had here, its
  dangling opening pointer.
- **`CLAUDE.md` says nothing about cutting a release.** The tag workflow performs the release and the
  skill that drives the rest is the user's to invoke, so the row named a task no agent can do.
- **✅ is the last status.** `merged` goes. A lot leaves the index a few days after its pull request
  lands, so a listed lot is either unmerged or newly merged and the glyph adds nothing. What ticket 10
  settled and keeps is that ✅ means *committed*.
- **Branch names are not tied to lot names.** Lot IDs are prefixed `FEAT-`, `FIX-`, `CHORE-`,
  `INVESTIGATE-`, `REFACTOR-` while branches take `feature/` or `fix/`, so a `CHORE-` lot branches
  `feature/…`. Left as it is and recorded in `.backlog/IDEAS.md` rather than imposed now.
- **The shipped settings stay as they are.** Pre-approving the four documented commands was considered
  and refused; the prompts are acceptable.

## Work

- `CONTRIBUTING.md`: the `.backlog/` exception states its own limit, and says that a guidance file is
  not in it.
- `CLAUDE.md`: the release row goes; the workflow ends by setting the lot to ✅ in its `PRD.md` and in
  the index, which is the step the review found missing from it.
- `BACKLOG-CONVENTIONS.md`: 🔀 out of the vocabulary, and the archiving trigger stated without it.
- `.backlog/INDEX.md`: the three lots at 🔀 become ✅, and the glyph legend follows.
- `.backlog/IDEAS.md`: the skills entry becomes the next lot's seed and gains the `release` skill's
  procedure and the undescribed `develop` → `master` promotion; two new entries, for branch naming and
  for four small imprecisions the review measured against the workflows and the source.
- The PRD, and tickets 10, 11 and 14: the boundary, the dropped status, the dead pointer.

## Done when

`CONTRIBUTING.md`, the PRD and `.backlog/IDEAS.md` give one answer to what a guidance file is; 🔀 is
a status nowhere and only a record of one in ticket 10; `CLAUDE.md` names no task an agent cannot
perform; and every open finding of this review is either fixed or in `.backlog/IDEAS.md`.
