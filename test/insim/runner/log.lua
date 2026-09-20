do

--[[
InsimLog -- live narration of a run.

Separate from InsimReport, which owns the finished result set. This file owns what is happening
WHILE a run is in flight: a timeline of stamped lines, written to dcs.log the moment they happen
and collected so the results file can carry the same timeline.

Writing to env.info immediately rather than at the end is the point. A run that hangs, or a
mission that dies mid-scenario, still leaves everything up to that moment in dcs.log.

Lines are stored already formatted, so the timeline in last-run.lua reads exactly as dcs.log
does, and so no float ever has to survive serialization to be legible.
]]

InsimLog = {}

local TAG = "SKYNET_INSIM"
local SCREEN_SECONDS = 10

local entries = {}
local startedAt = nil
local context = nil

--- Starts a new timeline. Called once per run, before the first test.
function InsimLog.reset()
  entries = {}
  startedAt = timer.getTime()
  context = nil
end

--- Names the scenario whose lines follow, so a multi-suite run stays readable. The runner sets
--- this; scenarios never do.
function InsimLog.setContext(name)
  context = name
end

--- Seconds since the run started. Before reset() there is no run, so the stamp is 0 rather than
--- an error: logging must never be the thing that breaks a run.
local function stamp()
  local elapsed = startedAt and (timer.getTime() - startedAt) or 0
  return string.format("t=%6.1f ", elapsed)
end

--- Appends one line to the timeline and writes it to dcs.log. Returns the line.
function InsimLog.write(text)
  local line = stamp() .. text
  entries[#entries + 1] = line
  env.info(TAG .. ": " .. line)
  return line
end

--- write() plus the screen, for the few lines worth interrupting a tester for.
function InsimLog.announce(text, seconds)
  InsimLog.write(text)
  trigger.action.outText(text, seconds or SCREEN_SECONDS)
end

--- The timeline so far, as an array of formatted lines.
function InsimLog.entries()
  return entries
end

--- Scenario-facing, and global like waitFor and waitSeconds. Formats only when given arguments,
--- so a lone message containing a percent sign is safe.
function log(message, ...)
  local text = tostring(message)
  if select("#", ...) > 0 then
    text = string.format(text, ...)
  end
  if context then
    text = "[" .. context .. "] " .. text
  end
  return InsimLog.write(text)
end

end
