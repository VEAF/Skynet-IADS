do

--[[
InsimTestTools -- helpers the test/insim tier needs that neither Skynet source nor luaunit
provides.

Two halves, deliberately in one file while it stays small:
  * pure Lua      -- deepCopy, serialize, offsetFrom. Usable in-sim and offline, and unit-tested
                     offline by test/lua/test_insim_tools.lua.
  * DCS-world     -- missionGroupData, addFromMission, addAirFromMission, destroyIfLive,
                     removeJunkAround, removeJunkInZone. Need a running sim.

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

--- A point at `metres` from `origin` along `bearingDegrees`, measured clockwise from north.
--- Mission-table coordinates: x is NORTH, y is EAST -- which is why cos drives x and sin drives y.
function InsimTestTools.offsetFrom(origin, bearingDegrees, metres)
  assert(type(origin) == "table" and origin.x and origin.y,
    "offsetFrom: origin needs x (north) and y (east)")
  assert(type(bearingDegrees) == "number", "offsetFrom: bearingDegrees must be a number")
  assert(type(metres) == "number", "offsetFrom: metres must be a number")

  local radians = math.rad(bearingDegrees)
  return {
    x = origin.x + metres * math.cos(radians),
    y = origin.y + metres * math.sin(radians),
  }
end

--- DCS world ---------------------------------------------------------------------------------
--- Everything below needs a running sim. See test/insim/README.md for how to exercise it.

--- Mission-table category name -> the enum coalition.addGroup wants. Resolved inside a function
--- because Group.Category does not exist outside DCS and this file is loaded by the offline
--- suites.
local function groupCategoryFor(kind)
  if kind == "plane" then
    return Group.Category.AIRPLANE
  end
  if kind == "helicopter" then
    return Group.Category.HELICOPTER
  end
  return Group.Category.GROUND
end

--- The mission's own definition of an editor-placed group, by name, plus the country that owns
--- it and the mission-table category it lives under ("vehicle", "static", "plane" or
--- "helicopter"). `env.mission` is the entire mission table, available to any mission script --
--- it is how mist builds its database without touching the filesystem.
---
--- Returns a deep copy, so a caller that mutates the table (to randomise a position, say)
--- cannot corrupt the mission table that later runs read from.
function InsimTestTools.missionGroupData(groupName)
  assert(type(groupName) == "string", "missionGroupData: groupName must be a string")
  assert(env and env.mission and env.mission.coalition,
    "missionGroupData: env.mission is unavailable -- is this running inside a mission?")

  for _, coalitionData in pairs(env.mission.coalition) do
    for _, country in pairs(coalitionData.country or {}) do
      for _, kind in ipairs({ "vehicle", "static", "plane", "helicopter" }) do
        for _, group in pairs((country[kind] or {}).group or {}) do
          if group.name == groupName then
            return InsimTestTools.deepCopy(group), country.id, kind
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
  local data, countryId, kind = InsimTestTools.missionGroupData(groupName)

  if kind == "static" then
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
    coalition.addGroup(countryId, groupCategoryFor(kind), data)
  end

  return groupName
end

--- One in-air turning point, shaped as the Mission Editor writes them.
local function airPoint(point, altitude, speed)
  return {
    type = "Turning Point",
    action = "Turning Point",
    x = point.x,
    y = point.y,
    alt = altitude,
    alt_type = "BARO",
    speed = speed,
    speed_locked = true,
    ETA = 0,
    ETA_locked = false,
    formation_template = "",
    task = { id = "ComboTask", params = { tasks = {} } },
  }
end

--- Adds an air group from its editor template, positioned and routed by the caller. The editor
--- group supplies only the airframes; its own coordinates and waypoint are ignored, because an
--- air fixture is authored as a single in-air turning point parked anywhere on the map.
---
--- `speed` is METRES PER SECOND, as the mission table stores it -- 200 m/s is about 390 kt.
function InsimTestTools.addAirFromMission(groupName, opts)
  assert(type(opts) == "table", "addAirFromMission: opts must be a table")
  assert(type(opts.from) == "table" and opts.from.x and opts.from.y,
    "addAirFromMission: opts.from needs x (north) and y (east)")
  assert(type(opts.to) == "table" and opts.to.x and opts.to.y,
    "addAirFromMission: opts.to needs x (north) and y (east)")
  assert(type(opts.altitude) == "number" and opts.altitude > 0,
    "addAirFromMission: opts.altitude must be a positive number of metres")
  assert(type(opts.speed) == "number" and opts.speed >= 20 and opts.speed <= 600,
    "addAirFromMission: opts.speed is metres per second, not knots (200 m/s is about 390 kt)")

  local data, countryId, kind = InsimTestTools.missionGroupData(groupName)
  assert(kind == "plane" or kind == "helicopter",
    "addAirFromMission: '" .. groupName .. "' is a " .. kind .. " group, not an air group")

  local lead = data.units and data.units[1]
  assert(lead, "addAirFromMission: '" .. groupName .. "' has no units")

  -- Anchor the flight at `from` while preserving whatever spacing the editor gave it, so a
  -- two-ship stays a two-ship.
  local dx, dy = opts.from.x - lead.x, opts.from.y - lead.y
  for _, unit in ipairs(data.units) do
    unit.x = unit.x + dx
    unit.y = unit.y + dy
    unit.alt = opts.altitude
    unit.alt_type = "BARO"
    unit.speed = opts.speed
  end

  data.x, data.y = opts.from.x, opts.from.y
  data.task = "Nothing"
  data.route = {
    points = {
      airPoint(opts.from, opts.altitude, opts.speed),
      airPoint(opts.to, opts.altitude, opts.speed),
    },
  }

  coalition.addGroup(countryId, groupCategoryFor(kind), data)
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

--- Clears wrecks across a trigger zone. `trigger.misc.getZone` returns a Vec3 point, whose `z`
--- is east -- removeJunkAround takes mission-table coordinates, where east is `y`.
function InsimTestTools.removeJunkInZone(zoneName)
  assert(type(zoneName) == "string", "removeJunkInZone: zoneName must be a string")

  local zone = trigger.misc.getZone(zoneName)
  assert(zone, "removeJunkInZone: no trigger zone named '" .. zoneName .. "'")

  return InsimTestTools.removeJunkAround({ x = zone.point.x, y = zone.point.z }, zone.radius)
end

end
