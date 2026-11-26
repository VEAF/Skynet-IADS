-- The Skynet layer of the in-sim test suite, in the mission. `boot` loads the Skynet script under
-- test once, at mission start; `scriptIsCurrent` tells whether that script is still the file on
-- disk; `iads` builds a scenario's IADS from the units the scenario added. The text loaded is kept
-- in InsimSkynetState, which is why that global is guarded: a reload of this file must not wipe it.
InsimSkynetState = InsimSkynetState or {}

local S = {}

-- Relative to Hotload.root.
S.SCRIPT = "/../../../build/insim/skynet-iads-insim.lua"

local function scriptPath()
	return InsimSkynetState.scriptPath or (Hotload.root .. S.SCRIPT)
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

-- Runs from a DO SCRIPT action at mission start, outside any hotload run: nothing here may pause.
-- Hotload.root is set only once dcs-hotload has started; when it has not, it has already logged why
-- (a DCS update reverting the MissionScripting.lua edit, most often), so boot only logs and skips.
function S.boot()
	if not Hotload.root then
		env.warning("insim-skynet: dcs-hotload did not start, the Skynet script is not loaded")
		return
	end
	local path = scriptPath()
	local text = readFile(path)
	if not text then
		error("cannot read the Skynet script " .. path, 0)
	end
	InsimSkynetState.text = nil
	assert(loadstring(text, "@" .. path))()
	InsimSkynetState.text = text -- only a script that ran without error counts as loaded
end

function S.scriptIsCurrent()
	if not InsimSkynetState.text then
		return false
	end
	return readFile(scriptPath()) == InsimSkynetState.text
end

-- A scenario's fixture roles for Skynet start with SAM or EW. `configure(iads)`, optional, runs
-- once they are added and before the IADS is activated. The deactivation is registered as soon as
-- the IADS exists, so a failure further on still leaves cleanup something to call.
function S.iads(ctx, configure)
	local ok, result = Hotload.callOnMain(function()
		return SkynetIADS:create(ctx.name)
	end)
	if not ok then
		error(result, 0)
	end
	local iads = result
	ctx:onCleanup(function()
		iads:deactivate()
	end)
	ok, result = Hotload.callOnMain(function()
		iads:addSAMSitesByPrefix(ctx.name .. "/SAM")
		iads:addEarlyWarningRadarsByPrefix(ctx.name .. "/EW")
		if configure then
			configure(iads)
		end
		-- so a run can be watched: the network on the F10 map, its radio menu, and what it decides
		-- in dcs.log. Its deactivation at cleanup takes the map and the menu away.
		local debugSettings = iads:getDebugSettings()
		debugSettings.radarWentLive = true
		debugSettings.radarWentDark = true
		debugSettings.harmDefence = true
		iads:addRadioMenu()
		iads:displayMap(true)
		iads:activate()
	end)
	if not ok then
		error(result, 0)
	end
	return iads
end

return S
