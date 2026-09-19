# 01 — Last line of defense: a dark site wakes on close proximity

Status: ⬜ ready

## What to build

In `SkynetIADS.evaluateContacts` (`skynet-iads-source/skynet-iads.lua`), after the EWR pass and
before the `targetCycleUpdateEnd` loop, every usable SAM site that no EWR has already triggered this
cycle gets a proximity check.

- **Enumerate hostile air units once per cycle**, shared by every site — never inside the per-site
  loop. A mission carrying sixty batteries would otherwise sweep sixty times every five seconds.
- **The radius is drawn once per site**, when the element is built, and kept for the mission. The
  randomness is there so a pilot cannot learn the exact distance; redrawn each cycle it only makes
  the site blink.
- **Distance is 2D**, like everything else in this project.
- **The kill-zone test is bypassed.** `informOfContact` requires the target to be inside the firing
  envelope; with a 10–15 km radius a Shilka would never wake, and short-range pieces are exactly
  what a last line of defense is for. A site lights up because it hears the aircraft go over, not
  because it can hit it.

### Persistence

The site stays lit **45 s** after the last pass. Without it, `targetCycleUpdateEnd` sends it dark
five seconds after the aircraft leaves the radius, so a fast pass lights the site for one cycle and
a racetrack makes it blink.

Implementation: a timestamp per site, set on each proximity wake, and a guard in
`SkynetIADSSamSite:targetCycleUpdateEnd` (`skynet-iads-source/skynet-iads-sam-site.lua`) that
refuses to go dark while it is still fresh.

### Two guards that must not be lost

- **A site silenced to evade a HARM must not wake on proximity.** `goLive()` already refuses while
  `harmSilenceID` is set, so the behaviour should be correct as written — but it becomes an explicit
  test, because the last line of defense silently cancelling HARM evasion would be the worst
  regression this feature could cause.
- **A site out of ammunition must not wake either.** `goLive()` guards on `hasRemainingAmmo()`. Same
  treatment: a test, not an assumption.

### The public entry point

Expose the wake-up as a **public API of this project** — something like
`SkynetIADS:reportContact(dcsUnit, samSite)` — and make this feature its first caller. A Skynet
contact builds from any DCS unit (`SkynetIADSContact:create({ object = unit }, source)`), so the
cost is small.

It exists because VEAF's planned spotter network has to wake a site "as if an EWR had seen the
aircraft" from **outside** Skynet. Without a public door, that code would write into
`targetsInRange` and friends on every cycle. Document it in the README alongside the rest of the
public interface.

## Settings

On the IADS instance, with setters: whether the last line of defense is active, and the radius
bounds. Default **on**. Global to both coalitions for now.

VEAF surfaces them through `mission.yaml`; keep the names aligned with what that side will use —
coordinate with `FIX-SKYNET-HELPER-AND-VENDORING` in VEAF-Mission-Creation-Tools.

## Definition of done

- A site whose EWRs report nothing goes live when a hostile aircraft enters its drawn radius.
- It falls silent 45 s after the last pass, on the normal cycle, with no special case.
- The drawn radius does not change between two cycles.
- Tests both ways: wakes on proximity; does **not** wake outside the radius, for a friendly
  aircraft, when the setting is off, while defending against a HARM, or without ammunition.
- `lua5.1 test/lua/run.lua` green.
