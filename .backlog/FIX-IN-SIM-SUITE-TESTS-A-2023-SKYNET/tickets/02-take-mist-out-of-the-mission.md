# 02 — Take MiST out of the mission, and the popup with it

Status: ⬜ ready — depends on ticket 01

Skynet stopped using MiST on 2026-08-30 (`fe40c4a`, *refactor: run without MiST*), which wrote
`SkynetIADSUtils` to replace it. The current sources make zero MiST calls. The test mission still
loads `mist_4_5_107.lua`, all 312 KB of it, and pays for it with an error the player sees:

```
ERROR SCRIPTING (Main): Mission script error: [string "l10n/DEFAULT/mist_4_5_107.lua"]:1350: Object doesn't exist
  [C]: in function 'getPosition'
  [string "l10n/DEFAULT/mist_4_5_107.lua"]:1350: in function 'f'
  [string "l10n/DEFAULT/mist_4_5_107.lua"]:1892: in function 'onEvent'
  [string "Scripts/World/EventHandlers.lua"]:13
```

Loading MiST installs MiST's own world event handler. On a `DEAD` event for an object MiST has no
record of, it tries to match it to a static by position and calls `Object.getPosition` on something
that is already gone. The suites that destroy objects — `test-skynet-iads.lua` (5
`trigger.action.explosion`) and `test-skynet-iads-abstract-radar-element.lua` (6) — are what sets it
off. DCS puts that on screen.

## What to build

Once ticket 01 has replaced the 2023 artifact with one that calls no MiST, the only MiST left in the
mission is the harness's own, and it is five calls with replacements that already exist:

| call | file | replacement |
|---|---|---|
| `mist.utils.round` | `test-skynet-iads-abstract-radar-element.lua`, `test-skynet-iads-red-sam-sites-and-ew-radars.lua` | `SkynetIADSUtils.round` |
| `mist.utils.get2DDist` | `test-skynet-iads-abstract-radar-element.lua` | `SkynetIADSUtils.get2DDist` |
| `mist.random` | `test-skynet-iads-abstract-radar-element.lua` | `SkynetIADSUtils.random` |
| `mist.scheduleFunction` | `skynet-unit-test-iads-setup.lua` | `SkynetIADSUtils.scheduleFunction` |
| `mist.removeFunction` | `skynet-unit-tests.lua` | `SkynetIADSUtils.removeFunction` |

Then remove `mist_4_5_107.lua` from the archive with
`build-tools/miz-suite.py remove mist_4_5_107.lua`, which takes its `mapResource` key
(`ResKey_Action_250`), its `a_do_script_file` call and its `trigrules` entry with it.

## Watch out for

**`skynet-unit-tests.lua` ends with a MiST leak check**, and it is not a like-for-like swap:

```lua
local i = 0
while i < 10000 do
    local id = mist.removeFunction(i)
    ...
```

It walks MiST's scheduler by integer id looking for tasks the IADS left behind, and writes
`WARNING: IADS left over Tasks` when it finds one — which it did on the 2026-09-20 run. Whether
`SkynetIADSUtils.removeFunction` can be walked the same way has to be checked against
`skynet-iads-utils.lua` before the loop is rewritten, and a check that silently stops checking is
worse than none. If it cannot, say so and drop it deliberately.

**`test-skynet-iads-red-sam-sites-and-ew-radars.lua` is one of the files touched**, and it is the one
whose four assertions ticket 03 is about. Changing `mist.utils.round` to `SkynetIADSUtils.round`
there does not change what those assertions expect — check the two are the same function before
assuming it (`SkynetIADSUtils.round` takes an optional precision, `mist.utils.round` does too;
confirm the default behaviour matches at the two call sites).

**The `.miz` is judged in DCS.** The popup is the observable: run the mission and confirm it is gone.

## Definition of done

- No file in `unit-tests/skynet-unit-tests.miz` calls MiST.
- `mist_4_5_107.lua` is out of the archive, and `miz-suite.py check` is clean.
- The mission has been run in DCS and the log carries no `ERROR SCRIPTING` line — no popup.
- The leak check either still works, or is gone on purpose with the reason written down.
