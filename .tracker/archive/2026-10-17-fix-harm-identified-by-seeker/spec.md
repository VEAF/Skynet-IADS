# HARM detection identifies an anti-radiation missile by its seeker

Status: done

Depends on `feat-munition-aware-wake`, which gives a contact its target class and already uses it
for the wake. This spec does the same for HARM detection, and so for HARM defence.

## The problem

`SkynetIADSHARMDetection:evaluateContacts()` takes a contact for a HARM when it flies faster than
800 kt with a flat altitude profile, and a roll on the detecting radars' `harm_detection_chance`
succeeds. The heuristic misfires: it identified an AGM-65D as a HARM, HARM defence shut the EW radar
down for 153 s, and the next three Mavericks were never seen. It also identifies any fast, flat
object — a cruise missile, a fast jet at low level.

The loop also `return`s on the first contact whose ground speed is 0 — a contact seen only once —
which ends the evaluation of every later contact for that cycle.

## What to build

- A contact is a candidate HARM when its target class is `arm` (`desc.guidance == 5`, passive radar
  seeker). The speed and altitude-profile test goes.
- The detection roll stays as it is: per new detecting radar, on `harm_detection_chance`. It is the
  setting that makes a site's crew more or less likely to recognise a HARM.
- The block that resets a HARM to `HARM_UNKNOWN` when its altitude profile has more than two
  segments goes: an anti-radiation missile does not stop being one.
- A contact with ground speed 0 is skipped, not the rest of the list: `informOfHARM` needs a speed
  to compute the time to impact, so such a contact waits for its next sighting.
- `SkynetIADSHARMDetection.HARM_THRESHOLD_SPEED_KTS` goes, and so does `SkynetIADSContact`'s
  altitude profile (`simpleAltitudeProfile`, its update in `refresh`, `getSimpleAltitudeProfile`):
  HARM detection is their only reader.

## Decisions

- **The seeker, not the flight.** The weapon's description says what it is; a speed and a profile
  only suggest it.
- **The roll stays.** Identification becomes exact; recognition stays probabilistic, so
  `harm_detection_chance` keeps its meaning for mission makers.
- **A failed roll still marks the contact `NOT_HARM`** until a new radar sees it, as now.

## Tests to follow

- an `arm` contact is identified when the roll succeeds, and `NOT_HARM` when it fails;
- a fast, flat `missile` contact (a Maverick) is never identified;
- a contact with ground speed 0 earlier in the list does not prevent a later one from being
  evaluated;
- the existing HARM detection tests, updated where they relied on speed and profile;
- the altitude-profile tests in `test_skynet_iads_contact.lua` go with the profile.

## Changelog

A behaviour change for mission makers: HARM defence no longer reacts to fast non-HARM munitions,
and reacts to slow ones.
