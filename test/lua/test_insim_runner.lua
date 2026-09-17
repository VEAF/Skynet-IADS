--- Offline tests for the test/insim runner, driven against dcs-stub's controllable clock and
--- timer. This is the whole reason the runner is testable outside DCS: dcsStub.advanceClock and
--- dcsStub.fireDueTimers reproduce timer.getTime and timer.scheduleFunction's re-arm contract.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/../insim/runner/wait.lua")

TestInsimWait = {}

function TestInsimWait:setUp()
  dcsStub.reset()
  dcsStub.setClock(100)
end

--- Drives a coroutine the way the runner will: resume, inspect the yield, decide.
local function resumeUntilBlocked(co)
  local ok, yielded = coroutine.resume(co)
  luaunit.assertTrue(ok, tostring(yielded))
  return yielded
end

function TestInsimWait:testWaitForYieldsADescriptorCarryingThePredicateAndTimeout()
  local called = false
  local co = coroutine.create(function()
    waitFor(function() called = true; return true end, 60)
  end)
  local yielded = resumeUntilBlocked(co)
  luaunit.assertEquals(yielded.kind, "waitFor")
  luaunit.assertEquals(yielded.timeout, 60)
  luaunit.assertIsFunction(yielded.predicate)
  luaunit.assertFalse(called, "the primitive must not evaluate the predicate itself")
end

function TestInsimWait:testWaitForReturnsNormallyWhenResumedWithTrue()
  local reached = false
  local co = coroutine.create(function()
    waitFor(function() return true end, 60)
    reached = true
  end)
  resumeUntilBlocked(co)
  local ok, err = coroutine.resume(co, true)
  luaunit.assertTrue(ok, tostring(err))
  luaunit.assertTrue(reached)
  luaunit.assertEquals(coroutine.status(co), "dead")
end

function TestInsimWait:testWaitForRaisesWhenResumedWithFalse()
  local co = coroutine.create(function()
    waitFor(function() return false end, 45)
  end)
  resumeUntilBlocked(co)
  local ok, err = coroutine.resume(co, false)
  luaunit.assertFalse(ok)
  luaunit.assertStrContains(tostring(err), "45")
  luaunit.assertStrContains(tostring(err), "timed out")
end

function TestInsimWait:testWaitForRejectsABadTimeout()
  local co = coroutine.create(function() waitFor(function() return true end, nil) end)
  local ok, err = coroutine.resume(co)
  luaunit.assertFalse(ok)
  luaunit.assertStrContains(tostring(err), "timeout")
end

function TestInsimWait:testWaitForRejectsANonFunctionPredicate()
  local co = coroutine.create(function() waitFor("not a function", 10) end)
  local ok, err = coroutine.resume(co)
  luaunit.assertFalse(ok)
  luaunit.assertStrContains(tostring(err), "predicate")
end

function TestInsimWait:testWaitSecondsYieldsADeadlineOnlyDescriptor()
  local co = coroutine.create(function() waitSeconds(30) end)
  local yielded = resumeUntilBlocked(co)
  luaunit.assertEquals(yielded.kind, "waitSeconds")
  luaunit.assertEquals(yielded.timeout, 30)
  luaunit.assertNil(yielded.predicate)
end

function TestInsimWait:testWaitSecondsReturnsNormallyOnResume()
  local reached = false
  local co = coroutine.create(function() waitSeconds(30); reached = true end)
  resumeUntilBlocked(co)
  luaunit.assertTrue(coroutine.resume(co, true))
  luaunit.assertTrue(reached)
end

function TestInsimWait:testDescribeNamesTheWaitForAFailureMessage()
  luaunit.assertStrContains(
    InsimWait.describe({ kind = "waitSeconds", timeout = 30 }), "waitSeconds")
  luaunit.assertStrContains(
    InsimWait.describe({ kind = "waitFor", timeout = 60 }), "waitFor")
end

os.exit(luaunit.LuaUnit.run())
