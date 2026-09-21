# 01 — drop the guard that destroys the jammer

Status: 🔄 in-progress

Lot: [FIX-DEMO-DESTROYS-ITS-JAMMER](../PRD.md)

## What

Remove the four-line guard at the end of the jammer section of
`demo-missions/skynet-iads-setup-persian-gulf.lua`, together with the two comment lines that open
and close it.

Nothing else in the file moves. The jammer is still created, armed and given its radio menu exactly
as before — the only change is that it is no longer destroyed immediately afterwards.

One deletion, two missions: `skynet-test-persian-gulf.miz` and
`skynet-test-persian-gulf-stress-test.miz` both load this script and both carry the same client slot
and the same AI F-4E. See the PRD.

## Why this and not a delay

See the PRD's decision table. In short: the guard fires on every load because a client slot has no
`Unit` at `triggerStart`, so a delay only narrows a window that a long briefing reopens, and it
reopens it **silently** — which is how this survived since 2023.

## Why no test

There is nothing to test in the standalone suite. `demo-missions/*.lua` are example setup scripts,
not sources: they are not in `build-tools/listToMerge.txt`, not gated by `luacheck` or `stylua`, and
not loaded by `test/lua/run.lua`. What CI does check is that every Lua file inside an assembled
`.miz` parses, and a deletion cannot break that.

The real check is in the simulator, and it is deliberately the first target of the next lot rather
than a one-off here.

## Definition of done

- Lines 76–81 of `demo-missions/skynet-iads-setup-persian-gulf.lua` are gone; `git diff` shows a
  deletion and nothing else.
- `python build-tools/miz-suite.py check` still passes.
- The assembled mission still parses: `python build-tools/miz-suite.py build` then CI's Lua parse.
- The `## The Persian Gulf demo destroys its own jammer at mission start` section of
  `docs/evolutions.md` is removed — it recorded a decision to defer, and the decision has been
  taken. The PRD of this lot is now the record.
- `CHANGELOG.md` carries an entry under `[Unreleased]`, appended at the end of its section.

## Verified in DCS

_To be filled by the run. Expected: a `Jammer: jammer-emitter` submenu under F10 → Other, and
`JAMMER` lines in `dcs.log` once the red network is lit._
