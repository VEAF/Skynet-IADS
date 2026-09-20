# 04 — Finish migrating the legacy suites

Status: 🔄 in-progress — port complete, six legacy suites removed; one question left for David

## Progress

- **Step 1, the inventory: done.** It lives in `test/lua/README.md` ("Ported suites" / "Still
  DCS-only"), kept current as each slice lands, rather than in a one-off document here.
- **Step 2, the port: sliced.** `unit-tests/test-skynet-iads-abstract-radar-element.lua` is 50 test
  methods; porting it in one sitting is a pull request nobody can review. Slice 1 ports the
  autonomy / coverage cluster — 8 tests — into
  `test/lua/test_skynet_iads_abstract_radar_element.lua`, because that is the cluster
  `FEAT-LAST-LINE-OF-DEFENSE` modifies. Slice 2 ports 15 more: HARM timing and defence states, the
  two engagement flags, the parent / child radar bookkeeping.

  Slice 3 ports 16 more: ammunition and missiles in flight, and the engagement zone. Slice 4 ports
  the last 7: point defence and the detected-target cache.

  **The port is done.** The legacy file has 50 test methods, of which **3 are commented out** (the
  two `testController*WhenGoingDark*`, obsolete since `setEmission` arrived in DCS 2.7, and
  `testCallMethodOnTableElements`) and **1 has an empty body**
  (`testPointDefenceWhenOnlyOneEWRadarIsActiveAndAmmoIsStillAvailable`, a `--TODO: write Unit test`
  that was never written). All **46** live ones run standalone.

  The split into four slices, and into three pull requests, was agreed with David on 2026-09-19,
  under the rule `CLAUDE.md` acquired the same day.

  Slice 3 also drew the first entries on the **"needs the simulator"** list the removal decision
  turns on: the `.miz` SA-2 range tests assert the figures DCS units report about themselves
  (53499.2265625 m for the Flat Face). Those are ED's numbers, not Skynet's, and a standalone test
  asking the stub would only prove `dcs-fixtures.lua` repeats itself. They stay.

  One thing the port kept finding: **a legacy test that cannot fail**, four times in this one
  file. Two of slice 2's originals compared bare `{}` mocks with `assertEquals`, and luaunit
  compares tables by value — so the order they claimed to pin was never checked. A third never
  called the method it was named after. A fourth, slice 3's `testSA8GoLiveRangeInPercent`, returned
  on `informOfContact()`'s own guard before the range was ever consulted.

  The fifth is a **finding**, not a defect in the test alone.
  `testPointDefenceWillGoDarkWhenSAMItIsProtectingGoesDark` asserts that a point defence goes dark
  with the site it protects. It passes because its point defence is built without
  `setupElements()`, so `SkynetIADSSamSite:isDestroyed()` answers true and `goLive()` never lit it.
  With a real point defence it **stays lit**: `pointDefencesStopActingAsEW()` is called from
  `goLive()` and from the last remembered HARM ageing out, and from nowhere else. Harmless in the
  live mechanism — nothing but HARM evasion ever lights a point defence — but not harmless for a
  mission that lights one by hand. The standalone test records what the code does, under a name
  that says so.

  Every ported test is checked by mutating the source and watching it go red: 19 mutations across
  the four slices.
- **Step 4, removing the legacy copy: done for six suites.** `abstract-dcs-object-wrapper`,
  `abstract-element`, `contact`, `harm-detection`, `jammer` and `sam-site` are gone from both
  places — the loose `unit-tests/*.lua` and the copy inside `skynet-unit-tests.miz`. Each was
  checked test by test: every assertion runs standalone, and none of them asserts terrain, real
  detection, or a figure a DCS unit reports about itself.

  Editing the `.miz` turned out to need a tool, `build-tools/miz-suite.py`, and the reason is
  worth knowing: a script is wired into a `.miz` in **four** places, not three. Besides the file,
  its `mapResource` key and the compiled `a_do_script_file(...)` call in `mission`'s `trig.actions`,
  the Mission Editor keeps its own structured copy of the same trigger in `trigrules`, an array
  whose indices have to stay contiguous. The first attempt removed three of the four and the tool's
  own check caught it.

  **What stays, and why.** `iads`, `early-warning-radar` and `red`/`blue-sam-sites-and-ew-radars`
  enumerate the demo world. Two of the three `moose-a2a-connector` tests do the same.
  `abstract-radar-element` is fully ported but still asserts the ranges DCS reports for the units it
  models — 53499.2265625 m for the SA-2's Flat Face — and that is the one thing a stub cannot stand
  in for. **Open question for David:** keep 47 KB of otherwise-duplicated suite for three numbers,
  or reduce it in the `.miz` to a small canary that checks only ED's figures? Reducing it means
  authoring an in-sim suite, which only a DCS session can judge — so it is not something to do
  unasked.

  **Not fixed here, and pre-existing:** the loose `unit-tests/test-skynet-iads.lua` carries
  `testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage` (the `3a94937` fix) and its `.miz` copy
  does not, so the in-sim suite has never run it. The standalone suite does, so nothing is
  uncovered; the two copies are simply still out of step. Left alone: syncing them changes what the
  in-sim suite runs, which only DCS can judge.

- **Step 4, the reasoning that got there:** The `unit-tests/*.lua` files are
  loose copies of scripts baked into `skynet-unit-tests.miz` (`l10n/DEFAULT/<same name>.lua`);
  editing one without rebuilding the `.miz` makes the two drift, which is the problem the step
  exists to prevent. It has already happened once: the loose
  `unit-tests/test-skynet-iads.lua` carries `testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage`
  (the `3a94937` fix) and the `.miz`'s copy does not, so the in-sim suite has never run it — 38
  lines of drift, and the only file of the fifteen where the two copies differ at all. Every earlier
  port (`sam-site`, `jammer`, `harm-detection`…) kept its copy and recorded the overlap in
  `test/lua/README.md` instead. That is a decision to confirm once the port is complete, not per
  slice.

  **Confirmed, David 2026-09-19: the legacy copy goes once what it covered is covered by ours** —
  both the loose `unit-tests/*.lua` and the copy baked into the `.miz`. The condition is coverage,
  not a count: for each suite, every behaviour it asserts is asserted standalone, or is on the
  "needs the simulator" list with a reason. A test that only ever passed because it ran against real
  DCS objects is not "covered" by a standalone test that asks the stub the same question — that one
  stays in the `.miz`. The removal is one pass at the end of the port, per suite, not per slice.

`test/lua/README.md` already states the intent: logic tests go to the standalone suite, and only
what genuinely needs the simulator — terrain elevation, real detection geometry, in-game events —
stays in `unit-tests/*.miz`.

The migration is unfinished, and the gap is not cosmetic. `docs/evolutions.md` records it against
issue #3: *"abstract-radar-element is NOT ported to test/lua yet (still on the DCS-only list).
Decide: port a slice of that suite, or write a narrow standalone test"*. That file is 47 KB of
tests, and it covers `SkynetIADSAbstractRadarElement` — the class carrying `goLive`, `goDark`,
`setToCorrectAutonomousState` and the HARM evasion. In other words, the class both tickets of
`FEAT-LAST-LINE-OF-DEFENSE` modify.

## What to do

1. Inventory `unit-tests/`: for each suite, decide **logic** or **needs the simulator**, and write
   the verdict down. The inventory is the deliverable of the first pass, not the migration itself.
2. Port the logic ones, starting with `test-skynet-iads-abstract-radar-element.lua`, because it
   blocks regression tests for work that is already planned.
3. Leave the genuinely in-sim ones where they are and say so explicitly in the README, so the next
   person does not reopen the question.
4. Once a suite is ported, remove the legacy copy rather than keeping both — two suites that drift
   are worse than one.

## Watch out for

Porting a test is not copying it. The legacy suites run inside DCS against real objects; the
standalone suite runs against `test/lua/dcs-stub.lua`. A test that passes only because the stub
returns something convenient is worth nothing. When a ported test needs the stub extended, extend it
deliberately and write down what real behaviour it is standing in for.

## Definition of done

- Every legacy suite is either ported or explicitly marked as needing the simulator, in writing.
- `test-skynet-iads-abstract-radar-element.lua` is ported, since the planned work depends on it.
- No behaviour is covered twice by a legacy and a standalone suite.
