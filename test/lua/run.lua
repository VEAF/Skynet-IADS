--- Discover and run every test/lua/test_*.lua as a child process, aggregating
--- exit codes.  Usage:  lua run.lua [filenameSubstring]

assert(_VERSION == "Lua 5.1", "run.lua: needs Lua 5.1 (DCS runtime); got " .. _VERSION)

local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
local sep = package.config:sub(1, 1) -- "\" on Windows, "/" elsewhere
local isWindows = (sep == "\\")
local interp = arg[-1] or "lua"
local filter = arg[1]

-- SKYNET_TEST_COVERAGE=1 makes every child load luacov. Each one merges its counts into
-- luacov.stats.out in the working directory rather than overwriting it, which is what makes
-- these separate processes add up to a single report; luacov also wraps os.exit, which is how
-- a suite always ends through luaunit. Unset, the run below is exactly what it was before,
-- with no debug hook installed.
--
-- That merging is also a trap between two runs: luacov adds to whatever luacov.stats.out it
-- finds, so a second run reports the union of both -- including lines of code that the first run
-- covered and that no longer exist. It reads as a rise. It cost a coverage floor being raised to
-- a figure the suite had never actually reached, caught by CI measuring 91.01% where this
-- machine claimed 92.01%. So the stale file goes before anything runs.
local coverage = os.getenv("SKYNET_TEST_COVERAGE")
local coverageFlag = ""
if coverage and coverage ~= "" and coverage ~= "0" then
	coverageFlag = " -lluacov"
	os.remove("luacov.stats.out")
	os.remove("luacov.report.out")
end

local function listSuites()
	local cmd
	if isWindows then
		cmd = 'dir /b "' .. base .. '\\test_*.lua"'
	else
		cmd = 'ls -1 "' .. base .. '"/test_*.lua'
	end
	local names = {}
	local p = assert(io.popen(cmd))
	for line in p:lines() do
		local name = line:match("([^\\/]+)$")
		if name and name:match("^test_.+%.lua$") then
			if not filter or name:find(filter, 1, true) then
				names[#names + 1] = name
			end
		end
	end
	p:close()
	table.sort(names)
	return names
end

local suites = listSuites()
if #suites == 0 then
	if filter then
		print("run.lua: no suites match '" .. filter .. "'")
		os.exit(0)
	end
	print("run.lua: no suites found in " .. base)
	os.exit(1)
end

local failed = {}
for _, name in ipairs(suites) do
	print("\n--- " .. name .. " ---")
	io.stdout:flush()
	local target = base .. sep .. name
	local cmd
	if isWindows then
		-- cmd.exe strips one leading+trailing quote pair from the whole string,
		-- so wrap the already-quoted command in an extra pair.
		cmd = '""' .. interp .. '"' .. coverageFlag .. ' "' .. target .. '""'
	else
		cmd = '"' .. interp .. '"' .. coverageFlag .. ' "' .. target .. '"'
	end
	local ok = os.execute(cmd)
	-- Lua 5.1 os.execute returns the process exit code (0 == success). Some
	-- builds return true/false; treat both non-zero and false as failure.
	if ok ~= 0 and ok ~= true then
		failed[#failed + 1] = name
	end
end

print("\n======================================")
if #failed == 0 then
	print("ALL " .. #suites .. " SUITE(S) PASSED")
	os.exit(0)
end
print(#failed .. " SUITE(S) FAILED:")
for _, n in ipairs(failed) do
	print("  - " .. n)
end
os.exit(1)
