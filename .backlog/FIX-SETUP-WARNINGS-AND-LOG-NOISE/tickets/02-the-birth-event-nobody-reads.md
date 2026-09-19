# 02 — the birth event nobody reads

Status: ✅ done

```lua
function SkynetIADS:onEvent(event)
    if event.id == world.event.S_EVENT_BIRTH then
        env.info("New Object Spawned")
        --	self:addSAMSite(event.initiator:getGroup():getName());
    end
end
```

Three things are wrong with those four lines, and the third is the one that decides the fix.

1. It fires for **every** unit that appears — spawned groups, respawns, and a player taking a slot.
2. It is written through `env.info` with no `SKYNET:` prefix, so it is the one Skynet line that
   cannot be filtered out of a `dcs.log`, or filtered *in*. Two networks means two copies of each.
3. **Nobody can act on it.** It does not name the object, so it is not even a trace. The enrolment
   it was written to support is commented out on the line below.

## What to build

Delete the body of the birth branch, and the commented-out call with it — git history is where an
abandoned idea belongs, not the shipped artifact. `onEvent` keeps its shape: it is still the
registered world event handler, and it is still the obvious place for event work later.

Do **not** replace the line with a gated, prefixed version. A debug setting would have to be off by
default to be bearable, and a line nobody can act on is not worth a setting; if per-object tracing
is ever wanted, it wants the object's name and a reason to exist.

## Two things to decide rather than assume

**Does the handler registration stay?** With the branch gone, `SkynetIADS:onEvent` does nothing at
all, and `SkynetIADS:create()` still calls `world.addEventHandler(iads)` — one dispatch per DCS
event per network, for nothing. Recommendation: **keep it**. Removing the registration is a larger
change to reach for while deleting four lines, and the handler is where the next event feature will
go. Say so in a comment so the next reader does not think it was overlooked.

**Does `SkynetIADSAbstractElement:onEvent` have the same problem?** It does not — it acts on
`S_EVENT_DEAD` and `S_EVENT_SHOT` and writes nothing — but check it rather than take this ticket's
word for it.

## Watch out for

`testABirthEventOnlyWritesALineToTheLog` in `test/lua/test_skynet_iads.lua` pins the current
behaviour and says in its own comment that it does. Rewrite it to assert that a birth event writes
nothing and enrols nothing — the second half is worth keeping, because *enrolling on birth* is the
idea that was commented out and someone may revive it.

## Definition of done

- A birth event writes nothing anywhere.
- The commented-out `addSAMSite` call is gone.
- A test asserts that a birth event writes nothing and enrols nothing.
- If the handler registration stays, a comment says why.
