# 01 — the silence that outlives the jammer

Status: ⬜ ready

A jammed site is put on `WEAPON_HOLD` by `SkynetIADSAbstractRadarElement:jam()`. Nothing ever takes
it off again except the next `jam()` whose roll fails, or a `goLive()` on a site that was dark.

So the moment `runCycle` stops reaching a site, the site keeps the last state it was given. Three
ways that happens, all ordinary:

- the emitter is destroyed — `runCycle` calls `masterArmSafe()` and returns;
- the jammer flies beyond `maximumEffectiveDistanceNM`;
- the jammer loses line of sight to every radar of the site.

On a site under network control the silence ends at the next `goLive()`. On an **autonomous** site
it never ends.

## What to build

**The jammer remembers what it is holding, and releases it.** Decided on 2026-09-19, after weighing
it against having the site count its jammers: keeping the state on the jammer is local to one class
and needs no protocol between two. The cost is one cycle — ten seconds — during which a site held by
*two* jammers can be released by the one that stops before the other takes it back. That is
acceptable; two jammers on one battery is rare, and the window closes by itself.

Shape:

- the jammer keeps the set of sites it jammed on the previous cycle;
- at the end of a cycle, any site in that set which was **not** jammed this time is released —
  `WEAPON_FREE`, the same call `jam()` already makes when its roll fails;
- `masterArmSafe()` releases everything it holds, so a destroyed emitter and a mission calling
  *Master Arm Off* from the F10 menu behave the same way.

Release through a method on the radar element rather than reaching into its controller from the
jammer: `jam()` owns that option today and should keep owning it.

## Watch out for

**Do not release a site the jammer never held.** The set has to be what this jammer actually jammed,
not every site it looked at, or a jammer would hand `WEAPON_FREE` to batteries that another part of
Skynet had deliberately set otherwise.

**A destroyed site.** `jam()` already guards on `isDestroyed()`; the release has to do the same, or
it calls `getController()` on a dead group.

**`getActiveSAMSites()` changes between cycles.** A site that goes dark leaves the list, so the
release cannot be driven off the current list — it has to be driven off what was held.

## Definition of done

- A test kills the emitter after a successful jam and asserts the site is back on `WEAPON_FREE`.
- A test flies the jammer out of range and asserts the same.
- A test takes line of sight away and asserts the same.
- A test asserts an autonomous site — the case where the silence used to be permanent — is released.
- `masterArmSafe()` releases what it holds.
