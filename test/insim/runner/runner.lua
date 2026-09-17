do

--[[
InsimRunner -- drives test/insim scenarios inside a live mission.

Replaces luaunit's run loop while keeping its assertions. The reason is timing: live DCS
behaviour needs simulated seconds to pass, a mission script may not block, and luaunit's run()
is synchronous.

Each test is three coroutines -- setUp, body, tearDown -- resumed in sequence on a tick. Three
rather than one so that tearDown still runs when the body raises: the runner hears about the
failure from coroutine.resume and simply moves to the next phase. Wrapping the body in pcall
inside a single coroutine would be the obvious alternative, and it cannot work here, because
stock Lua 5.1 cannot yield across a pcall boundary.

coroutine.resume IS the protected call. There is no pcall anywhere in this file.
]]

InsimRunner = {}

InsimRunner.TICK = 0.1            -- sim-seconds between ticks
InsimRunner.DEFAULT_BUDGET = 600  -- sim-seconds one test may take before being abandoned

local function sortedTestNames(suite)
  local names = {}
  for key, value in pairs(suite) do
    if type(key) == "string" and key:match("^test") and type(value) == "function" then
      names[#names + 1] = key
    end
  end
  table.sort(names)
  return names
end

--- Flattens the suites into a queue of pending tests, so stepping never has to nest loops.
function InsimRunner.plan(suites)
  assert(type(suites) == "table", "InsimRunner.plan: suites must be an array")

  local state = { queue = {}, index = 1, phase = nil, results = { passed = 0, failed = 0,
    suites = {} } }

  for _, entry in ipairs(suites) do
    assert(type(entry.name) == "string", "InsimRunner.plan: every suite needs a name")
    assert(type(entry.suite) == "table", "InsimRunner.plan: every suite needs a suite table")

    local record = { name = entry.name, tests = {} }
    state.results.suites[#state.results.suites + 1] = record

    for _, testName in ipairs(sortedTestNames(entry.suite)) do
      state.queue[#state.queue + 1] = {
        suite = entry.suite,
        suiteName = entry.name,
        testName = testName,
        record = record,
      }
    end
  end

  return state
end

local function recordOutcome(state, item, message)
  local outcome = { name = item.testName, status = message and "fail" or "pass",
    message = message }
  item.record.tests[#item.record.tests + 1] = outcome
  if message then
    state.results.failed = state.results.failed + 1
  else
    state.results.passed = state.results.passed + 1
  end
end

--- Phases are attempted in order. A phase with no function is skipped; a failed setUp skips the
--- body but never the tearDown.
local PHASES = { "setUp", "body", "tearDown" }

local function phaseFunction(item, phaseName)
  if phaseName == "body" then
    return item.suite[item.testName]
  end
  return item.suite[phaseName]
end

local function beginPhase(state, item, phaseIndex)
  local phaseName = PHASES[phaseIndex]
  local fn = phaseFunction(item, phaseName)

  if not fn then
    return nil
  end

  return {
    name = phaseName,
    index = phaseIndex,
    co = coroutine.create(function() fn(item.suite) end),
    deadline = nil,
    pending = nil,
  }
end

--- Advances to the next phase that actually has a function, or finishes the test.
local function advancePhase(state, item, fromIndex)
  for next = fromIndex + 1, #PHASES do
    if item.failedSetUp and PHASES[next] == "body" then
      -- skipped deliberately
    else
      local phase = beginPhase(state, item, next)
      if phase then
        return phase
      end
    end
  end
  return nil
end

local function finishTest(state)
  local item = state.queue[state.index]
  recordOutcome(state, item, item.failure)
  state.index = state.index + 1
  state.phase = nil
end

--- One tick. Returns true while the run has more to do.
function InsimRunner.step(state)
  local item = state.queue[state.index]
  if not item then
    return false
  end

  if not state.started then
    state.started = true
  end

  if not state.phase then
    item.startedAt = timer.getTime()
    item.budget = item.suite.budgetSeconds or InsimRunner.DEFAULT_BUDGET
    state.phase = beginPhase(state, item, 1) or advancePhase(state, item, 1)
    if not state.phase then
      finishTest(state)
      return state.queue[state.index] ~= nil
    end
  end

  local phase = state.phase
  local now = timer.getTime()

  -- Overall budget. Checked before resuming so an abandoned coroutine is never touched again.
  if now - item.startedAt > item.budget then
    item.failure = item.failure or string.format(
      "%s exceeded its %gs budget while blocked on %s",
      item.testName, item.budget, InsimWait.describe(phase.pending))
    finishTest(state)
    return state.queue[state.index] ~= nil
  end

  local resumeValue = nil

  if phase.pending then
    local satisfied = false
    if phase.pending.kind == "waitFor" then
      -- The predicate runs here, on the runner's tick, never inside the test coroutine.
      satisfied = phase.pending.predicate() and true or false
    end

    if satisfied then
      resumeValue = true
    elseif now >= phase.deadline then
      resumeValue = (phase.pending.kind == "waitSeconds")
    else
      return true  -- still waiting; nothing to do this tick
    end
  end

  local ok, yielded = coroutine.resume(phase.co, resumeValue)

  if not ok then
    -- A raise from any phase fails the test. setUp additionally skips the body.
    item.failure = item.failure or tostring(yielded)
    if phase.name == "setUp" then
      item.failedSetUp = true
    end
    state.phase = advancePhase(state, item, phase.index)
    if not state.phase then
      finishTest(state)
    end
    return state.queue[state.index] ~= nil
  end

  if coroutine.status(phase.co) == "dead" then
    state.phase = advancePhase(state, item, phase.index)
    if not state.phase then
      finishTest(state)
    end
    return state.queue[state.index] ~= nil
  end

  -- Still alive, so it yielded a wait descriptor.
  assert(type(yielded) == "table" and yielded.timeout,
    item.testName .. ": a test coroutine yielded something that is not a wait descriptor")
  phase.pending = yielded
  phase.deadline = now + yielded.timeout

  return true
end

function InsimRunner.results(state)
  return state.results
end

--- Arms a repeating tick that steps the run to completion, then hands the results to
--- `onComplete`. Returning a time from a timer.scheduleFunction callback re-arms it, which is
--- the DCS contract dcs-stub also implements.
function InsimRunner.start(suites, onComplete)
  local state = InsimRunner.plan(suites)

  local function tick()
    if InsimRunner.step(state) then
      return timer.getTime() + InsimRunner.TICK
    end
    onComplete(InsimRunner.results(state))
    return nil
  end

  return timer.scheduleFunction(tick, nil, timer.getTime() + InsimRunner.TICK)
end

end
