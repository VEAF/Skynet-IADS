# 02 — contributing.md takes the name the repository predicts

**Status**: ⬜ ready

## Problem

Every other markdown file at the root is uppercase — `CHANGELOG.md`, `CLAUDE.md`, `CONTEXT.md`,
`LICENSE.md`, `README.md`. `contributing.md` is alone in lowercase, and nothing in the repository
states the convention it breaks, so it is indistinguishable from a deliberate exception.

There is a functional reason on top of the cosmetic one: GitHub special-cases `CONTRIBUTING.md` and
surfaces it in the issue and pull request composer. Lowercase, it is just a file.

## Work

- Rename to `CONTRIBUTING.md`.
- Update the three live references: `README.md`, `CLAUDE.md`, `.claude/skills/release/SKILL.md`.
- Leave `CHANGELOG.md` and `.backlog/FEAT-BILINGUAL-DOCUMENTATION/tickets/05-instructions.md` alone.
  Both describe what was true when written.

**The rename is case-only, and this is a Windows checkout.** `core.ignorecase` is on by default, so
a plain `git mv` reports success and stages nothing. Go through a temporary name:

```
git mv contributing.md contributing.tmp.md
git mv contributing.tmp.md CONTRIBUTING.md
```

Then confirm with `git status` that a rename is actually staged, not an empty diff.

The naming conventions this rename conforms to are written down in ticket 04, not here — this ticket
is the mechanical move, so that the commit is readable as one.

## Done when

`git show --stat` on the commit shows `contributing.md → CONTRIBUTING.md`, the three referencing
files point at the new name, and `ls *.md` shows five uppercase names and nothing else.
