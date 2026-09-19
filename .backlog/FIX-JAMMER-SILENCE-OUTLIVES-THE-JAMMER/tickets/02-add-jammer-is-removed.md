# 02 — `addJammer()` cannot be called, and is removed

Status: ⬜ ready

```lua
function SkynetIADS:addJammer(jammer)
    table.insert(self.jammers, jammer)
end
```

`self.jammers` is never initialised in `SkynetIADS:create()`, so this raises *table expected, got
nil* on the first call. Since it would be called from a mission's setup script, the whole setup
script stops there.

And no other line in the project ever reads `self.jammers`. Initialising the table would turn a
crash into a call that succeeds and does nothing, which is worse: the mission maker would believe
the jammer was registered.

The path that works is the documented one, and it does not go through this method:

```lua
jammer = SkynetIADSJammer:create(Unit.getByName("F-4 AI"), redIADS)
```

## What to build

**Remove it**, and say so in the source where it used to be. David's call, 2026-09-19.

The comment matters more than usual here: this is public surface of a script other missions load, so
someone will eventually search for `addJammer` and find nothing. The comment has to answer them —
what it was, why it could never have worked, and what to call instead. Keep it to a few lines; it is
a signpost, not an essay.

Removal is safe to assert rather than assume: it has raised on every call since it was written, so
no mission can be relying on it.

## Watch out for

`test/lua/README.md` counts `SkynetIADS:addJammer()` among the deliberately uncovered lines, with an
explanation. That entry goes with the method.

`CHORE-TEST-COVERAGE-FLOOR` ticket 06 mentions it twice — that is a closed lot's record of what was
true then, and stays as it is.

Removing a line that no test covers **raises** the coverage percentage. Check the figure after, and
raise the floor in the same pull request if it clears the next whole point.

## Definition of done

- `SkynetIADS:addJammer()` is gone.
- A comment in its place says what it was, why it never worked, and what to use instead.
- `test/lua/README.md` no longer lists it as uncovered.
