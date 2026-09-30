# 11 — Review response

**Status**: ✅ done

## Problem

An independent review of the whole branch, before the pull request was opened, found nine items. One
ticket rather than one per item: the subject is *responding to this review*, and each response is
already readable as its own commit.

## What it found, and what was done

**A dead pointer in the table the PRD calls load-bearing.** Ticket 07 renamed a section and the row
naming it was not updated — dead within a day, in the one table that survives compaction and is the
only route back to delegated content. All six pointers then in the file were audited: five
resolved, one did not. Two more were added afterwards, by the commits for the git-flow and
lot-threshold decisions, so the table now holds ten references to seven sections across two files.
`.backlog/IDEAS.md` carries the follow-up, that nothing verifies these names and the check is small.

**The autonomy claim in `CONTEXT.md` was one trigger of four.** `hasValidParentRadar` requires the
element's own connection node, a usable command centre, *and* a parent with power, a connection node,
the EW role and not destroyed. A network can go autonomous without a radar being touched. EWRs go
autonomous on a shorter rule, so the section was not about SAM sites alone. Connection nodes were
missing from the vocabulary while being load-bearing for all of it.

**Two rules were still stated twice** — the stub warning, and the version story in the `release`
skill, which also named a person and a date.

**Wording that would be read the wrong way**: the `.backlog/` exception read as an instruction to
leave the branch; the `CONTEXT.md` pointer named a hierarchy that file no longer discusses, and
`CONTEXT.md` was absent from `CONTRIBUTING.md` entirely; `lint.sh` was given bare among PowerShell
commands; the tracker called an idea an "evolution" and archived lots "closed", which is not a status.

**Ticket 07's done-when was not met**: the cross-reference used a generated anchor, which does not
survive a reword. It targets an explicit `<a id>` now, as `README.md` already does.

## Decisions taken during the review

Four were Florent's. Each is recorded in `PRD.md`, which is what the archive record is compacted
from; they are listed here only so this ticket is readable alone:

- the changelog is scoped to source changes, stated in one file, and this lot's four entries go;
- `CLAUDE.md` keeps the git rules bare and `CONTRIBUTING.md` explains them;
- `README.md` is authoritative for joint maintenance;
- a lot is required only for work with more than one deliverable or a decision worth recording.

## Done when

Every item is answered or declined in writing, and the backlog records describe what was actually
done — including where this lot broke its own rules.
