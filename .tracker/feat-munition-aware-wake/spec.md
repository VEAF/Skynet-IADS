# A site wakes only for what it can engage, and never for its own side

Status: in-progress

## The problem

The network hands every contact to every SAM site under EW coverage, and a site goes live for any
contact inside its go-live range. Since bombs and missiles were deliberately let through, this
means:

- **Any site wakes for any bomb or missile.** The only capability check is for HARMs. Of the
  twenty-four SAM types Skynet supports, four engage bombs in DCS and ten engage air-to-ground
  missiles; the others wake, emit, and gain nothing.
- **A HARM wakes sites that cannot engage it.** The wake's HARM check relies on HARM detection's
  heuristic — speed, flat profile, a detection roll. Until a HARM is identified (first sighting,
  speed 0) or if the roll fails, it wakes every site in range, the emitter it is guiding on
  included. (The
  heuristic's other failure, a Maverick taken for a HARM by HARM defence, is
  `fix-harm-identified-by-seeker`.)
- **A site is held live by anything its radar sees.** `goDark()` refuses while the site's own radar
  detects any contact in range, so a passing bomb keeps up a site that cannot engage it.
- **No coalition check.** Nothing between the DCS radar and the site checks a contact's coalition.
  DCS radars report no friendly object today, aircraft or weapon; the network relies on it without
  saying so.

## What to build

### Coalition filter, at the source

`SkynetIADSAbstractRadarElement:getDetectedTargets()` drops any detected object whose coalition is
the IADS's own, before a contact is built. Neutral objects are kept, as the last line of defence
keeps them. Aircraft and weapons alike.

`getCoalition()` raises "Weapon doesn't exist" on a weapon that has ended. An object whose coalition
cannot be read is dropped: a contact could not be built from it anyway.

Every consumer is downstream of it: the merge into `self.contacts`, the wake loop, HARM detection,
the logger. AWACS go through the same method.

### The target class of a contact

`SkynetIADSContact:getTargetClass()` answers one of the following, read from the DCS object's
category and `getDesc()`. The rows are tested in order; the first that matches wins:

| class | contact |
|---|---|
| `aircraft` | a `UNIT` whose `desc.category` is `Unit.Category.AIRPLANE` or `HELICOPTER` |
| `bomb` | a `WEAPON` whose `desc.category` is `Weapon.Category.BOMB` |
| `nil` | a `WEAPON` of category `MISSILE` whose `desc.missileCategory` is `Weapon.MissileCategory.AAM` or `SAM` |
| `arm` | a `WEAPON` of category `MISSILE` whose `desc.guidance` is `Weapon.GuidanceType.RADAR_PASSIVE` |
| `missile` | any other `WEAPON` of category `MISSILE` |
| `nil` | anything else: ground units, ships, structures, shells, rockets, torpedoes |

The DCS enums are named, never their values (`RADAR_PASSIVE` is 5, `AAM` 1, `SAM` 2), and the
standalone stub gains the two tables.

The class depends only on the DCS object: computed once, when the contact is built. A missile whose
`missileCategory` cannot be read counts as `missile`. DCS describes the AGM-154 JSOW as a missile, so
it is one here too.

The class names are constants on `SkynetIADSContact`, prefixed `CLASS_`, distinct from the existing
HARM-state constants.

The wake does not read the HARM state. HARM detection keeps its heuristic identification, which
still drives HARM defence: a contact can be `arm` before HARM detection identifies it, and a
Maverick it takes for a HARM is still `missile` here.

### What a site can engage

`SkynetIADSAbstractRadarElement:canEngage(contact)`:

- `aircraft` → true;
- `arm` → `getCanEngageHARM()`;
- `bomb` → `getCanEngageBomb()`;
- `missile` → `getCanEngageMissile()`;
- `nil` → false.

### Supported-types data

Two booleans beside `can_engage_harm`, in the same form:

```lua
["can_engage_harm"] = true,
["can_engage_bomb"] = true,
["can_engage_missile"] = true,
```

A field left out is false.

| type | `can_engage_bomb` | `can_engage_missile` | `can_engage_harm` |
|---|---|---|---|
| Tor M2 | true | true | true |
| Pantsir S1 | true | true | true |
| Iris-T SLM | true | true | true |
| Phalanx | true | true | true |
| S-300 | | true | true |
| Patriot | | true | true |
| NASAMS | | true | true |
| Tor | | true | true |
| HQ-7 | | true | **true (new)** |
| Roland ADS | | true | |
| every other type | | | unchanged |

What DCS 2.9.30 does, measured with the site immortal and the launcher invisible:

| type | Mk-82 | GBU-38 | AGM-65D | AGM-154C | AGM-84H | AGM-88C |
|---|---|---|---|---|---|---|
| Tor M2, Pantsir S1, Iris-T SLM, Phalanx | yes | yes | yes | yes | yes | yes |
| S-300, Patriot, NASAMS, Tor, HQ-7 | no | no | yes | yes | yes | yes |
| Roland ADS | no | no | yes | no | yes | 1 shot at 5 HARMs, none stopped |
| Osa, Rapier, 2S6 Tunguska, Gepard | no | no | no | no | in its last seconds only | no |
| the ten others | no | no | no | no | no | no |

The High Digit SAMs table is unchanged: not measured.

### Mission-maker API

On `SkynetIADSAbstractRadarElement`, chainable like the existing setters:

- `setCanEngageBomb(state)` / `getCanEngageBomb()`;
- `setCanEngageMissile(state)` / `getCanEngageMissile()`.

They behave as `setCanEngageHARM` does: setting one true also turns `ENGAGE_AIR_WEAPONS` on.
`setCanEngageAirWeapons(false)` sets both false, as it does `canEngageHARM`;
`setCanEngageAirWeapons(true)` restores them from the database.

Setting one true on a site whose air weapons are off turns air weapons on first, then sets the flag.
`setCanEngageHARM` does it the other way round today: `setCanEngageAirWeapons(true)` restores the
database value over the flag just set, so `setCanEngageHARM(true)` on such a site ends false for a
type the database says cannot engage HARMs. All three setters take the corrected order.

### The wake

In `evaluateContacts`, the category filter of the wake loop becomes `getTargetClass() ~= nil`. The
comment block above it goes with it: it describes the filter being replaced, and its "Note 1" is
what this work does.

`SkynetIADSSamSite:informOfContact(contact)` goes live when the go-live constraints hold,
`canEngage(contact)`, and `isTargetInRange(contact)` — the site's go-live range, the same for every
class.

`informOfContact`'s own HARM test — `isIdentifiedAsHARM()` against `getCanEngageHARM()` — goes:
`canEngage` covers it, with the `arm` class read from the seeker. This concerns the wake only. HARM
detection, the HARM state and HARM defence are untouched; making HARM detection use the seeker too
is `fix-harm-identified-by-seeker`.

`getDetectedTargets()` keeps its class-blind range filter. It decides what a radar reports to the
network; making it class-aware would stop EW radars from reporting munitions.

### Going dark

In `goDark()`, both tests on `#self:getDetectedTargets()` count only the contacts the element
`canEngage`. A site whose radar sees only what it cannot engage goes dark.

For an EW radar, `canEngage` is false for every munition; this changes nothing in practice: an EW
radar goes dark only through HARM defence, whose clause does not depend on detected targets.

### Changelog

Mission behaviour changes, so the next release is at least a minor. One entry, worded for a mission
maker: which sites wake for which munitions, the HQ-7 now engaging HARMs, the coalition filter, the
new setters, and `setCanEngageHARM(true)` now holding on a site whose air weapons were off.

### Documentation

Both languages:

- `api.md`: the two setters, beside `setCanEngageHARM`, and a paragraph on what wakes a site, by
  class.
- `faq.md`: the answer "Which SAM systems can engage HARMS?", a list from 2022, becomes the
  per-type table of bombs, missiles and HARMs, naming the three database fields for whoever edits
  the database. Its anchor stays.

## Decisions

- **Classes from the weapon's description, not from behaviour.** `category`, `missileCategory` and
  `guidance` are fixed per weapon type and read at once. The HARM heuristic needs several sightings
  and a roll, and misfires.
- **`guidance` identifies anti-radiation missiles and nothing else.** It is the seeker type: laser
  and TV Mavericks differ, and so do two Hellfires that the same sites treat alike.
- **Capability per class, as booleans: no `RCS` threshold.** Which types engage a missile lines up
  with the weapon's `RCS`, but the flight profile was not ruled out — the Hellfire, the smallest, is
  also fired from closest. A missile a site cannot engage is rarely alone: its launcher is usually
  in the same envelope and wakes the site anyway.
- **`can_engage_harm` means reliable, not "ever engaged".** It also keeps a site live under HARM
  attack (`shallIgnoreHARMShutdown`), so a false "true" costs the site. The HQ-7 shot its HARM down;
  the Roland ADS fired once at five and stopped none.
- **Osa, Rapier, 2S6 Tunguska and Gepard engage no munition.** They fired at the AGM-84H only in its
  terminal climb, and stopped none reliably.
- **Munitions use the site's go-live range.** The kill zone at 100 % woke every capable type in time;
  the search range never did better. A mission maker who changes a site's go-live range changes it
  for everything the site engages.
- **One boolean per class, in the form of `can_engage_harm`.** A set of classes was turned down: a
  second shape beside the existing field, more verbose in every entry, and folding HARM into it
  would change a public API for nothing. A new class — a split of `missile`, or rockets — is one
  more field, setter and line in the classifier.
- **One `bomb` class, guided or not.** Every type treated the Mk-82 and the GBU-38 alike.
- **The Roland ADS wakes for a JSOW it does not engage.** Accepted: one class for every missile that
  is not an ARM, rather than a split no other type needs.
- **Coalition filter at the source, not at the wake.** It protects every consumer, HARM detection
  included. DCS does not report friendly objects today: this is protection, not a fix.
- **Neutral contacts kept**, as the last line of defence keeps them.
- **Air-to-air and surface-to-air missiles are excluded.** `missileCategory` separates them reliably.
  Whether a site should wake for an air-to-air missile is open in `IDEAS.md`.
- **Reporting stays class-blind; waking and staying live are class-aware.**

## Tests to follow

Standalone suite (`test/lua/`), written first:

- a friendly aircraft and a friendly weapon are not returned by `getDetectedTargets`; an enemy and a
  neutral one are; an object whose `getCoalition()` raises is dropped;
- `getTargetClass` for each row of the class table, including a missile without `missileCategory`,
  a JSOW-like missile, and a passive-radar missile whose `missileCategory` is air-to-air;
- `canEngage` per class, for a type with and without each field, and after each setter;
- `setCanEngageBomb(true)` and `setCanEngageMissile(true)` turn `ENGAGE_AIR_WEAPONS` on;
- each of the three setters, set true on a site whose air weapons are off and whose database entry
  is false, holds true — with the real `setCanEngageAirWeapons`, not a mock;
- `setCanEngageAirWeapons(false)` then `(true)` clears and restores both;
- a bomb wakes a bomb-capable site and not an incapable one;
- an anti-radiation missile wakes a HARM-capable site and not another, whatever its HARM state;
- an aircraft wakes every site, as before;
- `goDark` with only unengageable contacts goes dark; with one engageable contact, stays;
- `testABatteryIsNotWokenByAShellOrARocket` in `test_skynet_iads.lua` rewritten for classes.

## Out of scope

- HARM detection's identification: `fix-harm-identified-by-seeker`.
- DCS's own "Evasion of ARM": `fix-dcs-arm-evasion-off`.
- Rockets and shells as target classes. They stay filtered: the most numerous contacts, in a loop of
  contacts × sites, and no system is measured engaging them.
- The High Digit SAMs: not measured.
- `SkynetIADS:reportContact`: what a caller reports is taken as it is, class-blind.
