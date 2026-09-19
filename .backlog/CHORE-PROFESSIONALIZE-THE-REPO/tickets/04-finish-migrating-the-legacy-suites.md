# 04 — Finish migrating the legacy suites

Status: ⬜ ready

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

## Handoff — 2026-09-19

Tickets 01, 02, 03, 05, 06, 07 of this lot are done and merged. This is the only one left, and it
was deliberately saved for last — heaviest, least mechanical. Notes for whoever picks it up:

**The inventory (step 1) is mostly already written down.** `test/lua/README.md`'s "Ported suites"
and "Still DCS-only" sections are current as of this session — cross-check against them rather
than redoing the pass from scratch. As of now, `unit-tests/` holds 15 files; ported (their `.miz`
copy kept, standalone suite is authoritative): `harm-detection`, `abstract-dcs-object-wrapper`,
`moose-a2a-connector`, `jammer`, `abstract-element`, `sam-site`, plus one narrow regression test
off the real `iads`. Still DCS-only, unstarted: `early-warning-radar`, **`abstract-radar-element`**
(this ticket's target), most of `iads`, `red/blue-sam-sites-and-ew-radars`.

**The target file's actual shape**: `unit-tests/test-skynet-iads-abstract-radar-element.lua` is 47
test methods (`grep -n "^function TestSkynetIADSAbstractRadarElement:test"` to list them), not one
monolith — this can be sliced across several PRs rather than ported in one sitting. It builds SAM
sites via `Group.getByName(self.samSiteName)` against `.miz`-baked groups and overrides
`getDetectedTargets`/`getDCSRepresentation` with mocks — **the same shape already ported** in
`test/lua/test_skynet_iads_sam_site.lua` (`dcs-fixtures.lua`'s `F.samGroup`, mock
`enableEmission`/`isExist`/`getController`). That file is the template to copy, not
`abstract-element` or `harm-detection` (simpler classes, thinner fixtures).

**Suggested slice order**, tied to what `FEAT-LAST-LINE-OF-DEFENSE` actually touches (autonomy and
coverage, not HARM evasion or point defence): port `testSetToCorrectAutonomousState`,
`testGoDark`/`testGoLive`, `testGoDarkDueToHARMTestIfAIisOff`,
`testWillGoLiveWhenAutonomousAndHARMDefenceFinished`,
`testSAMSiteAndEWRadarLoosesConnectionAndPowerSourceThenAddANewOneAgain`,
`testInformChildrenOfStateChange` and `testActAsEarlyWarningRadar` first — that cluster is the
actual regression net that lot needs. The HARM-timing, point-defence and cache/aspect-calculation
clusters (roughly half the file) can follow in later slices.

**Local environment, discovered this session**: this machine has no `lua5.1` on `PATH` — only a
scoop-installed Lua 5.5, which is Lua-version-incompatible enough to be actively misleading (no
`math.atan2`, and it crashes `luacheck` outright rather than just misbehaving). A real Lua 5.1.5 is
already installed at `C:\Program Files (x86)\Lua\5.1\lua.exe` (the path `test/lua/README.md`
already documents as the Windows fallback) — use that directly:
`"C:\Program Files (x86)\Lua\5.1\lua.exe" test\lua\run.lua`. Getting `luacheck` running locally on
this machine hit a second wall — its `luafilesystem` dependency needs a C compiler, and the
bundled `luarocks` is wired for MSVC (`cl.exe`, not installed) rather than the `gcc` that is on
`PATH` — not resolved this session; CI (Ubuntu) is the environment of record for it.

**Once a slice ports**, update `test/lua/README.md`'s tracking lists (ported / still DCS-only) in
the same commit — that table is what stopped this ticket from silently reopening for a year.

## Definition of done

- Every legacy suite is either ported or explicitly marked as needing the simulator, in writing.
- `test-skynet-iads-abstract-radar-element.lua` is ported, since the planned work depends on it.
- No behaviour is covered twice by a legacy and a standalone suite.
