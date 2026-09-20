do

--[[
InsimTestTools -- helpers the test/insim tier needs that neither Skynet source nor luaunit
provides.

Two halves, deliberately in one file while it stays small:
  * pure Lua      -- deepCopy, serialize, offsetFrom, bearingBetween. Usable in-sim and offline,
                     and unit-tested offline by test/lua/test_insim_tools.lua.
  * DCS-world     -- missionGroupData, addFromMission, addAirFromMission, destroyIfLive,
                     removeJunkAround, removeJunkInZone. Need a running sim.

Scope rules: nothing Skynet-specific -- that lives in insim-skynet-tools.lua, so this file
stays usable by a scenario that does not load Skynet at all; check SkynetIADSUtils before
adding arithmetic, since test/lua already covers it.
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
    -- A double needs up to 17 significant digits to be recovered exactly, but 17 renders 41.3
    -- as 41.299999999999997. Try short first and keep it only when it parses back to the same
    -- double, so the output is the shortest EXACT form -- never a lossy one.
    local short = string.format("%.14g", value)
    if tonumber(short) == value then
      return short
    end
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

--- The course from `from` to `to`, in RADIANS clockwise from north -- the unit the mission table
--- stores headings in, so it can be assigned straight to a unit. Use math.deg on it to feed
--- offsetFrom, which takes degrees.
---
--- x is north and y is east, so the bearing is atan2(east, north): the inverse of offsetFrom's
--- convention, not the atan2(y, x) of a maths-class plane. Normalised to [0, 2pi) to match what
--- the Mission Editor writes; two identical points yield 0.
function InsimTestTools.bearingBetween(from, to)
  assert(type(from) == "table" and from.x and from.y,
    "bearingBetween: from needs x (north) and y (east)")
  assert(type(to) == "table" and to.x and to.y,
    "bearingBetween: to needs x (north) and y (east)")

  local radians = math.atan2(to.y - from.y, to.x - from.x)
  if radians < 0 then
    radians = radians + 2 * math.pi
  end
  return radians
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

--- Only groups carrying this prefix are ever added or destroyed. Everything else in the mission
--- -- playable slots, observers, scenery, a group half-built in the editor -- is untouchable,
--- which means forgetting to mark something protects it rather than exposing it.
InsimTestTools.FIXTURE_PREFIX = "SKY-"

--- True when any unit is flyable by a human. Such a group is never a fixture whatever it is
--- named: a naming convention cannot catch a slot that was accidentally given the prefix, and
--- the cost of that mistake is a player thrown out of their aircraft mid-flight.
local function isPlayable(groupData)
  for _, unit in pairs(groupData.units or {}) do
    if unit.skill == "Client" or unit.skill == "Player" then
      return true
    end
  end
  return false
end

--- Walks every group in the mission, whatever its category or coalition.
local function eachMissionGroup(visit)
  assert(env and env.mission and env.mission.coalition,
    "env.mission is unavailable -- is this running inside a mission?")

  for _, coalitionData in pairs(env.mission.coalition) do
    for _, country in pairs(coalitionData.country or {}) do
      for _, kind in ipairs({ "vehicle", "static", "plane", "helicopter" }) do
        for _, group in pairs((country[kind] or {}).group or {}) do
          visit(group, country, kind)
        end
      end
    end
  end
end

--- Every group a scenario may add or destroy: prefixed, and not playable.
function InsimTestTools.missionFixtureNames()
  local names = {}
  local prefix = InsimTestTools.FIXTURE_PREFIX

  eachMissionGroup(function(group)
    if type(group.name) == "string" and group.name:sub(1, #prefix) == prefix
      and not isPlayable(group) then
      names[#names + 1] = group.name
    end
  end)

  return names
end

--- Blanket teardown: destroys every live fixture and returns the names it took. Playable slots
--- and anything without the prefix survive.
function InsimTestTools.destroyAllFixtures()
  local destroyed = {}

  for _, name in ipairs(InsimTestTools.missionFixtureNames()) do
    if InsimTestTools.destroyIfLive(name) then
      destroyed[#destroyed + 1] = name
    end
  end

  return destroyed
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

--- Guards both add paths. Adding over a live playable group replaces it, which throws whoever
--- is sitting in it back to the slot screen -- and the slots exist precisely so a human can
--- watch a scenario run.
local function refuseIfPlayable(groupData, groupName)
  assert(not isPlayable(groupData),
    "'" .. tostring(groupName) .. "' is playable -- scenarios never add or destroy a slot")
end

--- Adds an editor-placed group or static under its own name, exactly where the Mission Editor
--- put it. Re-adding replaces a LIVE entity, so this doubles as the respawn that gives each
--- test fresh units; a wreck is not replaced, which is why setUp clears junk first.
function InsimTestTools.addFromMission(groupName)
  local data, countryId, kind = InsimTestTools.missionGroupData(groupName)
  refuseIfPlayable(data, groupName)

  -- Fixtures are authored late-activated so a normal mission start leaves them dormant. An
  -- added copy must not inherit that: Skynet's prefix discovery skips units that are not active.
  data.lateActivation = nil

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

--- One in-air turning point, shaped as the Mission Editor writes them. `etaLocked` is true on
--- waypoint 1 and false thereafter, which is what the editor writes.
local function airPoint(point, altitude, speed, etaLocked)
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
    ETA_locked = etaLocked,
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
  assert(opts.from.x ~= opts.to.x or opts.from.y ~= opts.to.y,
    "addAirFromMission: opts.from and opts.to are the same point -- the leg has no direction")
  assert(type(opts.altitude) == "number" and opts.altitude > 0,
    "addAirFromMission: opts.altitude must be a positive number of metres")
  assert(type(opts.speed) == "number" and opts.speed >= 20 and opts.speed <= 600,
    "addAirFromMission: opts.speed is metres per second, not knots (200 m/s is about 390 kt)")

  local data, countryId, kind = InsimTestTools.missionGroupData(groupName)
  refuseIfPlayable(data, groupName)

  -- Fixtures are authored late-activated so a normal mission start leaves them dormant. An
  -- added copy must not inherit that: Skynet's prefix discovery skips units that are not active.
  data.lateActivation = nil

  assert(kind == "plane" or kind == "helicopter",
    "addAirFromMission: '" .. groupName .. "' is a " .. kind .. " group, not an air group")

  local lead = data.units and data.units[1]
  assert(lead, "addAirFromMission: '" .. groupName .. "' has no units")

  -- Face the flight along its own leg. Without this it spawns on whatever heading the editor
  -- parked the template on and only turns onto waypoint 1 afterwards -- a wrong initial track for
  -- the first seconds of a detection run, and a fixture that looks broken on the Game Master map.
  local course = InsimTestTools.bearingBetween(opts.from, opts.to)

  -- Anchor the flight at `from` while preserving whatever spacing the editor gave it, so a
  -- two-ship stays a two-ship.
  local dx, dy = opts.from.x - lead.x, opts.from.y - lead.y
  for _, unit in ipairs(data.units) do
    unit.x = unit.x + dx
    unit.y = unit.y + dy
    unit.alt = opts.altitude
    unit.alt_type = "BARO"
    unit.speed = opts.speed
    unit.heading = course
  end

  data.x, data.y = opts.from.x, opts.from.y
  data.task = "Nothing"
  data.route = {
    points = {
      airPoint(opts.from, opts.altitude, opts.speed, true),
      airPoint(opts.to, opts.altitude, opts.speed, false),
    },
  }

  coalition.addGroup(countryId, groupCategoryFor(kind), data)
  return groupName
end

--- What DCS itself says about a group's radars, which is a different question from what Skynet
--- believes. SkynetIADSAbstractRadarElement:isActive() returns its own aiState flag, and going
--- dark calls enableEmission(false) -- emission stops, but the unit stays alive and its antenna
--- keeps turning. The model is not evidence either way.
---
--- Returns { emitting = <bool>, emitters = <n>, units = { { name, type, emitting, tracking } } }.
---
--- Unit:getRadar() reports false both for a unit that has no radar and for one whose radar is
--- off, so a single unit's false means little. The aggregate is what to assert on: nothing
--- emitting, or something emitting.
function InsimTestTools.radarState(groupName)
  local group = Group.getByName(groupName)
  assert(group, "radarState: no group named '" .. tostring(groupName) .. "'")

  local state = { emitting = false, emitters = 0, units = {} }

  for _, unit in ipairs(group:getUnits()) do
    if unit:isExist() then
      local emitting, tracking = unit:getRadar()
      emitting = emitting and true or false
      state.units[#state.units + 1] = {
        name = unit:getName(),
        type = unit:getTypeName(),
        emitting = emitting,
        tracking = tracking and tracking:getName() or nil,
      }
      if emitting then
        state.emitting = true
        state.emitters = state.emitters + 1
      end
    end
  end

  return state
end

--- One line of radarState for the run timeline, naming the emitters so a failed assertion is
--- diagnosable from the log alone.
function InsimTestTools.describeRadarState(groupName)
  local state = InsimTestTools.radarState(groupName)

  if not state.emitting then
    return string.format("%s: dark (%d unit(s), none emitting)", groupName, #state.units)
  end

  local names = {}
  for _, unit in ipairs(state.units) do
    if unit.emitting then
      names[#names + 1] = unit.type .. (unit.tracking and (" -> " .. unit.tracking) or "")
    end
  end

  return string.format("%s: emitting, %d of %d unit(s) -- %s",
    groupName, state.emitters, #state.units, table.concat(names, ", "))
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
