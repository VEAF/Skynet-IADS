# 03 — `addRadioMenu()` issues its menu twice

Status: ✅ done

```lua
function SkynetIADS:addRadioMenu()
    self.radioMenu = missionCommands.addSubMenu("SKYNET IADS " .. self:getCoalitionString())
    -- four addCommand calls
end
```

Nothing checks whether the menu already exists. A second call re-issues the submenu and all four
commands.

The half that needs no simulator to see:

```lua
function SkynetIADS:removeRadioMenu()
    missionCommands.removeItem(self.radioMenu)
end
```

`self.radioMenu` is overwritten on every call, so after two calls it names only the last menu. The
first is referenced nowhere and `removeRadioMenu()` can no longer take it away — an orphan for the
rest of the mission.

What DCS shows a player after two calls is **not established**: two submenus built with the same
name carry the same path, and nobody has looked. That is why this ticket is a guard and not a
redesign.

## What to build

`addRadioMenu()` returns immediately when `self.radioMenu` is already set. `removeRadioMenu()` clears
the field after removing, so add-remove-add works.

That is the whole change. It makes the second call harmless without depending on what DCS does with
duplicate paths, which is the question nobody can answer from here.

## Watch out for

`testAddRadioMenuTwiceBuildsTheWholeMenuAgain` in `test/lua/test_skynet_iads.lua` pins today's behaviour
and is marked `PINS A DEFECT` — it is the last characterisation test left in that file. Update it to
assert the guard and remove the note, the way `FIX-SETUP-WARNINGS-AND-LOG-NOISE` did with its four.
The file header mentions it by name; that sentence goes too.

`SkynetIADSJammer:addRadioMenu()` is a different method on a different class, with a `--TODO: Remove
Menu when emitter dies` above it. Out of scope: it is the jammer's own F10 menu, not the network's,
and the TODO is a separate question.

## Definition of done

- A second `addRadioMenu()` issues nothing.
- `removeRadioMenu()` then `addRadioMenu()` issues the menu again.
- The characterisation test asserts the guard, and no longer says the behaviour is pinned rather
  than endorsed.
