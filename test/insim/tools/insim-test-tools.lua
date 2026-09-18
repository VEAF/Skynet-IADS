do

--[[
InsimTestTools -- helpers the test/insim tier needs that neither Skynet source nor luaunit
provides.

Two halves, deliberately in one file while it stays small:
  * pure Lua      -- deepCopy, serialize. Usable in-sim and offline, and unit-tested offline
                     by test/lua/test_insim_tools.lua.
  * DCS-world     -- addOrReplace, removeJunkAround, scopedName. Need a running sim.

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

--- Test-scoped names keep one scenario's fixtures from colliding with another's, and give
--- Skynet's prefix discovery a prefix that cannot match a neighbour's leftovers.
function InsimTestTools.scopedName(scenarioName, fixtureName)
  assert(type(scenarioName) == "string" and type(fixtureName) == "string",
    "scopedName: both arguments must be strings")
  return string.format("insim_%s_%s", scenarioName, fixtureName)
end

--- Adds a group from a template at `anchor`. Re-adding the same name replaces a LIVE group;
--- a wreck is not replaced, which is why setUp calls removeJunkAround first.
--- anchor/dx/dy are mission-table coordinates: x is NORTH, y is EAST.
function InsimTestTools.addGroupFromTemplate(template, name, anchor, countryId)
  assert(type(template) == "table" and template.units, "addGroupFromTemplate: bad template")
  assert(type(name) == "string", "addGroupFromTemplate: name must be a string")
  assert(type(anchor) == "table" and anchor.x and anchor.y,
    "addGroupFromTemplate: anchor needs x (north) and y (east)")

  local groupData = {
    name = name,
    task = template.task or "Ground Nothing",
    units = {},
    route = { points = {} },
  }

  for i, unit in ipairs(template.units) do
    groupData.units[i] = {
      name = string.format("%s-%d", name, i),
      type = unit.type,
      x = anchor.x + (unit.dx or 0),
      y = anchor.y + (unit.dy or 0),
      heading = unit.heading or 0,
      skill = unit.skill or "Average",
      playerCanDrive = false,
    }
  end

  coalition.addGroup(countryId, Group.Category.GROUND, groupData)
  return name
end

function InsimTestTools.addStaticFromTemplate(template, name, anchor, countryId)
  assert(type(template) == "table" and template.type, "addStaticFromTemplate: bad template")
  assert(type(anchor) == "table" and anchor.x and anchor.y,
    "addStaticFromTemplate: anchor needs x (north) and y (east)")

  coalition.addStaticObject(countryId, {
    name = name,
    type = template.type,
    category = template.category,
    x = anchor.x,
    y = anchor.y,
    heading = template.heading or 0,
    dead = false,
  })
  return name
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

  return world.removeJunk({
    id = world.VolumeType.SPHERE,
    params = { point = point, radius = radius },
  }) or 0
end

end
