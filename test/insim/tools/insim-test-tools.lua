do

--[[
InsimTestTools -- helpers the test/insim tier needs that neither Skynet source nor luaunit
provides.

Two halves, deliberately in one file while it stays small:
  * pure Lua      -- deepCopy, serialize. Usable in-sim and offline, and unit-tested offline
                     by test/lua/test_insim_tools.lua.
  * DCS-world     -- missionGroupData, addFromMission, destroyIfLive, removeJunkAround. Need a
                     running sim.

Scope rules: nothing Skynet-specific (that belongs in scenarios or fixtures); check
SkynetIADSUtils before adding arithmetic, since test/lua already covers it; split this file
once it passes roughly 300 lines.
]]

InsimTestTools = {}

--- Pure Lua ----------------------------------------------------------------------------------

function InsimTestTools.deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for k, v in pairs(value) do
    copy[InsimTestTools.deepCopy(k)] = InsimTestTools.deepCopy(v)
  end
  return copy
end

local function serializeScalar(value)
  local kind = type(value)
  if kind == "string" then
    return string.format("%q", value)
  end
  if kind == "number" then
    -- A double needs 17 significant digits to be recovered exactly; %g strips trailing
    -- zeros, so clean values stay short.
    return string.format("%.17g", value)
  end
  if kind == "boolean" then
    return tostring(value)
  end
  error("InsimTestTools.serialize: cannot serialize a " .. kind)
end

--- Sorted so the same table always produces the same text: fixture files are committed, and a
--- diff that reorders on every regeneration is useless.
local function sortedKeys(tbl)
  local numbers, strings = {}, {}
  for k in pairs(tbl) do
    if type(k) == "number" then
      numbers[#numbers + 1] = k
    elseif type(k) == "string" then
      strings[#strings + 1] = k
    else
      error("InsimTestTools.serialize: cannot serialize a " .. type(k) .. " key")
    end
  end
  table.sort(numbers)
  table.sort(strings)
  for _, k in ipairs(strings) do
    numbers[#numbers + 1] = k
  end
  return numbers
end

function InsimTestTools.serialize(value, indent)
  if type(value) ~= "table" then
    return serializeScalar(value)
  end
  indent = indent or ""
  local inner = indent .. "  "
  local parts = {}
  for _, key in ipairs(sortedKeys(value)) do
    parts[#parts + 1] = string.format("%s[%s] = %s",
      inner, serializeScalar(key), InsimTestTools.serialize(value[key], inner))
  end
  if #parts == 0 then
    return "{}"
  end
  return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
end

--- DCS world ---------------------------------------------------------------------------------
--- Everything below needs a running sim. See test/insim/README.md for how to exercise it.

--- The mission's own definition of an editor-placed group, by name, plus the country that owns
--- it and whether it is a static. `env.mission` is the entire mission table, available to any
--- mission script -- it is how mist builds its database without touching the filesystem.
---
--- Returns a deep copy, so a caller that mutates the table (to randomise a position, say)
--- cannot corrupt the mission table that later runs read from.
function InsimTestTools.missionGroupData(groupName)
  assert(type(groupName) == "string", "missionGroupData: groupName must be a string")
  assert(env and env.mission and env.mission.coalition,
    "missionGroupData: env.mission is unavailable -- is this running inside a mission?")

  for _, coalitionData in pairs(env.mission.coalition) do
    for _, country in pairs(coalitionData.country or {}) do
      for _, isStatic in ipairs({ false, true }) do
        local category = isStatic and country.static or country.vehicle
        for _, group in pairs((category or {}).group or {}) do
          if group.name == groupName then
            return InsimTestTools.deepCopy(group), country.id, isStatic
          end
        end
      end
    end
  end

  error("missionGroupData: no group named '" .. tostring(groupName) .. "' in the mission")
end

--- Adds an editor-placed group or static under its own name, exactly where the Mission Editor
--- put it. Re-adding replaces a LIVE entity, so this doubles as the respawn that gives each
--- test fresh units; a wreck is not replaced, which is why setUp clears junk first.
function InsimTestTools.addFromMission(groupName)
  local data, countryId, isStatic = InsimTestTools.missionGroupData(groupName)

  if isStatic then
    local unit = data.units and data.units[1]
    assert(unit, "addFromMission: static '" .. groupName .. "' has no unit")
    coalition.addStaticObject(countryId, {
      name = data.name,
      type = unit.type,
      category = unit.category,
      x = unit.x,
      y = unit.y,
      heading = unit.heading,
      dead = false,
    })
  else
    coalition.addGroup(countryId, Group.Category.GROUND, data)
  end

  return groupName
end

--- Destroys a group or static if it is still live. Has no effect on a wreck -- that is what
--- removeJunkAround is for.
function InsimTestTools.destroyIfLive(name)
  local group = Group.getByName(name)
  if group and group:isExist() then
    group:destroy()
    return true
  end

  local static = StaticObject.getByName(name)
  if static and static:isExist() then
    static:destroy()
    return true
  end

  return false
end

--- Clears wrecks in a sphere around `anchor`. Returns how many objects DCS removed.
--- `radius` is measured from the anchor, so it must cover the whole composition footprint plus
--- debris scatter, not just the anchor point.
--- The sphere is centred at terrain height so it covers ground clutter regardless of elevation.
function InsimTestTools.removeJunkAround(anchor, radius)
  assert(type(anchor) == "table" and anchor.x and anchor.y,
    "removeJunkAround: anchor needs x (north) and y (east)")
  assert(type(radius) == "number" and radius > 0, "removeJunkAround: radius must be positive")

  -- land.getHeight takes a Vec2 {x = north, y = east}; world volumes take a Vec3
  -- {x = north, y = altitude, z = east}.
  local point = {
    x = anchor.x,
    y = land.getHeight({ x = anchor.x, y = anchor.y }),
    z = anchor.y,
  }

  local cleared = world.removeJunk({
    id = world.VolumeType.SPHERE,
    params = { point = point, radius = radius },
  })

  -- Documented as a count, but `or 0` alone would pass a boolean straight through to a caller
  -- that is about to do arithmetic on it.
  return type(cleared) == "number" and cleared or 0
end

end
