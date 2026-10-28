--- insim-watch.lua: the watch of the in-sim suite (test/insim/), which records the values a probe
--- goes through. It runs in DCS under dcs-hotload; here hotload is stubbed and the timer is the
--- stub's, fired by hand.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/../lua/dcs-stub.lua")

Hotload = {
	callOnMain = function(fn)
		return pcall(fn)
	end,
	-- Calls the predicate once per simulated second, firing the timers in between.
	waitFor = function(predicate, timeout)
		for _ = 1, timeout do
			if predicate() then
				return true
			end
			dcsStub.advanceClock(1)
			dcsStub.fireDueTimers()
		end
		return false
	end,
}

local W = dofile(base .. "/../insim/dcs-hotload/user-lib/insim-watch.lua")

local function fakeContext()
	local ctx = { cleanups = {} }
	function ctx:onCleanup(fn)
		table.insert(self.cleanups, fn)
	end
	function ctx:cleanUp()
		for i = #self.cleanups, 1, -1 do
			self.cleanups[i]()
		end
	end
	return ctx
end

-- A probe answering the values in turn, the last one for ever after.
local function answers(values)
	local i = 0
	return function()
		i = math.min(i + 1, #values)
		local value = values[i]
		if type(value) == "function" then
			return value()
		end
		return value
	end
end

local function tick(n)
	for _ = 1, n do
		dcsStub.advanceClock(1)
		dcsStub.fireDueTimers()
	end
end

TestInsimWatch = {}

function TestInsimWatch:setUp()
	dcsStub.reset()
	self.ctx = fakeContext()
end

function TestInsimWatch:tearDown()
	self.ctx:cleanUp()
end

function TestInsimWatch:testRecordsOnlyTheChanges()
	local watch = W.start(self.ctx, { active = answers({ false, false, true, true, false }) }, 1)
	tick(5)
	luaunit.assertEquals(watch:sequence("active"), { false, true, false })
end

function TestInsimWatch:testAProbeThatRaisesIsRecordedAndTheWatchGoesOn()
	local boom = function()
		error("boom", 0)
	end
	local watch = W.start(self.ctx, { active = answers({ true, true, boom, false }) }, 1)
	tick(4)
	luaunit.assertEquals(watch:sequence("active"), { true, "error: boom", false })
end

function TestInsimWatch:testANilAnswerIsRecorded()
	local none = function()
		return nil
	end
	local watch = W.start(self.ctx, { site = answers({ "x", none }) }, 1)
	tick(2)
	luaunit.assertEquals(watch:sequence("site"), { "x", "nil" })
end

function TestInsimWatch:testCleanupStopsTheWatch()
	local watch = W.start(self.ctx, { active = answers({ false, true }) }, 1)
	tick(1)
	self.ctx:cleanUp()
	self.ctx.cleanups = {}
	tick(3)
	luaunit.assertEquals(watch:sequence("active"), { false })
end

function TestInsimWatch:testWaitForMatchesTheStartOfTheSequence()
	local watch = W.start(self.ctx, { active = answers({ false, true, false, true }) }, 1)
	luaunit.assertTrue(watch:waitFor("active", { false, true, false }, 10))
end

function TestInsimWatch:testWaitForGivesUp()
	local watch = W.start(self.ctx, { active = answers({ false }) }, 1)
	luaunit.assertFalse(watch:waitFor("active", { false, true }, 5))
end

function TestInsimWatch:testReportHoldsEverySequence()
	local watch = W.start(self.ctx, { a = answers({ 1, 2 }), b = answers({ "x" }) }, 1)
	tick(2)
	luaunit.assertEquals(watch:report(), { a = { 1, 2 }, b = { "x" } })
end

os.exit(luaunit.LuaUnit.run())
