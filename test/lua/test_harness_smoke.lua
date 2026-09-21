--- Smoke test: the vendored luaunit runs, and skynet-loader loads the two
--- source files the contact pilot needs, populating their globals.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/luaunit.lua")
local loader = dofile(base .. "/skynet-loader.lua")

-- Group is the only global the wrapper touches at load time (a sentinel it
-- compares metatables against). dcs-stub owns it from Task 2 on; here a bare
-- table is enough to load the file.
Group = Group or {}

TestHarnessSmoke = {}

function TestHarnessSmoke:test_luaunit_is_loaded()
	luaunit.assertEquals(type(luaunit.LuaUnit.run), "function")
end

function TestHarnessSmoke:test_loader_loads_wrapper_and_contact()
	loader.load("skynet-iads-abstract-dcs-object-wrapper")
	loader.load("skynet-iads-contact")
	luaunit.assertEquals(type(inheritsFrom), "function")
	luaunit.assertEquals(type(SkynetIADSAbstractDCSObjectWrapper), "table")
	luaunit.assertEquals(type(SkynetIADSContact), "table")
	luaunit.assertEquals(SkynetIADSContact.HARM, "HARM")
end

function TestHarnessSmoke:test_loader_loads_skynet_iads_utils()
	loader.load("skynet-iads-utils")
	luaunit.assertEquals(type(SkynetIADSUtils), "table")
	luaunit.assertEquals(type(SkynetIADSUtils.round), "function")
	luaunit.assertEquals(SkynetIADSUtils.round(2.5), 3)
end

function TestHarnessSmoke:test_loadAll_includes_utils()
	loader.reset()
	loader.loadAll()
	luaunit.assertEquals(type(SkynetIADSUtils), "table")
end

function TestHarnessSmoke:test_loader_order_matches_the_build_list()
	-- The loader's ORDER claims to be verbatim from listToMerge.txt. Nothing enforced that,
	-- and the cost of a drift is quiet: a source added to the build but not to the loader is
	-- never loaded by the suite, so it is neither tested nor even visible to the test-coverage
	-- report — luacov only knows about files something executed.
	local listPath = base .. "/../../build-tools/listToMerge.txt"
	local list = assert(io.open(listPath, "r"), "cannot open " .. listPath)
	local expected = {}
	for line in list:lines() do
		local entry = line:match("^%s*(.-)%s*$")
		-- highdigitsams/ is a separate suite the loader deliberately leaves out. Any *other*
		-- subdirectory appearing here should fail this test rather than be skipped silently.
		if entry ~= "" and entry:sub(1, 1) ~= "#" and entry:sub(1, #"highdigitsams/") ~= "highdigitsams/" then
			local name = entry:gsub("%.lua$", "")
			expected[#expected + 1] = name
		end
	end
	list:close()

	luaunit.assertEquals(loader.ORDER, expected)
end

function TestHarnessSmoke:test_loader_memoises()
	loader.load("skynet-iads-contact")
	loader.load("skynet-iads-contact") -- second call must be a no-op, not an error
	luaunit.assertEquals(type(SkynetIADSContact), "table")
end

function TestHarnessSmoke:test_loader_reset_forces_reload()
	loader.load("skynet-iads-abstract-dcs-object-wrapper")
	loader.load("skynet-iads-contact")
	luaunit.assertEquals(type(SkynetIADSContact), "table")

	-- wipe the global the file defines; a memoised load would NOT bring it back
	SkynetIADSContact = nil
	loader.load("skynet-iads-contact") -- still memoised => no-op
	luaunit.assertNil(SkynetIADSContact)

	-- reset drops the memo; the next load genuinely re-runs the file
	loader.reset()
	loader.load("skynet-iads-contact")
	luaunit.assertEquals(type(SkynetIADSContact), "table")
end

os.exit(luaunit.LuaUnit.run())
