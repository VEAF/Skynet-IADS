-- DCS's mission-scripting environment has no module system, and this project's own files are
-- concatenated at build time (see build-tools/listToMerge.txt) rather than required — every
-- class here is a bare global by design. luacheck lints one file at a time, so a name this
-- project defines in one file and reads in another has to be listed below, not just the DCS
-- Scripting Engine's own globals.

std = "lua51"

globals = {
	-- DCS Scripting Engine, and test/lua/dcs-stub.lua's stand-in for it.
	"env",
	"timer",
	"world",
	"coalition",
	"trigger",
	"missionCommands",
	"Unit",
	"Group",
	"Object",
	"Weapon",
	"Controller",
	"AI",
	"land",
	"coord",
	"StaticObject",

	-- This project's own classes and shared state, each a bare global.
	"inheritsFrom",
	"samTypesDB",
	"dcsStub",
	"SkynetIADS",
	"SkynetIADSUtils",
	"SkynetIADSLogger",
	"SkynetIADSContact",
	"SkynetIADSTableDelegator",
	"SkynetIADSHARMDetection",
	"SkynetIADSJammer",
	"SkynetIADSAbstractDCSObjectWrapper",
	"SkynetIADSAbstractElement",
	"SkynetIADSAbstractRadarElement",
	"SkynetIADSAWACSRadar",
	"SkynetIADSCommandCenter",
	"SkynetIADSEWRadar",
	"SkynetIADSSAMSearchRadar",
	"SkynetIADSSamSite",
	"SkynetIADSSAMTrackingRadar",
	"SkynetIADSSAMLauncher",
	"SkynetMooseA2ADispatcherConnector",
}

-- Every test file (and the highdigitsams data file) also defines its own bare globals at the
-- top level of the chunk — one luaunit suite table per file, plus `luaunit` itself. None of
-- those are read outside the file that sets them, so they are allowed here rather than
-- listed by name above: only *reading* a name that is neither declared nor set anywhere
-- should fail.
allow_defined_top = true

-- Every method here takes `self` because that is how `function Class:method(...)` reads, not
-- because the method needs it — most don't. Warning on that would be noise on every file.
self = false

-- 631, line too long: several lines predate this tool by years and run well past any
-- reasonable width (one is 285 characters). Rewrapping them is out of scope for adding the
-- linter; stylua's own column_width already keeps anything it reformats in check.
ignore = { "631" }

exclude_files = {
	"test/lua/luaunit.lua", -- vendored upstream, unmodified
}
