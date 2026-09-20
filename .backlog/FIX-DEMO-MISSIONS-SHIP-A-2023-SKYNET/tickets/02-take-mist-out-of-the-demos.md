# 02 — Take MiST out of the demo missions

Status: ✅ done — 2026-09-20, merged in PR #33

All four demo missions load `mist_4_5_107.lua`, 312 KB of it. Skynet stopped needing MiST on
2026-08-30 (`fe40c4a`, *refactor: run without MiST*), which wrote `SkynetIADSUtils` to replace it.

The three missions carrying the 2023 artifact have no choice: that build makes 33 MiST calls. Ticket
01 replaces it — then the only MiST left in any demo is one line.

## What to build

Measured 2026-09-20 across the loose setup scripts:

| script | MiST calls |
|---|---|
| `demo-missions/skynet-iads-setup-persian-gulf.lua` | **0** |
| `skynet-insim-last-line-of-defence.lua` (now `unit-tests/last-line-of-defence/`) | **0** |
| `demo-missions/moose_a2a_connector/skynet-and-moose-a2a-dispatcher-setup.lua` | **1** |

The one:

```lua
--:69
mist.scheduleFunction(outputNames, self, 1, 2)
```

`SkynetIADSUtils.scheduleFunction` takes the same arguments and is what the in-sim harness was moved
to in `FIX-IN-SIM-SUITE-TESTS-A-2023-SKYNET` ticket 02. Check the signature at the call site rather
than assuming it — that is what that ticket did, and one of the five calls it listed turned out to be
commented out.

Then `build-tools/miz-suite.py remove mist_4_5_107.lua` per archive, which takes the `mapResource`
key, the `a_do_script_file` call and the `trigrules` entry with it.

### One file in an archive does call MiST, and it is not a setup script

`dcs-bridge.lua`, baked into `skynet-insim-last-line-of-defence.miz` and belonging to
[VEAF/dcs-bridge](https://github.com/VEAF/dcs-bridge), calls `mist.dynAdd`, `mist.build`,
`mist.version`, `mist.majorVersion` and `mist.minorVersion`. Its own header says MIST is *"only
required for the spawn command"*, and the call site is guarded:

```lua
if not mist or not mist.dynAdd then
```

The check mission that loads it does not use that command — it spawns through `coalition.addGroup`
directly, three times, and never through the bridge. So MiST can leave that archive: what goes with
it is the bridge's `spawn` command, which nothing here calls, and the MIST version line in the
bridge's handshake. Measured 2026-09-20 by grepping every member of every demo archive, the artifact
and MiST itself excluded — this was the only hit outside the setup scripts, and `mission` had none
in any of the four.

## Watch out for

**`demo-missions/mist_4_5_107.lua` is committed, and the documentation points at it.**
`documentation/setting-up.md:126-130` says Skynet no longer requires MiST but that "the demo missions
bundle `mist_4_5_107.lua` for other functionality". Once that stops being true the page has to say so
— and that paragraph is the one place a newcomer reads about MiST at all.

**Does anything else in these missions use MiST?** The setup scripts are not the whole mission: a
trigger in the Mission Editor can call MiST directly, and that lives in `mission`, not in a `.lua`.
Grep the archive's `mission` member before removing, not just the scripts.

**MOOSE is not MiST.** `Moose.lua` stays. It is 1.1 MB, it is what that demo demonstrates, and
Skynet's MOOSE connector is a supported feature.

## Definition of done

- No file in any demo archive calls MiST, `mission` included.
- `mist_4_5_107.lua` is out of all four archives, and `miz-suite.py check` is clean.
- `documentation/setting-up.md` no longer tells people the demos bundle MiST.
- Whether `demo-missions/mist_4_5_107.lua` itself should stay in the repository is answered — it is
  312 KB of a dependency nothing left uses.
- A demo has been run in DCS with no `ERROR SCRIPTING` line. Loading MiST is what put a popup on the
  player's screen in the test missions; the same event handler is installed here.
