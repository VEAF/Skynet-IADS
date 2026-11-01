--- Checks that every DCS unit type samTypesDB names still exists in the DCS database.
---
--- samTypesDB is maintained by hand. When ED renames a unit, a site placing it is classified
--- without it, and nothing says so. This fetches the current head of the Quaggles/dcs-lua-datamine
--- dump -- its file list only, no file content -- and fails on every type, in every role, that has
--- no file under _G/db/Units/.
---
---   lua5.1 test/lua/check-unit-types.lua
---
--- It reads the head, not a pin: nothing is committed but this script, and a red run is the news.
--- It needs the network, which is why it is not named test_* and the runners leave it out.
--- The High Digit SAMs are a mod, so their types are not in ED's dump and are not checked.
---
--- Exit codes: 0 every type resolves, 1 some are missing, 2 nothing could be measured.

local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
local root = base .. "/../.."
local dest = root .. "/build/dcs-lua-datamine"
local DATAMINE = "https://github.com/Quaggles/dcs-lua-datamine.git"
local ROLES = { "searchRadar", "trackingRadar", "launchers", "misc" }
local isWindows = package.config:sub(1, 1) == "\\"

local function fail(reason)
	io.stderr:write("check-unit-types: " .. reason .. "\n")
	os.exit(2)
end

-- cmd.exe strips one leading+trailing quote pair from the whole string, as run.lua explains.
local function shell(cmd)
	if isWindows then
		return '"' .. cmd .. '"'
	end
	return cmd
end

local function succeeded(status)
	return status == 0 or status == true
end

local function fetchUnits()
	local head = io.open(dest .. "/.git/HEAD", "r")
	if head then
		head:close()
	elseif not succeeded(os.execute(shell('git init -q "' .. dest .. '"'))) then
		fail("cannot create " .. dest)
	end
	local fetch = 'git -C "' .. dest .. '" fetch -q --depth=1 --filter=blob:none ' .. DATAMINE .. " HEAD"
	if not succeeded(os.execute(shell(fetch))) then
		fail("cannot fetch the datamine from " .. DATAMINE)
	end
	local units = {}
	local p = assert(io.popen(shell('git -C "' .. dest .. '" ls-tree -r --name-only FETCH_HEAD -- _G/db/Units')))
	for line in p:lines() do
		local name = line:match("([^/]+)%.lua$")
		if name then
			units[name] = true
		end
	end
	p:close()
	if next(units) == nil then
		fail("the datamine lists no unit under _G/db/Units")
	end
	return units
end

local function unitTypes()
	dofile(root .. "/skynet-iads-source/skynet-iads-supported-types.lua")
	local types = {}
	for site, def in pairs(samTypesDB) do
		for _, role in ipairs(ROLES) do
			for unitType in pairs(def[role] or {}) do
				types[#types + 1] = { site = site, role = role, unitType = unitType }
			end
		end
	end
	if #types == 0 then
		fail("samTypesDB names no unit type")
	end
	return types
end

local units = fetchUnits()
local types = unitTypes()
local missing = {}
for _, t in ipairs(types) do
	if not units[t.unitType] then
		missing[#missing + 1] = t.site .. " / " .. t.role .. " / " .. t.unitType
	end
end
table.sort(missing)
for _, line in ipairs(missing) do
	print(line)
end
print(#types .. " unit types checked, " .. #missing .. " missing from the DCS database")
os.exit(#missing == 0 and 0 or 1)
