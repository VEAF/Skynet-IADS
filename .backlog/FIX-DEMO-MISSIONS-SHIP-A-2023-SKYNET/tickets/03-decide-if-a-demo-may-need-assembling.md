# 03 — Decide whether a demo mission may need assembling

Status: ✅ done — 2026-09-20, David chose **(b)**

`FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET` ticket 05 settled this for the *test* missions: the archives
in git hold a placeholder for every script, and `miz-suite.py build` assembles the playable mission
into the git-ignored `build/missions/`. Nothing can go stale because nothing is stored twice.

A demo mission is not a test mission. Somebody clones or downloads this repository **to run it**. If
`demo-missions/skynet-test-persian-gulf.miz` becomes a template, opening it in DCS gives a
placeholder message instead of a demonstration — and the published documentation points at that file.

## Three readings

**a. Demos stay playable; a check keeps them honest.** The archives keep a real copy of the
deliverable, and CI fails when it differs from a fresh build. Whoever changes `skynet-iads-source/`
reruns the refresh and commits the archives.
*Cost:* a binary in the diff of most pull requests — the exact trade the previous lot walked away
from, and it walked away for a reason. 4 archives here instead of 2, so it is worse.
*What it buys:* anyone can clone and fly, today, with no tooling.

**b. Demos are assembled, and the release ships them.** Same design as the test missions: the
repository holds templates, `miz-suite.py build` assembles. The playable missions become **release
assets**, attached by `.github/workflows/release.yml` alongside `skynet-iads-compiled.lua` — which is
already generated, already not committed, and already published that way.
*Cost:* the repository stops being something you can fly from directly. Between two releases, running
a demo means running the build. The documentation has to say so, in the page a newcomer reads first.
*What it buys:* nothing can go stale, and what people download from the Releases page is assembled
from the code that release ships — which is stronger than what (a) gives them.

**c. Split them.** `skynet-test-persian-gulf.miz` is the one the documentation points at and stays
playable, refreshed by hand when a release is cut. The other three — the stress test, the MOOSE
connector, the last-line-of-defence demo — are developer material and become templates.
*Cost:* two mechanisms for four files, and a rule about which is which that somebody will get wrong.
*What it buys:* the newcomer's path is untouched; the drift-prone majority stops drifting.

## Recommendation

**(b)**, and the reason is that the Releases page already works this way. The deliverable is not in
this repository either — it is built and attached to a release, and nobody finds that surprising. A
demo mission is the same kind of thing: an artifact built from the sources, not a source. It also
means the demo somebody downloads carries exactly the Skynet that release shipped, which is a
guarantee (a) cannot make between two releases.

The objection to (b) is real and it is about newcomers, not about design: "clone and open the .miz"
is one step, "clone, install PowerShell and Python, run two commands, then open the .miz" is not. If
that weighs more than the guarantee, **(c)** is the honest compromise and I would take it over (a) —
(a) pays the cost of a committed copy in every pull request, forever, to protect a case (c) protects
for free.

## Decision — (b), 2026-09-20

David chose **(b)**: every demo becomes a template, `miz-suite.py build` assembles, and the playable
missions are attached to the release.

He was given one figure the write-up above did not have. **This repository has published no GitHub
release at all** — `gh release list` on `VEAF/Skynet-IADS` is empty, and the release workflow is
manual (`CHORE-PROFESSIONALIZE-THE-REPO` ticket 03). So the argument "the Releases page already
works this way" is true of the design and not yet true of the facts, and (b) has a consequence that
has to be said plainly rather than discovered:

- **Until a release is cut, there is nowhere to download a playable demo from.** The Quick start in
  `documentation/index.md` links to `raw/master/demo-missions/skynet-test-persian-gulf.miz`. Under
  (b) that link hands a newcomer a template whose first script calls `env.error`.
- Ticket 01 therefore has to repoint that link and say, in the page a newcomer reads first, how to
  assemble a demo from a checkout. **Cutting the first release is not in this lot**, and it is the
  thing that closes the gap — recorded at the bottom of the PRD as a blocker on nobody.

He chose it anyway, with that on the table. Nothing else in the lot is affected by the caveat.

## Watch out for

**Whatever wins, the setup scripts are the easy half.** They are small, they are already committed
loose, and three of the four archives disagree with their loose copy. Even under (a) those should be
assembled rather than copied.

**`Moose.lua` and `dcs-bridge.lua` are in no archive's source.** Under (b) or (c) they stay in the
template as-is and go in `NO_SOURCE_IN_REPO`; under (a) nothing changes for them.

## Definition of done

- David has chosen a, b or c, and the reason is written here. ✅ — (b), 2026-09-20
- Ticket 01 is rewritten to match before any code is written. ✅
