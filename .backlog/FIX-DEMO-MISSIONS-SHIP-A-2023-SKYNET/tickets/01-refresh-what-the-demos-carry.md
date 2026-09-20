# 01 — Refresh what the demo missions carry

Status: ⬜ ready — **blocked on ticket 03**, which decides this ticket's shape

Three of the four demo missions carry `SKYNET VERSION: 3.2 | BUILD TIME: 29.12.2023 1905Z`, and none
of them has been touched since 2023-12-29. `develop` is on 3.5.0.

## What to build

**This depends on ticket 03.** Under (b) or (c) the work is to point the existing machinery at
`demo-missions/`; under (a) it is to add a comparison the previous lot deliberately removed. The two
have almost nothing in common, which is why 03 comes first.

What holds either way:

- **The setup scripts are assembled from their loose copies, not copied by hand.** Three of the four
  archives already disagree with the loose file they are supposed to mirror; keeping both is what
  produced that.
- **`Moose.lua` and `dcs-bridge.lua` have no source in the repository** and must survive untouched.
  `miz-suite.py` has `NO_SOURCE_IN_REPO` for this, currently empty — MiST was its only entry until
  2026-09-20. Vendoring MOOSE here is not proposed: 1.1 MB belonging to another project.
- **`ARCHIVES` in `miz-suite.py` is a tuple of two paths.** Adding four more is the mechanical part;
  the interesting part is that `source_of()` currently looks in the archive's own directory and then
  in `unit-tests/`, which is wrong for `demo-missions/` and wronger for its `moose_a2a_connector/`
  subdirectory. Read it before extending it.
- **`skynet-insim-last-line-of-defence.miz` does not need refreshing.** It carries 3.5.0 built
  2026-09-19. It is in this lot for MiST (ticket 02) and for its drifted setup script. Do not put a
  newer artifact in a mission nobody has flown since.

## Watch out for

**A demo is judged by flying it, not by a pass count.** The in-sim suite answered "119 tests, 0
failures"; a demo answers "does it still demonstrate what it is for". `skynet-test-persian-gulf.miz`
is the one `documentation/` points at, so it is the one that has to be flown. The stress test is
where a wrong answer hides best — it is meant to look busy.

**Expect the demos to behave differently, and that is the point.** Three years of changes sit between
3.2 and 3.5.0, including `FEAT-LAST-LINE-OF-DEFENSE` and `FIX-COVERAGE-UPDATE-DARKENS-SITES`. Sites
will wake and go dark at different moments than they used to. A difference is not a regression here;
what would be a regression is an error in the log, or a site that never lights at all.

**The setup scripts may not survive three years unchanged either.** They call into Skynet's public
API, and `documentation/api.md` is the record of what that API is now. If one of them calls something
that has been renamed, it fails at mission start — which is a genuine finding, and belongs in this
lot rather than being patched past.

## Definition of done

- Every demo mission runs the Skynet this repository ships, by whatever mechanism ticket 03 chose.
- The setup scripts inside the archives and the loose copies cannot disagree.
- `skynet-test-persian-gulf.miz` has been flown in DCS and still demonstrates an IADS: sites wake,
  sites go dark, no error in the log.
- What changed in behaviour between 3.2 and 3.5.0, as observed, is written down here — that is the
  first honest description this project will have of what three years did.
