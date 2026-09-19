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

## Definition of done

- Every legacy suite is either ported or explicitly marked as needing the simulator, in writing.
- `test-skynet-iads-abstract-radar-element.lua` is ported, since the planned work depends on it.
- No behaviour is covered twice by a legacy and a standalone suite.
