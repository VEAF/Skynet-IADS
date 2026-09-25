# 03 — The tracker documents itself; docs/ disappears

**Status**: ⬜ ready

## Problem

`docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md` hold the rules for the backlog —
lot shape, PRD versus ticket, the status vocabulary, the blocking convention — one directory away
from the backlog they describe. Neither is Claude-specific in content: a human reading
`.backlog/INDEX.md` needs the legend exactly as much as an agent does.

**The status vocabulary is already duplicated.** `.backlog/INDEX.md` carries a Legend with the six
glyphs and the ⏸/⬜ distinction; `triage-labels.md` carries both again, in fuller form. Two copies,
free to drift, of the one thing that must be read identically in the index, in every PRD and in every
ticket.

And `docs/` is a trap independent of its contents: it sits beside `documentation/`, one letter apart
in name and a whole concept apart in content. `CLAUDE.md` spends a sentence distinguishing them. With
the idea tracker gone (ticket 01), `agents/` is all that is left, so the directory can go.

## Work

- Create `BACKLOG-CONVENTIONS.md` from both files: the `.backlog/` shape, `<LOT-ID>` prefixes, what
  belongs in a PRD versus a ticket versus the index, the three-tracker split, the status vocabulary,
  the ⬜/⏸ distinction, and the blocking rule.
- Rename `.backlog/README.md` to `.backlog/INDEX.md`. Once the root file is the door, "read me
  first" is false — the thing to read first is no longer in that directory — and `INDEX.md` says
  what it is, beside `IDEAS.md`. One cost, accepted: GitHub renders a directory's `README.md` inline
  and will not render `INDEX.md`, so browsing `.backlog/` shows a bare listing. The root file links
  straight to it.
- Collapse the duplicated Legend: the index keeps the lot table and links to `BACKLOG-CONVENTIONS.md`
  for the vocabulary. The index is the file that changes weekly; the rules change rarely. Keeping
  them apart is deliberate.
- `git rm` both source files; the `docs/` directory goes with them.
- Repoint `CLAUDE.md`'s *Agent notes* at `BACKLOG-CONVENTIONS.md`. The pointer stays in `CLAUDE.md`
  rather than becoming a `.backlog/CLAUDE.md` or a path-scoped rule: both of those load only when a
  file in the directory is **read**, and the moment these rules are needed is when a lot is being
  *created*, possibly in a directory that does not exist yet. See the PRD.

## Done when

`docs/` no longer exists, `BACKLOG-CONVENTIONS.md` holds every rule the two deleted files held, the
status glyphs appear in exactly one place, and nothing in the repository links to `docs/agents/`
except the archived records and `CHANGELOG.md`, which are history.
