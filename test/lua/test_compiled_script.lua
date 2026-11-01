--- Builds the compiled script, loads it against the DCS stub and runs it as a main chunk, failing
--- if it raises.
---
--- The other suites load the sources one file at a time, so they cannot see what only the
--- concatenation does: a top-level `local` shadowing a later file's name, the 200-locals limit of
--- a single chunk, two files' lines merging. A build proves the files concatenate; this proves
--- the result runs.
---
--- It builds what it tests, into build/test/, and never reads or touches
--- build/skynet-iads-compiled.lua: whether that file is current could only be told by building
--- anyway. It skips, saying so, when no Python runs; once one does, a build that fails is a failure.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/dcs-stub.lua")

-- Same sentinel skynet-loader.lua sets up: the wrapper only touches Group at load time to tell a
-- Group from a Unit/Static, so a bare table is enough here.
Group = Group or {}

local root = base .. "/../.."
local output = root .. "/build/test/skynet-iads-compiled.lua"
local quiet = package.config:sub(1, 1) == "\\" and " >nul 2>&1" or " >/dev/null 2>&1"

--- The first interpreter that runs. On Windows `python3` can be the Microsoft Store alias, which
--- exists and fails, so being on PATH is not enough: it has to answer `--version`.
local function findPython()
	for _, name in ipairs({ "python3", "python" }) do
		if os.execute(name .. " --version" .. quiet) == 0 then
			return name
		end
	end
end

TestCompiledScript = {}

function TestCompiledScript:testRunsAsAMainChunk()
	local python = findPython()
	if not python then
		-- luaunit counts a skip without printing its reason.
		local reason = "compiled script not tested: neither python3 nor python runs"
		print(reason)
		luaunit.skip(reason)
	end

	-- Unquoted first: cmd.exe strips the quotes of a command line that starts with one.
	local command = python .. ' "' .. root .. '/build-tools/build-compiled-script.py" --output "' .. output .. '"'
	if os.execute(command) ~= 0 then
		luaunit.fail("the build failed: " .. command)
	end

	local chunk, loadErr = loadfile(output)
	if not chunk then
		luaunit.fail("failed to load " .. output .. ":\n" .. tostring(loadErr))
	end
	local ok, runErr = pcall(chunk)
	if not ok then
		luaunit.fail(output .. " raised while executing:\n" .. tostring(runErr))
	end
end

os.exit(luaunit.LuaUnit.run())
