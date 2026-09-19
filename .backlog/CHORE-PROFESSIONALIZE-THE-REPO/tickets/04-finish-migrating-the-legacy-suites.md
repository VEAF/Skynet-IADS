# 04 — Finish migrating the legacy suites

Status: 🔄 in-progress — slices 1 and 2 done; 23 real tests of `abstract-radar-element` left

## Progress

- **Step 1, the inventory: done.** It lives in `test/lua/README.md` ("Ported suites" / "Still
  DCS-only"), kept current as each slice lands, rather than in a one-off document here.
- **Step 2, the port: sliced.** `unit-tests/test-skynet-iads-abstract-radar-element.lua` is 50 test
  methods; porting it in one sitting is a pull request nobody can review. Slice 1 ports the
  autonomy / coverage cluster — 8 tests — into
  `test/lua/test_skynet_iads_abstract_radar_element.lua`, because that is the cluster
  `FEAT-LAST-LINE-OF-DEFENSE` modifies. Slice 2 ports 15 more: HARM timing and defence states, the
  two engagement flags, the parent / child radar bookkeeping.

  Of the 27 methods left, **3 are commented out in the legacy file** (the two
  `testController*WhenGoingDark*`, obsolete since `setEmission` arrived in DCS 2.7, and
  `testCallMethodOnTableElements`) and **1 has an empty body**
  (`testPointDefenceWhenOnlyOneEWRadarIsActiveAndAmmoIsStillAvailable`, a `--TODO: write Unit test`
  that was never written). So **23 real tests remain**: ammo and missiles-in-flight, the SA-2
  range / engagement-zone tests, point defence, cached targets. `test/lua/README.md` lists them.

  One thing the port keeps finding: a legacy test that cannot fail. Two of slice 2's originals
  compared bare `{}` mocks with `assertEquals`, and luaunit compares tables by value — so the order
  they claimed to pin was never checked; a third never called the method it was named after. Each
  ported test is checked by mutating the source and watching it go red.
- **Step 4, removing the legacy copy: not done, and deliberately.** The `unit-tests/*.lua` files are
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
