# 13 — Pointers name files, not headings

**Status**: ✅ done

## Problem

Every rule stated once means every other file points at it, and this lot has been paying for the
pointers ever since. Three kinds have needed a correction each, in the lot's own reviews:

- **`§ <heading>` in `CLAUDE.md`.** A row named a section that ticket 07 had renamed; it was dead a
  day after it was written. `.backlog/IDEAS.md` proposes a check to catch the next one.
- **Anchor links between and inside the guidance files.** `CONTRIBUTING.md` linked to a generated
  anchor, then to `README.md#maintenance`, and each fix added an explicit `<a id>` to keep the link
  alive through a reword.
- **Code names in `CONTEXT.md`.** Ticket 12 added an *In code* column mapping each term to a class or
  method, on the grounds that a stale identifier fails on the first search.

Each fix was correct, and each one left another reference that has to be kept in step by hand. The
section names buy almost nothing for the reader they are written for: an agent following a pointer
reads the whole file, and `CONTRIBUTING.md` is well within one read. A person has GitHub's outline.
What makes the table work is the *task* in the left column — that is what makes someone open the
file — and a file name is enough to say which.

The code names reverse a decision taken in ticket 12. A stale identifier does fail on a search, but
only when someone searches; until then it is read as true. Someone about to change the code finds
the class in seconds without it.

## Work

- **`CLAUDE.md` names files, never headings.** The table's right column says which file, and what it
  covers in plain words that do not have to match a heading. The two `§` references in the prose go
  the same way. A line under the table states the rule, so the next row does not bring a heading back.
- **Close the `IDEAS.md` entry** proposing a `§` check: there is nothing left for it to resolve.
- **No anchor links in the guidance files.** `CONTRIBUTING.md` links to `README.md` as a file, and
  drops the in-page link to its own *Documentation* section a few lines above. The two `<a id>`
  anchors added for those links go. `README.md`'s `#en` / `#fr` anchors stay: they are the language
  switcher, a feature for readers, not a cross-reference between files.
- **`CONTEXT.md` loses its code-name column**, and the connection-node row loses the method name in
  its definition.
- **The `CONTEXT.md` pointer says what the file holds now.** `CLAUDE.md`'s row and the file's own
  opening line both promise "the words the code uses for it", which the column was added to keep.
  Without it, both describe what is there: the domain's vocabulary and what will surprise someone
  reading the code.
- The PRD records the two decisions beside the others taken during review.

## Done when

`CLAUDE.md` contains no `§`; no guidance file at the root links to an anchor; `CONTEXT.md` has no
code identifiers in its vocabulary; and nothing in `CLAUDE.md` or `CONTEXT.md` promises content the
file does not carry.
