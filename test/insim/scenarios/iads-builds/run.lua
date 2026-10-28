local ctx = ...
local iads = ctx.state.iads

local function site(role)
	local s = iads:getSAMSiteByGroupName(ctx.name .. "/" .. role)
	if not s then
		return "absent"
	end
	return {
		nato = s:getNatoName(),
		launchers = #s:getLaunchers(),
		searchRadars = #s:getSearchRadars(),
		trackingRadars = #s:getTrackingRadars(),
	}
end

local function radar(role)
	local e = iads:getEarlyWarningRadarByUnitName(ctx.name .. "/" .. role .. "-1")
	if not e then
		return "absent"
	end
	return {
		nato = e:getNatoName(),
		workingRadar = e:hasWorkingRadar(),
		awacs = getmetatable(e) == SkynetIADSAWACSRadar,
	}
end

local names = {}
for _, s in ipairs(iads:getSAMSites()) do
	names[#names + 1] = s:getDCSName()
end
table.sort(names)

return {
	sam = #iads:getSAMSites(),
	ew = #iads:getEarlyWarningRadars(),
	samNames = names,
	sa10 = site("SAM-SA10"),
	sa8 = site("SAM-SA8"),
	sa6 = site("SAM-SA6"),
	ew1l13 = radar("EW-1L13"),
	awacs = radar("EW-AWACS"),
}
