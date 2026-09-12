--- Standalone regression test for 3a94937: a live SAM site must stay live
--- while its target remains under EW radar coverage. Mirrors
--- unit-tests/test-skynet-iads.lua's
--- testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage, built on
--- dcs-fixtures instead of the skynet-unit-tests.miz. SkynetIADS and
--- SkynetIADSEWRadar are not otherwise ported to test/lua yet (see
--- test/lua/README.md) — this file only exercises the one code path the fix
--- touches (SkynetIADS.evaluateContacts), not the whole iads/early-warning-
--- radar suites.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

TestSkynetIADS = {}

function TestSkynetIADS:setUp()
  dcsStub.reset()
end

--a SAM site that is already live must stay live while the target is still under EW coverage.
--targetCycleUpdateStart() clears targetsInRange on every cycle, so if evaluateContacts() skips
--sites that are already active, nothing sets the flag again and targetCycleUpdateEnd() sends them
--dark on the next cycle. In game that reads as a site raising its launchers and standing down
--every few seconds without ever firing. Regression test for 3a94937.
function TestSkynetIADS:testSAMSiteStaysLiveWhileTargetRemainsUnderEWCoverage()
  local iads = SkynetIADS:create()

  F.earlyWarningRadarUnit("EW-west23")
  local ewRadar = iads:addEarlyWarningRadar("EW-west23")

  -- EW-west23 sits at the origin with a 120 km detection range (RADAR_RANGE_M in
  -- dcs-fixtures.lua); the SA-2 group's units sit at x=1..4 m. A target at
  -- x=10000 m / y=2000 m altitude is ~10 km out — well inside both the EW radar's
  -- 120 km range and the SA-2 launcher's 40 km rangeMaxAltMin (real SA-2 data in
  -- skynet-iads-source/syknet-iads-sam-launcher.lua, reused by dcs-fixtures.lua's
  -- launcherAmmo for the search radar).
  dcsStub.makeUnit({
    name = "test-in-firing-range-of-sa-2",
    type = "F-16C",
    pos = { x = 10000, y = 2000, z = 0 },
    desc = { category = Unit.Category.AIRPLANE },
  })

  function ewRadar:getDetectedTargets()
    return { F.iadsContact("test-in-firing-range-of-sa-2") }
  end

  F.samGroup("SA-2", "SAM-SA-2")
  local samSite = iads:addSAMSite("SAM-SA-2")

  function samSite:getDetectedTargets()
    return {}
  end

  samSite:goDark()
  luaunit.assertEquals(samSite:isActive(), false) -- addSAMSite() leaves it dark; cycle 1 must be what brings it live
  iads:activate()

  iads:evaluateContacts()
  luaunit.assertEquals(samSite:isActive(), true)

  --the target has not moved and the EW radar still sees it, so a second cycle must not
  --switch the site off
  iads:evaluateContacts()
  luaunit.assertEquals(samSite:isActive(), true)

  --and a third, to show it is a steady state and not a one-cycle grace period
  iads:evaluateContacts()
  luaunit.assertEquals(samSite:isActive(), true)

  iads:deactivate()
end

os.exit(luaunit.LuaUnit.run())
