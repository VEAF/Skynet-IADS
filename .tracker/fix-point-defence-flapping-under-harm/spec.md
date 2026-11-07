# A site protected by a point defence flaps under a HARM

Status: done

## The problem

A SAM site whose point defence can take the inbound HARM is meant to stay as it was while the point
defence engages: `shallIgnoreHARMShutdown()` answers true, and `informOfHARM` wakes the point
defence through `pointDefencesGoLive()`. In DCS, the site instead goes dark for the whole time the
HARM is in flight, its radar coming on for an instant at each contact cycle; its point defence does
the opposite, live with a dark instant at each cycle.

Seen in the in-sim scenario `harm-point-defence` (`test/insim/scenarios/`), on `insim-ca-main`: an
SA-6 acting as an EW radar, an SA-15 as its point defence, both under a 1L13; one AGM-88C fired by an
invisible, immortal F-16 at the SA-6; HARM detection chance 100 %. It is the setup of the documented
example, an SA-10 acting as EW protected by SA-15s (`documentation/api.en.md`). The scenario fails
with `site` going `{ true, false, true }`; the SA-15 still fires.

## The cause

Coverage is geometry: every radar element is a parent of every SAM site inside its detection range,
whether it acts as EW or not, so the SA-6 and the SA-15, a few hundred metres apart, are each the
other's parent and child. `addPointDefence()` adds no link of its own. `actAsEW` decides whether a
parent counts (`hasValidParentRadar()`), and a change of it is sent down the link:
`setActAsEW()` calls `informChildrenOfStateChange()`, and each child gets
`setToCorrectAutonomousState()` → `resetAutonomousState()` → `goDark()`, even when its autonomy has
not changed.

A point defence goes live by acting as EW, so two paths meet:

1. **The HARM is identified.** `informOfHARM` → `pointDefencesGoLive()` → `SA15:setActAsEW(true)` →
   `informChildrenOfStateChange()` → `goDark()` on the SA-6, a child of the SA-15. The SA-6 acting
   as EW itself does not spare it: `goDark()` does not look at `actAsEW`, and the SA-6 has no
   engageable target and no missile in flight.
2. **Each contact cycle.** `evaluateContacts` calls `goLive()` on every radar acting as EW. The SA-6
   is dark, so `goLive()` runs and calls `pointDefencesStopActingAsEW()` →
   `SA15:setActAsEW(false)` → `informChildrenOfStateChange()` → the SA-6 goes dark again, inside its
   own `goLive()`. Later in the same tick, path 1 wakes the SA-15 again.

A site that is not acting as EW but engaging a target is never sent down path 2, which only the
radars acting as EW go through. Path 1 still reaches it, and only `goDark()`'s own guard holds it
up: an engageable target seen by its radar, or a missile in flight. In `harm-engaging-defended`,
below, the guard holds and the site stays live; it would not in a gap with neither, such as a site
live on a contact the network reported, with no track of its own yet. The flapping itself is seen
only on a protected site acting as EW.

## Decisions

**A point defence defending against a HARM is held live by a latch of its own, not by `actAsEW`.**
`informOfHARM` and HARM silence set it, through `pointDefencesGoLive()`;
`cleanUpOldObjectsIdentifiedAsHARMS()` releases it once the last HARM is gone. That runs in the
protected site's HARM scan, so `goDark()` leaves the scan running while a HARM is remembered, and
the scan stops itself once the last one is gone on a dark site: a site gone dark of its own accord,
for want of a target, would otherwise hold its point defence live until it next went live.
`goDark()` leaves a latched point defence live while it has power and missiles: its target cycle is
one caller, a parent's notification another, and nothing lights it again once dark, as the contact
cycle did for a point defence acting as EW. The point defence never changes its EW role, so nothing
is sent down the coverage links, and `goLive()` no longer has point defences to switch off: both
paths go. What a live point defence detects still reaches the network, as for any live site not
acting as EW.

Turned down:

- **`informChildrenOfStateChange()` corrects a child only when its autonomy has changed**, as
  `updateAutonomousStateIfChanged()` does for the coverage sweep. It would stop path 1, but every
  caller of the notification would change with it, and a point defence would still become a parent
  radar and a member of the EW list for the length of a HARM.
- **`goDark()` leaves a site acting as EW alone.** It does not cover a site engaging a target.
- **A point defence's `setActAsEW()` does not notify its children.** A site acting as EW is a valid
  parent; hiding that change is hiding a real one.

## What to build

- The latch, and point defences moved off `actAsEW`: the protected site stays as it was for the
  whole engagement, its point defence live while the HARM is inbound and dark again once it is gone.
- Standalone tests in `test/lua/` for both paths.
- `harm-point-defence` passes; it asserts the site stays live (`site = { true }`) and is the
  regression test in DCS.
- Two in-sim scenarios for a site that is not acting as EW and cannot engage a HARM, an SA-2 under
  EW coverage, engaging a visible, immortal attacker that fires a HARM at it only once the site has
  fired. Both pass against the script before the fix, and must still pass after it:
  - `harm-engaging-undefended`, no point defence: the site goes dark under the HARM, and comes back
    up once its silence is over.
  - `harm-engaging-defended`, an SA-15 as point defence: the site stays live through the HARM, and
    never goes silent; the point defence goes live, and dark again once the HARM is gone. Whether
    the site fires again meanwhile is the DCS AI's choice, measured and not judged.

  The attacker flies straight at the site from the north, so that the HARM's line does not run on
  to the EW radar west of it, which would take the HARM for one aimed at itself and go silent.

  The attacker is immortal, so the site may run out of missiles, and `goDarkIfOutOfAmmo()` sends it
  dark as a HARM would: a site left without missiles makes the run `invalid`. The attack is a
  helper in `user-lib/`, shared by both.

## Out of scope

- HARM identification itself: `fix-harm-identified-by-seeker`.
