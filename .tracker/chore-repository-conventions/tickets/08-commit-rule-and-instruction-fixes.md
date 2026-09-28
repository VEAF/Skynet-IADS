# 08 — The commit rule, and four corrections to the instruction files

**Status**: ✅ done

## Problem

Review of `CLAUDE.md` after ticket 05, by Florent. Five findings, of which one is a rule change.

**The commit rule was stated backwards.** "One commit per ticket" forbids what the project does —
one pull request carried six tickets in twelve commits — because the constraint is against *mixing*,
not about *counting*.

Ticket 04 had said this rule was to be carried across verbatim and decided elsewhere, on the grounds
that changing how the project works does not belong inside a documentation merge. Florent decided it
during this review instead, which is the right forum: it was put to him as a question, not smuggled
into a diff.

The other four: the rule against opening a pull request upstream stated a prohibition without the
mechanism that causes the mistake, so it read as pointless; the Windows note asserted that `lua5.1`
is not on `PATH`, which is one machine rather than a property of the platform; and a `Bash` section
granted nothing, since permissions are enforced by `settings.json`, while telling an agent never to
pause — including before destructive commands.

## Work

- The rule becomes **a commit must not touch more than one ticket**, which admits the lot-opening
  commit, a ticket needing two, and a review response appended rather than squashed back.
- **The merge method follows from it** and is now stated: merged with a merge commit, never squashed,
  because a squash collapses the branch into one commit and destroys the per-ticket history. It was
  already the practice, but it is a repository setting that can be changed, and the rule would then
  stop working silently.
- The upstream rule gives its mechanism: this repository is a GitHub fork, so `gh pr create` without
  `--repo` targets the parent, as does the web UI's compare banner.
- The Windows note becomes a condition and a default install location.
- The `Bash` section is removed.

Closes the `.backlog/IDEAS.md` entry that had held the commit-rule analysis open.

## Done when

Both files state the rule the same way, the merge method is stated beside it, and `CLAUDE.md` no
longer claims to grant permissions.
