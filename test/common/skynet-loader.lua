--- Loads Skynet source files (globals, no modules) in dependency order,
--- the same order build-tools/listToMerge.txt concatenates them.
--- Usage:
---   local loader = dofile(".../skynet-loader.lua")
---   loader.load("skynet-iads-contact")   -- one file
---   loader.loadAll()                      -- everything

local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "./"
local src = base .. "/../../skynet-iads-source/"

-- The order is the build's: build-tools/listToMerge.txt, read once. The highdigitsams/ entry is
-- left out: it is a separate suite, not part of the core load.
local ORDER = {}
local listPath = base .. "/../../build-tools/listToMerge.txt"
local list = io.open(listPath, "r")
if not list then
	error("skynet-loader: cannot read " .. listPath)
end
for line in list:lines() do
	local entry = line:match("^%s*(.-)%s*$")
	if entry ~= "" and entry:sub(1, 1) ~= "#" and entry:sub(1, #"highdigitsams/") ~= "highdigitsams/" then
		ORDER[#ORDER + 1] = (entry:gsub("%.lua$", ""))
	end
end
list:close()

local M = { _loaded = {} }

function M.load(name)
	if M._loaded[name] then
		return
	end
	local path = src .. name .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then
		error("skynet-loader: cannot load '" .. name .. "' from " .. path .. "\n" .. tostring(err))
	end
	local ok, execErr = pcall(chunk)
	if not ok then
		error("skynet-loader: '" .. name .. "' failed while executing: " .. tostring(execErr))
	end
	M._loaded[name] = true
end

function M.loadAll()
	for _, name in ipairs(ORDER) do
		M.load(name)
	end
end

return M
