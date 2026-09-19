--- Standalone port of unit-tests/test-skynet-iads-abstract-dcs-object-wrapper.lua.
--- All 5 tests exercise the wrapper around a fixture unit: EW-SA-6, a Kub 1S91 str.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
local loader = dofile(base .. "/skynet-loader.lua")
loader.loadAll()

TestSkynetIADSAbstractDCSObjectWrapper = {}

function TestSkynetIADSAbstractDCSObjectWrapper:setUp()
	dcsStub.reset()
	self.unit = dcsStub.makeUnit({ name = "EW-SA-6", type = "Kub 1S91 str", pos = { x = 0, y = 0, z = 0 } })
	self.abstractObjectWrapper = SkynetIADSAbstractDCSObjectWrapper:create(self.unit)
end

function TestSkynetIADSAbstractDCSObjectWrapper:tearDown() end

function TestSkynetIADSAbstractDCSObjectWrapper:testGetName()
	luaunit.assertEquals(self.abstractObjectWrapper:getName(), "EW-SA-6")
	self.abstractObjectWrapper.dcsRepresentation = nil
	--test to see if name is still returned after object wrapped is nil
	luaunit.assertEquals(self.abstractObjectWrapper:getName(), "EW-SA-6")
end

function TestSkynetIADSAbstractDCSObjectWrapper:testGetTypeName()
	luaunit.assertEquals(self.abstractObjectWrapper:getTypeName(), "Kub 1S91 str")
	self.abstractObjectWrapper.dcsRepresentation = nil
	luaunit.assertEquals(self.abstractObjectWrapper:getTypeName(), "Kub 1S91 str")
end

function TestSkynetIADSAbstractDCSObjectWrapper:testIsExist()
	luaunit.assertEquals(self.abstractObjectWrapper:isExist(), true)
	self.abstractObjectWrapper.dcsRepresentation = nil
	luaunit.assertEquals(self.abstractObjectWrapper:isExist(), false)
end

function TestSkynetIADSAbstractDCSObjectWrapper:testGetDCSRepresentation()
	luaunit.assertEquals(self.abstractObjectWrapper:getDCSRepresentation(), Unit.getByName("EW-SA-6"))
end

function TestSkynetIADSAbstractDCSObjectWrapper:testInsertToTableIfNotAlreadyAdded()
	local tbl = {}
	local mock = {}
	table.insert(tbl, mock)
	local result = self.abstractObjectWrapper:insertToTableIfNotAlreadyAdded(tbl, mock)
	luaunit.assertEquals(#tbl, 1)
	luaunit.assertEquals(result, false)

	local mock2 = {}
	local result2 = self.abstractObjectWrapper:insertToTableIfNotAlreadyAdded(tbl, mock2)
	luaunit.assertEquals(#tbl, 2)
	luaunit.assertEquals(result2, true)
end

-- ---- CHORE-TEST-COVERAGE-FLOOR ticket 06 ---------------------------------------------------

--- The wrapper forwards the position of whatever it wraps, which is how every distance in the
--- project reaches a DCS object.
function TestSkynetIADSAbstractDCSObjectWrapper:testThePositionIsTheWrappedObjects()
	local unit = dcsStub.makeUnit({ name = "positioned", pos = { x = 100, y = 20, z = 300 } })
	local wrapper = SkynetIADSAbstractDCSObjectWrapper:create(unit)
	luaunit.assertEquals(wrapper:getPosition().p, { x = 100, y = 20, z = 300 })
end

--- Some DCS objects answer an empty name and carry only a runtime id. The wrapper falls back to
--- it, because a nameless element is otherwise indistinguishable from every other nameless
--- element in the status page and in the coverage graph.
function TestSkynetIADSAbstractDCSObjectWrapper:testAnObjectWithNoNameFallsBackToItsRuntimeId()
	local unit = dcsStub.makeUnit({ name = "will-be-blanked" })
	function unit:getName()
		return ""
	end
	unit.id_ = 4711

	local wrapper = SkynetIADSAbstractDCSObjectWrapper:create(unit)
	luaunit.assertEquals(wrapper:getName(), 4711)
end

--- The inheritance helper's class(), isa() and the default create() it gives every subclass are
--- NOT tested, and stay uncovered on purpose. Nothing in this repository calls them: all ten
--- classes built with inheritsFrom() define their own create, and isa/class appear nowhere
--- outside their own definition -- checked across skynet-iads-source, test/lua and unit-tests.
---
--- They are still methods on every Skynet object, and the built artifact is vendored by
--- VEAF-Mission-Creation-Tools, so a mission script may be calling them without this repository
--- ever knowing. Deleting undocumented public surface from a vendored deliverable is a decision
--- for VEAF, not a side effect of a test-coverage ticket, so they are left in place and written
--- down here instead. That is 11 lines of the denominator, and where they went.

os.exit(luaunit.LuaUnit.run())
