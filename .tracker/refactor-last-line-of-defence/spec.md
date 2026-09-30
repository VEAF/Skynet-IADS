# The last line of defence in its own file, and reported contacts on the site

Status: in-progress

## The problem

The last line of defence is bolted onto `SkynetIADS`: its four settings, `getHostileAirUnits`,
`isSiteEligibleForLastLineOfDefence` and `evaluateLastLineOfDefence` live in `skynet-iads.lua`.
`SkynetIADSHARMDetection` is the model for an evaluator the cycle calls once: its own file,
`create(iads)`, one call from `evaluateContacts`.

`SkynetIADS:reportContact` holds logic that is the site's — go-live constraints, `goLive()`, the
time of the report — while the other way a contact reaches a site, `informOfContact`, lives on the
site.

The comment on `reportContact` names one consumer of the artifact, which ships to every consumer.

## What to build

No behaviour change. The suite passes with only the test plumbing below touched.

### The module

`skynet-iads-source/skynet-iads-last-line-of-defence.lua`, class `SkynetIADSLastLineOfDefence`:

- `create(iads)`, created in `SkynetIADS:create` beside `harmDetection`;
- the four settings, with their defaults;
- `getHostileAirUnits()` and `evaluate(samSites)`, moved as they are;
- the explanatory block above `setLastLineOfDefence` in `skynet-iads.lua` becomes the file's header.

`evaluateContacts` calls `self.lastLineOfDefence:evaluate(samSites)`. The file goes into
`build-tools/listToMerge.txt` beside `skynet-iads-harm-detection.lua`: nothing in it runs at load
time.

### The eligibility check on the site

`isSiteEligibleForLastLineOfDefence(samSite)` has one caller and asks only about the site's own
state. It becomes a method of `SkynetIADSSamSite`.

### Reported contacts on the site

`SkynetIADSSamSite:informOfReportedContact(contact)`, next to `informOfContact(contact)`: the two
ways a contact reaches a site, the detected and the reported.

```lua
function SkynetIADS:reportContact(dcsUnit, samSite)
	if dcsUnit == nil or samSite == nil or dcsUnit:isExist() == false then
		return false
	end
	return samSite:informOfReportedContact(SkynetIADSContact:create({ object = dcsUnit }, samSite))
end

function SkynetIADSSamSite:informOfReportedContact(contact)
	if self:areGoLiveConstraintsSatisfied(contact) == false then
		return false
	end
	self:goLive()
	if self:isActive() == false then
		return false
	end
	self.lastReportedContactTime = timer.getTime()
	return true
end
```

`markContactReported()` is folded into it: it had that one caller.

### Comments

- `SkynetIADS:reportContact` — a public entry point: external code can wake a site directly rather
  than writing into `targetsInRange` every cycle. Nothing about its callers.
- `SkynetIADSSamSite:informOfReportedContact` — the firing-envelope paragraph moves here from
  `reportContact`: unlike `informOfContact()` it does not require the target inside the firing
  envelope, and the go-live constraints and `goLive()`'s guards still hold.
- `test_skynet_iads_harm_silence_cleanup.lua:105` and `test_skynet_iads_last_line_of_defence.lua`'s
  `testReportContactIsAPublicEntryPoint` name a consumer; they say "external code" instead.

### Vocabulary — its own commit

- `CONTEXT.md`, in *A SAM site cannot see for itself*, after the sentence on the last line of
  defence:

  > Two words keep the routes apart. A contact is **detected** when a DCS radar sees it — an EWR's,
  > or a SAM site's own once it is live. It is **reported** when something tells the network about
  > it with no radar involved: the last line of defence, or a script calling
  > `SkynetIADS:reportContact`.

- `documentation/api.en.md`, *Act as EW radar*: "Contacts the SAM site sees are reported to the
  IADS" becomes "Contacts the SAM site detects are passed to the IADS". The French twin already says
  `détecte … transmis`.

### Changelog

One line under `### Changed`: the last line of defence moved to its own file and reported contacts
to the site, with no change in behaviour.

## Decisions

- **The setters and getters on `SkynetIADS` stay, unchanged**, delegating — validation and the
  radius clearing included. The setters are the documented API and mission scripts call them;
  trimming them is not worth the change.
- **`reportContact` stays on `SkynetIADS`** with its signature and return value; the last line of
  defence stops at the first aircraft that wakes a site on that return value.
- **`informOfReportedContact` takes a contact**, like `informOfContact`, not a DCS unit.
- **`hasFreshReportedContact` stays on the site.** Persistence applies to any reported contact.
- **The drawn radius stays on the site.** It could live in the module, keyed by site; the site is
  simpler, and the setter already clears it there.

## Tests to follow

- `test_skynet_iads_last_line_of_defence.lua` stubs `iads:getHostileAirUnits`; the stub moves to the
  module.
- `dcs-stub.lua` names `SkynetIADS:getHostileAirUnits()` in two comments.

## Out of scope

- How coverage is built. A 2D distance against a radar's range, with no horizon or terrain, puts
  sites under network control that no radar actually covers. Worth improving for its own sake; it
  does not replace a sensor near the site, because coverage is per site and detection is per
  aircraft and altitude.
- The last line of defence sees through terrain: `coalition.getGroups` hands every airborne hostile,
  whatever lies between. The drawn radius keeps it from being exploited; a trade-off, not a defect.
