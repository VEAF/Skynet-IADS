--- Unit tests for skynet-iads-source/skynet-iads-utils.lua — the MiST-free
--- replacement for the ~13 helpers Skynet used to borrow from MiST. Replaces
--- the old test_mist_stub.lua (mist-stub.lua is deleted).
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.load("skynet-iads-utils")

TestSkynetIADSUtils = {}

function TestSkynetIADSUtils:setUp()
	dcsStub.reset()
end

-- ---- arithmetic (was test_mist_stub) --------------------------------

function TestSkynetIADSUtils:test_round()
	luaunit.assertEquals(SkynetIADSUtils.round(5015.0), 5015)
	luaunit.assertEquals(SkynetIADSUtils.round(2.4), 2)
	luaunit.assertEquals(SkynetIADSUtils.round(2.5), 3)
	luaunit.assertEquals(SkynetIADSUtils.round(1.2345, 2), 1.23)
end

function TestSkynetIADSUtils:test_conversions()
	luaunit.assertAlmostEquals(SkynetIADSUtils.toDegree(math.pi), 180, 1e-9)
	luaunit.assertAlmostEquals(SkynetIADSUtils.metersToNM(1852), 1, 1e-9)
	luaunit.assertAlmostEquals(SkynetIADSUtils.metersToFeet(0.3048), 1, 1e-9)
end

function TestSkynetIADSUtils:test_get2DDist_ignores_altitude()
	local a = { x = 0, y = 9999, z = 0 }
	local b = { x = 3, y = 0, z = 4 }
	luaunit.assertAlmostEquals(SkynetIADSUtils.get2DDist(a, b), 5, 1e-9)
end

function TestSkynetIADSUtils:test_get3DDist()
	luaunit.assertAlmostEquals(SkynetIADSUtils.get3DDist({ x = 0, y = 0, z = 0 }, { x = 3, y = 0, z = 4 }), 5, 1e-9)
	luaunit.assertAlmostEquals(SkynetIADSUtils.get3DDist({ x = 0, y = 0, z = 0 }, { x = 0, y = 12, z = 0 }), 12, 1e-9)
end

function TestSkynetIADSUtils:test_random_in_range()
	for _ = 1, 20 do
		local r = SkynetIADSUtils.random(3, 5)
		luaunit.assertEquals(r >= 3 and r <= 5, true)
	end
	luaunit.assertEquals(SkynetIADSUtils.random(1) >= 1, true)
end

-- ---- headings ------------------------------------------------------

function TestSkynetIADSUtils:test_getHeading_raw_wraps_into_0_2pi()
	local u = dcsStub.makeUnit({ heading = math.rad(347) })
	-- rawHeading = true skips the coord-based north correction
	luaunit.assertAlmostEquals(SkynetIADSUtils.getHeading(u, true), math.rad(347), 1e-6)
end

function TestSkynetIADSUtils:test_getHeading_nil_position()
	local nofix = {
		getPosition = function()
			return nil
		end,
	}
	luaunit.assertNil(SkynetIADSUtils.getHeading(nofix))
end

function TestSkynetIADSUtils:test_getNorthCorrection_zero_with_coord_fake()
	luaunit.assertAlmostEquals(SkynetIADSUtils.getNorthCorrection({ x = 100, y = 0, z = 200 }), 0, 1e-6)
end

-- ---- scheduler ---------------------------------------------------

function TestSkynetIADSUtils:test_scheduleFunction_runs_once_via_timer()
	local ran = 0
	SkynetIADSUtils.scheduleFunction(function()
		ran = ran + 1
	end, {}, 1)
	dcsStub.setClock(1)
	dcsStub.fireDueTimers()
	luaunit.assertEquals(ran, 1)
	dcsStub.setClock(100)
	dcsStub.fireDueTimers()
	luaunit.assertEquals(ran, 1) -- one-shot
end

function TestSkynetIADSUtils:test_scheduleFunction_repeats()
	local ran = 0
	SkynetIADSUtils.scheduleFunction(function()
		ran = ran + 1
	end, {}, 1, 10)
	dcsStub.setClock(1)
	dcsStub.fireDueTimers()
	dcsStub.setClock(11)
	dcsStub.fireDueTimers()
	dcsStub.setClock(21)
	dcsStub.fireDueTimers()
	luaunit.assertEquals(ran, 3)
end

function TestSkynetIADSUtils:test_scheduleFunction_clamps_past_start_time()
	-- VEAF #5 / cde577d: a first run asked for a time already past must still
	-- happen, but not before now + MINIMUM_DELAY. Without the clamp the task
	-- would be armed at t=1 and fire immediately at clock 200; the clamp pushes
	-- it to 200 + 0.01, so it must NOT run at clock 200 and MUST run at 200.01.
	local ran = false
	dcsStub.setClock(200)
	SkynetIADSUtils.scheduleFunction(function()
		ran = true
	end, {}, 1) -- start 1s, clock 200
	dcsStub.fireDueTimers()
	luaunit.assertEquals(ran, false) -- clamped to 200.01 — fails here if the clamp regresses
	dcsStub.setClock(200.01)
	dcsStub.fireDueTimers()
	luaunit.assertEquals(ran, true)
end

function TestSkynetIADSUtils:test_repeating_task_that_throws_is_logged_and_keeps_going()
	local calls = 0
	SkynetIADSUtils.scheduleFunction(function()
		calls = calls + 1
		if calls == 1 then
			error("boom")
		end
	end, {}, 1, 10)
	dcsStub.setClock(1)
	dcsStub.fireDueTimers() -- throws, caught
	dcsStub.setClock(11)
	dcsStub.fireDueTimers() -- still scheduled
	luaunit.assertEquals(calls, 2)
	local sawError = false
	for _, e in ipairs(dcsStub.logs) do
		if tostring(e.text):find("boom", 1, true) then
			sawError = true
		end
	end
	luaunit.assertEquals(sawError, true)
end

function TestSkynetIADSUtils:test_removeFunction_returns_boolean()
	local id = SkynetIADSUtils.scheduleFunction(function() end, {}, 1, 10)
	luaunit.assertEquals(SkynetIADSUtils.removeFunction(id), true)
	luaunit.assertEquals(SkynetIADSUtils.removeFunction(id), false)
	luaunit.assertEquals(SkynetIADSUtils.removeFunction(nil), false)
end

os.exit(luaunit.LuaUnit.run())
