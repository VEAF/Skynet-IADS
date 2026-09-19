# 04 — one `jam()` per radar, where one per site is meant

Status: ✅ done

```lua
for l = 1, #radars do
    local radar = radars[l]
    distance = self:getDistanceNMToRadarUnit(radar)
    if self:isKnownRadarEmitter(natoName) and self:hasLineOfSightToRadar(radar) and distance <= self.maximumEffectiveDistanceNM then
        ...
        samSite:jam(self:getSuccessProbability(distance, natoName))
    end
end
```

`jam()` is called once per visible radar, and each call takes its own `math.random(1, 100)` and
writes the site's ROE. They overwrite each other, so the last radar in the list decides.

**Measured first, because the obvious reading overstates it.** A SA-2 has 2 radars in
`getRadars()`, a SA-6 has 1. The radars of one group sit tens of metres apart, so their distances —
and therefore their probabilities — are identical to the decimal. Statistically the site is rolled
once, not N times. This is redundancy, not a behaviour defect, and the ticket exists because it is
cheap to make the code say what it does, not because a mission is misbehaving.

What it does cost: one redundant `setOption` per extra radar every ten seconds per jammed site, and
— with `jammerProbability` on — one duplicate log line per extra radar per cycle.

## What to build

Decide the site once per cycle, then jam it once. The loop over radars becomes what it should have
been: a search for whether the site is jammable at all, and at what distance.

The distance to use is the **nearest visible radar**, not the last one in the list: it is the one a
jammer would be working against, and taking the nearest keeps the choice defensible rather than
incidental. Since the difference within a group is fractions of a nautical mile, no current
behaviour changes measurably — but the rule stops being "whatever order `getRadars()` happened to
return".

Ticket 01 needs the same information, so write this one first if the two are done in sequence: the
set of sites jammed this cycle falls out of it.

## Watch out for

`getRadars()` concatenates search radars then tracking radars. Nothing else in the project depends
on its order, but do not reorder it to make this easier.

A site where no radar is visible must end the cycle **not jammed**, and ticket 01 then releases it.

## Definition of done

- One `jam()` call per site per cycle, asserted by a test that counts them on a site with more than
  one radar.
- The distance passed is the nearest visible radar's.
- No change to whether a given site ends up jammed, at equal random rolls.
