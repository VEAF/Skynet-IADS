--- insim-skynet.lua: the Skynet layer of the in-sim suite (test/insim/). It runs in DCS under
--- dcs-hotload; here hotload is stubbed, Skynet is the real source and the groups are stubs.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()
local F = dofile(base .. "/dcs-fixtures.lua")

Hotload = {
	root = base .. "/no-such-hotload-root",
	callOnMain = function(fn)
		return pcall(fn)
	end,
}

local S = dofile(base .. "/../insim/dcs-hotload/user-lib/insim-skynet.lua")

local function writeFile(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end

local function fakeContext(name)
	local ctx = { name = name, cleanups = {} }
	function ctx:onCleanup(fn)
		table.insert(self.cleanups, fn)
	end
	return ctx
end

TestInsimSkynet = {}

function TestInsimSkynet:setUp()
	dcsStub.reset()
	dcsStub.stubUtilsScheduler()
	InsimSkynetState = {}
	rawset(_G, "BootProbe", nil)
	self.script = os.tmpname()
	InsimSkynetState.scriptPath = self.script
end

function TestInsimSkynet:tearDown()
	os.remove(self.script)
	if self.iads then
		self.iads:deactivate()
		self.iads = nil
	end
end

local RED = { coalition = coalition.side.RED }

local function buildScenarioUnits()
	F.samGroup("SA-6", "iadsx/SAM-SA6", RED)
	F.earlyWarningRadarGroup("iadsx/EW", "iadsx/EW-1", RED)
	F.samGroup("SA-6", "iadsy/SAM-SA6", RED)
end

function TestInsimSkynet:testIadsTakesOnlyThisScenariosUnits()
	buildScenarioUnits()
	self.iads = S.iads(fakeContext("iadsx"))
	luaunit.assertEquals(#self.iads:getSAMSites(), 1)
	luaunit.assertEquals(#self.iads:getEarlyWarningRadars(), 1)
end

function TestInsimSkynet:testCleanupDeactivatesTheIads()
	buildScenarioUnits()
	local ctx = fakeContext("iadsx")
	self.iads = S.iads(ctx)
	luaunit.assertEquals(#ctx.cleanups, 1)
	luaunit.assertTrue(dcsStub.scheduledCount() > 0)
	ctx.cleanups[1]()
	luaunit.assertEquals(dcsStub.scheduledCount(), 0)
end

function TestInsimSkynet:testIadsRaisesWhatCallOnMainReports()
	Hotload.callOnMain = function()
		return false, "boom"
	end
	local ok, err = pcall(S.iads, fakeContext("iadsx"))
	Hotload.callOnMain = function(fn)
		return pcall(fn)
	end
	luaunit.assertFalse(ok)
	luaunit.assertEquals(err, "boom")
end

function TestInsimSkynet:testBootRunsTheScriptAndKnowsItIsCurrent()
	writeFile(self.script, "BootProbe = 42")
	luaunit.assertFalse(S.scriptIsCurrent())
	S.boot()
	luaunit.assertEquals(rawget(_G, "BootProbe"), 42)
	luaunit.assertTrue(S.scriptIsCurrent())
end

function TestInsimSkynet:testRewrittenScriptIsNotCurrent()
	writeFile(self.script, "BootProbe = 42")
	S.boot()
	writeFile(self.script, "BootProbe = 43")
	luaunit.assertFalse(S.scriptIsCurrent())
end

function TestInsimSkynet:testBootWithoutTheScriptRaises()
	InsimSkynetState.scriptPath = nil
	local ok, err = pcall(S.boot)
	luaunit.assertFalse(ok)
	luaunit.assertStrContains(err, "skynet-iads-insim.lua")
end

os.exit(luaunit.LuaUnit.run())
