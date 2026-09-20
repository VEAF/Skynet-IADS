do

---IADS Unit Tests
SKYNET_UNIT_TESTS_NUM_EW_SITES_RED = 17
SKYNET_UNIT_TESTS_NUM_SAM_SITES_RED = 17

--factory method used in multiple unit tests
function IADSContactFactory(unitName)
	local contact = Unit.getByName(unitName)
	local radarContact = {}
	radarContact.object = contact
	local iadsContact = SkynetIADSContact:create(radarContact)
	iadsContact:refresh()
	return  iadsContact
end

function createDeadEvent()
	local event = {}
	event.id = world.event.S_EVENT_DEAD
	return event
end


lu.LuaUnit.run()

--Clean up scheduled tasks the unit tests left behind, and report any the IADS itself left.
--SkynetIADSUtils hands out task ids from a counter that starts at 1 and never resets, and
--removeFunction answers whether there was a task under that id -- so walking the integers is
--the same sweep this did through mist.removeFunction, and it stays valid while fewer than
--10000 tasks have ever been scheduled in a run.
--This runs before skynet-unit-test-iads-setup.lua builds the IADS the mission is played with,
--so it cannot disarm that one.
local i = 0
while i < 10000 do
	local id =  SkynetIADSUtils.removeFunction(i)
	i = i + 1
	if id then
		env.info("WARNING: IADS left over Tasks")
	end
end

end