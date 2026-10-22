-- Judges a scenario's recorded result outside DCS, in plain Lua 5.1.
-- Usage: lua verify.lua <scenario verify.lua> <result file>
-- Exit 0 and no output when verify.lua returns; exit 1 and the error message on stdout when it raises;
-- exit 2 and a message when verify.lua is missing, does not compile or does not return a function.

local verifyPath, resultPath = arg[1], arg[2]
if not verifyPath or not resultPath then
	print("usage: verify.lua <verify.lua> <result file>")
	os.exit(2)
end

local here = (arg[0]:gsub("\\", "/")):match("^(.*)/[^/]*$") or "."
local luaunit = dofile(here .. "/../../lua/luaunit.lua")

local chunk, loadError = loadfile(verifyPath)
if not chunk then
	print(loadError)
	os.exit(2)
end
local loaded, verifyFn = pcall(chunk)
if not loaded then
	print(verifyFn)
	os.exit(2)
end
if type(verifyFn) ~= "function" then
	print(verifyPath .. " does not return a function")
	os.exit(2)
end

local result = dofile(resultPath)
local ok, err = pcall(verifyFn, result, luaunit)
if not ok then
	print(err)
	os.exit(1)
end
os.exit(0)
