--- Smoke test: the vendored luaunit runs, and skynet-loader loads the two
--- source files the contact pilot needs, populating their globals.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
local loader = dofile(base .. "/../common/skynet-loader.lua")

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

function TestHarnessSmoke:test_set_root_overrides_source_directory()
  local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
  local fresh = dofile(base .. "/../common/skynet-loader.lua")
  fresh.setRoot(base .. "/no-such-directory")
  local ok, err = pcall(fresh.load, "skynet-iads-utils")
  luaunit.assertFalse(ok)
  luaunit.assertStrContains(tostring(err), "no-such-directory")
end

function TestHarnessSmoke:test_set_root_accepts_trailing_separator()
  local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
  local fresh = dofile(base .. "/../common/skynet-loader.lua")
  fresh.setRoot(base .. "/../../skynet-iads-source/")
  fresh.load("skynet-iads-utils")
  luaunit.assertNotNil(SkynetIADSUtils)
end

os.exit(luaunit.LuaUnit.run())
