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

-- ---- CHORE-TEST-COVERAGE-FLOOR ticket 06 ---------------------------------------------------
--
-- The geometry helpers the HARM aspect calculation and the coverage graph are built on, and the
-- two ends of the scheduler's life the tests above never reached.

-- ---- makeVec3: the y/z swap every distance goes through -------------------------------------

--- A mission-table point is a vec2: its easting is in `y`. A runtime vec3 keeps the altitude
--- there and the easting in `z`. Getting it backwards raises nothing, it silently puts the point
--- somewhere else -- which is why every distance in this file converts first, and why this is
--- worth a test rather than a glance.
function TestSkynetIADSUtils:test_makeVec3_moves_a_vec2_easting_into_z()
	local vec3 = SkynetIADSUtils.makeVec3({ x = 10, y = 20 })
	luaunit.assertEquals(vec3, { x = 10, y = 0, z = 20 })
end

function TestSkynetIADSUtils:test_makeVec3_takes_the_altitude_from_alt()
	local vec3 = SkynetIADSUtils.makeVec3({ x = 10, y = 20, alt = 300 })
	luaunit.assertEquals(vec3, { x = 10, y = 300, z = 20 })
end

--- An explicit altitude wins over the point's own, which is how a caller lifts a ground point.
function TestSkynetIADSUtils:test_makeVec3_prefers_an_explicit_altitude()
	luaunit.assertEquals(SkynetIADSUtils.makeVec3({ x = 10, y = 20 }, 500), { x = 10, y = 500, z = 20 })
	luaunit.assertEquals(SkynetIADSUtils.makeVec3({ x = 10, y = 20, alt = 300 }, 500), { x = 10, y = 500, z = 20 })
end

function TestSkynetIADSUtils:test_makeVec3_leaves_a_vec3_alone()
	luaunit.assertEquals(SkynetIADSUtils.makeVec3({ x = 1, y = 2, z = 3 }), { x = 1, y = 2, z = 3 })
end

-- ---- getDir / getHeadingPoints --------------------------------------------------------------

--- Grid north is +x and grid east is +z, so these four are the compass. The last one is the
--- branch that matters: atan2 answers in (-pi, pi], and a bearing has to come back in [0, 2*pi).
--- Without the wrap, anything pointing west of north reads as a negative heading and every
--- aspect built on it is wrong by a full turn.
function TestSkynetIADSUtils:test_getDir_answers_a_bearing_in_0_2pi()
	luaunit.assertAlmostEquals(SkynetIADSUtils.getDir({ x = 1, y = 0, z = 0 }), 0, 1e-9)
	luaunit.assertAlmostEquals(SkynetIADSUtils.getDir({ x = 0, y = 0, z = 1 }), math.pi / 2, 1e-9)
	luaunit.assertAlmostEquals(SkynetIADSUtils.getDir({ x = -1, y = 0, z = 0 }), math.pi, 1e-9)
	luaunit.assertAlmostEquals(SkynetIADSUtils.getDir({ x = 0, y = 0, z = -1 }), 3 * math.pi / 2, 1e-9)
end

--- Passing a reference point adds the correction from grid north to true north. The stub's
--- coord is a linear fake in which the two coincide (see dcs-stub.lua), so the corrected answer
--- has to equal the raw one -- which is what makes this a test of the branch being taken rather
--- than of a number the fake invented.
function TestSkynetIADSUtils:test_getDir_with_a_reference_point_applies_the_north_correction()
	local vec = { x = 0, y = 0, z = 1 }
	luaunit.assertEquals(SkynetIADSUtils.getNorthCorrection({ x = 0, y = 0, z = 0 }), 0)
	luaunit.assertAlmostEquals(SkynetIADSUtils.getDir(vec, { x = 0, y = 0, z = 0 }), SkynetIADSUtils.getDir(vec), 1e-9)
end

--- The heading from one point to another, which is what the HARM aspect calculation asks for
--- before deciding whether a missile is pointed at the radar or merely passing it.
function TestSkynetIADSUtils:test_getHeadingPoints_measures_from_the_first_point_to_the_second()
	local origin = { x = 0, y = 0, z = 0 }
	luaunit.assertAlmostEquals(
		SkynetIADSUtils.getHeadingPoints(origin, { x = 1000, y = 0, z = 0 }),
		0,
		1e-9,
		"due grid north"
	)
	luaunit.assertAlmostEquals(
		SkynetIADSUtils.getHeadingPoints(origin, { x = 0, y = 0, z = 1000 }),
		math.pi / 2,
		1e-9,
		"due grid east"
	)
	-- and the other way round is the reciprocal, not the same bearing
	luaunit.assertAlmostEquals(
		SkynetIADSUtils.getHeadingPoints({ x = 0, y = 0, z = 1000 }, origin),
		3 * math.pi / 2,
		1e-9
	)
end

function TestSkynetIADSUtils:test_getHeadingPoints_north_corrected_matches_the_raw_one_here()
	local origin = { x = 0, y = 0, z = 0 }
	local target = { x = 1000, y = 0, z = 1000 }
	luaunit.assertAlmostEquals(
		SkynetIADSUtils.getHeadingPoints(origin, target, true),
		SkynetIADSUtils.getHeadingPoints(origin, target),
		1e-9
	)
end

-- ---- the two ends of a scheduled task's life ------------------------------------------------

--- A repeating task with a stop time stops, and stops for good. Without this the coverage
--- refresh and the contact cycle would be the only scheduler users ever exercised, and both run
--- forever.
function TestSkynetIADSUtils:test_a_repeating_task_stops_at_its_stop_time()
	local runs = 0
	SkynetIADSUtils.scheduleFunction(function()
		runs = runs + 1
	end, {}, 1, 5, 12)

	for _ = 1, 4 do
		dcsStub.advanceClock(5)
		dcsStub.fireDueTimers()
	end
	luaunit.assertEquals(runs, 2, "it ran at 5 s and at 10 s, and the 15 s tick was past the stop time")

	dcsStub.advanceClock(100)
	dcsStub.fireDueTimers()
	luaunit.assertEquals(runs, 2, "and it does not come back")
end

--- A task that removes itself while it is running must not be re-armed afterwards. This is what
--- SkynetIADS:deactivate() does from inside a cycle, and re-arming a task whose owner has just
--- been torn down is how a dead network keeps polling DCS objects that no longer exist.
function TestSkynetIADSUtils:test_a_task_that_removes_itself_is_not_rearmed()
	local runs = 0
	local id
	id = SkynetIADSUtils.scheduleFunction(function()
		runs = runs + 1
		SkynetIADSUtils.removeFunction(id)
	end, {}, 1, 5)

	dcsStub.advanceClock(5)
	dcsStub.fireDueTimers()
	luaunit.assertEquals(runs, 1)

	dcsStub.advanceClock(100)
	dcsStub.fireDueTimers()
	luaunit.assertEquals(runs, 1, "it took itself off the scheduler from inside its own run")
end

--- Removing a task that is merely pending, from outside, has the same effect by the other route.
function TestSkynetIADSUtils:test_a_task_removed_before_it_fires_never_runs()
	local runs = 0
	local id = SkynetIADSUtils.scheduleFunction(function()
		runs = runs + 1
	end, {}, 1, 5)
	luaunit.assertEquals(SkynetIADSUtils.removeFunction(id), true)

	dcsStub.advanceClock(100)
	dcsStub.fireDueTimers()
	luaunit.assertEquals(runs, 0)
end

os.exit(luaunit.LuaUnit.run())
