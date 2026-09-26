# 07 — Streamline CONTRIBUTING.md

**Status**: ⏸ paused — to analyse

> **Do not start this before tickets 04 and 05 have landed.** Nothing is expected of anyone; this is
> sequencing. Ticket 04 moves the seven duplicated subjects, the lint section and the naming
> conventions *into* this file, and ticket 05 empties the rest of `CLAUDE.md` towards it. Streamlining
> beforehand would be reorganising a file that is about to change shape. **What restarts it**: 04 and
> 05 merged, or abandoned.

## Problem

`CONTRIBUTING.md` is 153 lines today and will be closer to 250 once ticket 04 has finished with it.
It grew by addition, and the seams show. Four things worth analysing, found while reading it on
2026-09-26 — the list is a starting point, not the scope.

**1. A section is filed under the wrong parent.** *The README is hand-written, the documentation is
published* is an `###` nested inside `## Building`. Publishing documentation is not a kind of
building, and the whole bilingual-documentation contract — the three rules, the gate, the local
preview — is therefore reachable only by reading a section about the artifact.

**2. The order is not the order anyone works in.** What you need → Layout → Git flow → English →
Test first → Building → Versioning → Changelog → Editor. Git flow arrives before the reader knows
how to build or test, and the changelog rule sits three sections after the pull request it belongs
to. A newcomer's actual path is prerequisites, layout, build, test, commit, pull request.

**3. Two passages are duplicated judgement, which is what this lot exists to end.**

- **Versioning.** `CONTRIBUTING.md` and `CHANGELOG.md`'s *A note on version numbers* both explain
  the two coexisting schemes, that the project continues the artifact's lineage, that 3.5.0 is the
  first release under joint maintenance and that the `RP` suffix is dropped. Same decision, stated
  twice, free to drift. The changelog is where a version story belongs; the guide needs the rule —
  semantic versioning, and a change to what a mission sees at runtime is at least a minor.
- **Joint maintenance.** The opening paragraph, `README.md`'s *Maintenance* section and `CLAUDE.md`'s
  header each say that VEAF and the Regroupement maintain the project here and that neither upstream
  is a source. Three copies. Decide which one is authoritative and let the others point at it or say
  it in a clause.

**4. An internal link depends on a generated anchor.** *Everything in English…* links to
`#the-readme-is-hand-written-the-documentation-is-published`. Reword that heading and the link dies
silently. It is the failure the documentation convention already forbids under `documentation/`, and
`docs-check.py` does not cover the root, so nothing would catch it.

Also to look at, without a prior opinion: whether the three-line *Editor* section earns its place,
and whether the *Layout* table should list every directory or only the ones a contributor edits. The
table needs updating regardless — `docs/` will be gone, `.backlog/INDEX.md` and
`BACKLOG-CONVENTIONS.md` will exist.

## Work

To be decided by the analysis. The obvious shape is a reordering plus the two de-duplications, but
the file will have just absorbed a great deal from `CLAUDE.md` and the right structure is easier to
see then than now.

Constraint carried from the lot: whatever moves, no rule may end up stated in two places, and no rule
may explain itself by pointing at a PRD, a ticket, a lot or a commit.

## Done when

A contributor can read the file top to bottom in the order they would actually do the work; every
rule appears once in the repository; the internal cross-reference survives a reworded heading; and
the `Layout` table matches what the repository contains after tickets 01 and 03.
