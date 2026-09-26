# 10 — *done* means committed, and *merged* becomes a status

**Status**: ✅ done

## Problem

The status vocabulary defined ✅ done as "merged". This lot contradicted that while writing it: its
tickets were marked done with the pull request not yet opened.

Correcting the definition then collapsed a distinction that was doing real work. The index carried
three lots marked done that were genuinely merged, beside this one whose work was committed and
unmerged; under "done means committed" both would have read identically.

## Work

- ✅ **done** — the work is committed. For a ticket that is the end of it.
- 🔀 **merged** — new, **lots only**. The pull request has landed on `develop`; next stop is the
  archive. A ticket never reaches it: a ticket is finished when its commit lands on the branch, and
  it is the lot that is merged.
- The three merged lots in the index are retagged.

A lot reaching ✅ is now also a signal: every ticket is committed and none of it is in `develop` yet,
which is the moment its pull request is worth opening.

## Done when

The index distinguishes the two states, and no ticket carries 🔀.
