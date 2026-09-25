# 01 — The idea tracker moves into the backlog

**Status**: 🔄 in-progress

## Problem

`docs/evolutions.md` recorded what had been noticed but not yet committed to — the step before a lot.
That is the same subject as everything under `.backlog/`, one directory away, which made it the one
tracker nobody opened while looking at the others.

## Work

- `git mv docs/evolutions.md .backlog/IDEAS.md`.
- Recompute the two relative links inside it. `../.backlog/archive/…` becomes `archive/…`; the
  source link was `../../../skynet-iads-source/skynet-iads.lua`, three levels up from `docs/` and so
  already broken before the move, and becomes `../skynet-iads-source/skynet-iads.lua`.
- Update the three live references: `CLAUDE.md`, `contributing.md`, `docs/agents/issue-tracker.md`.
  Add `IDEAS.md` to the `Shape` tree in `issue-tracker.md`, which lists what `.backlog/` contains.
- **A fourth reference, in a source file**: `test/lua/test_skynet_iads_contact.lua:67` opens a comment
  with `docs/evolutions.md "No isExist() / nil guard before Object.getCategory…"`. It is stale twice
  over — the path moved, and the entry it names is no longer in the tracker at all. Drop the citation
  and keep the explanation, which stands on its own; that is the same rule the guidance files follow.
  Search `*.lua` and `*.txt` as well as `*.md` — the first sweep of this ticket checked only prose
  files and missed this one.
- One line in the backlog index saying `IDEAS.md` sits there and is *not* a lot.
- Changelog entry at the end of `### Changed`.

Paths only. The prose still calls these things *evolutions* — renaming the concept is a larger call
than renaming the file, and is not made here.

History is not rewritten: `CHANGELOG.md` and two archived lot records name `docs/evolutions.md`
describing what was true when they were written.

## Done when

`.backlog/IDEAS.md` exists with its two links resolving; `docs/` holds nothing but `agents/`; and
`grep -rn "evolutions" --exclude-dir=.git .` returns only `CHANGELOG.md` and the two archived lot
records, which are history.
