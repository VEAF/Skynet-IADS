--- Loads and runs the compiled artifact against the DCS stub, and fails if it raises.
--- A build proves the files concatenate; this proves the result executes as a main
--- chunk, which loadfile() alone does not catch (a chunk can parse cleanly and still
--- raise the moment it runs).
--- Usage: lua5.1 build-tools/check-artifact.lua <path-to-compiled-artifact>

local artifactPath = arg[1]
if not artifactPath then
  print("usage: check-artifact.lua <path-to-compiled-artifact>")
  os.exit(1)
end

local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
dofile(base .. "/../test/lua/dcs-stub.lua")

-- Same sentinel skynet-loader.lua sets up: the wrapper only touches Group at load
-- time to tell a Group from a Unit/Static, so a bare table is enough here.
Group = Group or {}

local chunk, loadErr = loadfile(artifactPath)
if not chunk then
  print("check-artifact: failed to load '" .. artifactPath .. "':\n" .. tostring(loadErr))
  os.exit(1)
end

local ok, runErr = pcall(chunk)
if not ok then
  print("check-artifact: '" .. artifactPath .. "' raised while executing:\n" .. tostring(runErr))
  os.exit(1)
end

print("check-artifact: " .. artifactPath .. " loaded and ran without raising")
os.exit(0)
