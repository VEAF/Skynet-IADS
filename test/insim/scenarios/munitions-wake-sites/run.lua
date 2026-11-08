local ctx = ...
local Wd = Hotload.load("insim-world")
local W = Hotload.load("insim-watch")
local sites = ctx.state.sites

local LOADOUTS = { -- F-16C bl.52d, stations 3 and 8 (MissionEditor/data/scripts/UnitPayloads/F-16C.lua)
	bomb = {
		pylons = { [3] = { CLSID = "{GBU-38}" }, [8] = { CLSID = "{GBU-38}" } },
		weaponType = 14, -- guided bombs (MissionEditor/modules/me_action_db.lua)
	},
	missile = {
		pylons = {
			[3] = { CLSID = "{E6A6262A-CA08-4B3D-B030-E1A993B98452}" },
			[8] = { CLSID = "{E6A6262A-CA08-4B3D-B030-E1A993B98453}" },
		}, -- AGM-65D
		weaponType = 1835008, -- standard air-to-surface missiles
	},
}

local function allDark()
	return Hotload.waitFor(function()
		return not (sites["SAM-TORM2"]:isActive() or sites["SAM-SA10"]:isActive() or sites["SAM-SA6"]:isActive())
	end, 60)
end

-- One attacker, invisible so that only its munition is ever a contact, on the SA-6: the one site
-- that must not wake for anything it drops.
local function pass(kind)
	if not allDark() then
		ctx.invalid(kind .. ": the sites were not all dark before the attack")
	end
	local watch = W.start(ctx, {
		torM2 = function()
			return sites["SAM-TORM2"]:isActive()
		end,
		sa10 = function()
			return sites["SAM-SA10"]:isActive()
		end,
		sa6 = function()
			return sites["SAM-SA6"]:isActive()
		end,
		-- the munition contacts in the network's picture: no wake can happen without one
		munitionContacts = function()
			local classes = {}
			for _, contact in ipairs(ctx.state.iads:getContacts()) do
				local class = contact:getTargetClass()
				if class and class ~= SkynetIADSContact.CLASS_AIRCRAFT then
					classes[#classes + 1] = class
				end
			end
			table.sort(classes)
			return table.concat(classes, ",")
		end,
	}, 1)
	local loadout = LOADOUTS[kind]
	local shots = Wd.recordShots(ctx)
	Wd.spawnAircraft(ctx, {
		name = "ATTACKER-" .. kind,
		type = "F-16C bl.52d",
		country = country.id.USA,
		from = Wd.pointFrom("ZONE-SITE-1", 45, 40),
		via = Wd.pointFrom("ZONE-SITE-1", 45, 37),
		to = Wd.pointFrom("ZONE-SITE-1", 225, 10),
		alt = 6000,
		speed = 250,
		task = "Ground Attack",
		payload = { pylons = loadout.pylons, fuel = 3000, flare = 0, chaff = 0, gun = 100 },
		immortal = true,
		invisible = true,
		ignoreThreats = true,
		waypointTasks = { Wd.attackTask(ctx.name .. "/SAM-SA6", loadout.weaponType) },
	})
	-- the Tor M2 wakes in both passes: its waking, then sleeping, ends the pass
	watch:waitFor("torM2", { false, true, false }, 360)
	if Wd.fired(shots, ctx.name .. "/ATTACKER-" .. kind .. "-1") == 0 then
		ctx.invalid(kind .. ": the attacker never fired")
	end
	return watch:report()
end

return { bomb = pass("bomb"), missile = pass("missile") }
