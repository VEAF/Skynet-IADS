do

--[[
Wait primitives for test/insim scenarios.

A scenario body runs as a coroutine. It cannot block -- that would freeze the sim thread -- so
waiting means yielding a descriptor and letting the runner decide when to resume.

Deliberately free of pcall: stock Lua 5.1 cannot yield across a pcall boundary (LuaJIT can, and
DCS ships LuaJIT, but test/lua runs stock 5.1 and this code must pass there too). Failures
propagate through coroutine.resume, which is itself a protected call.
]]

InsimWait = {}

--- Yields until `predicate` returns true, or fails the test when `timeoutSec` sim-seconds pass.
--- The predicate is evaluated by the runner on its tick, never here.
function waitFor(predicate, timeoutSec)
  assert(type(predicate) == "function", "waitFor: predicate must be a function")
  assert(type(timeoutSec) == "number" and timeoutSec > 0,
    "waitFor: timeout must be a positive number of seconds")

  local satisfied = coroutine.yield({
    kind = "waitFor",
    predicate = predicate,
    timeout = timeoutSec,
  })

  if not satisfied then
    error(string.format("waitFor timed out after %gs", timeoutSec), 2)
  end
end

--- Yields for a fixed number of sim-seconds. Never fails on its own.
function waitSeconds(seconds)
  assert(type(seconds) == "number" and seconds > 0,
    "waitSeconds: seconds must be a positive number")

  coroutine.yield({ kind = "waitSeconds", timeout = seconds })
end

--- Human-readable name for a pending wait, used when a test blows its overall budget and the
--- runner has to say what it was waiting on.
function InsimWait.describe(yielded)
  if type(yielded) ~= "table" or not yielded.kind then
    return "an unrecognised yield"
  end
  return string.format("%s(%gs)", yielded.kind, yielded.timeout or 0)
end

end
