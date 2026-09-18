--- Offline tests for the test/insim runner, driven against dcs-stub's controllable clock and
--- timer. This is the whole reason the runner is testable outside DCS: dcsStub.advanceClock and
--- dcsStub.fireDueTimers reproduce timer.getTime and timer.scheduleFunction's re-arm contract.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/../insim/runner/wait.lua")
dofile(base .. "/../insim/runner/runner.lua")

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

TestInsimRunner = {}

function TestInsimRunner:setUp()
  dcsStub.reset()
  dcsStub.setClock(100)
end

--- Runs a plan to completion, advancing the clock a tick at a time. Returns the results.
local function runToCompletion(suites, maxTicks)
  local state = InsimRunner.plan(suites)
  local ticks = 0
  while InsimRunner.step(state) do
    ticks = ticks + 1
    luaunit.assertTrue(ticks < (maxTicks or 100000), "run did not terminate")
    dcsStub.advanceClock(InsimRunner.TICK)
  end
  return InsimRunner.results(state)
end

function TestInsimRunner:testASynchronousPassingTestIsReportedAsPassed()
  local results = runToCompletion({
    { name = "Sync", suite = { testOk = function() end } },
  })
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertEquals(results.failed, 0)
  luaunit.assertEquals(results.suites[1].tests[1].name, "testOk")
  luaunit.assertEquals(results.suites[1].tests[1].status, "pass")
end

function TestInsimRunner:testAFailedAssertionIsReportedWithItsMessage()
  local results = runToCompletion({
    { name = "Failing", suite = { testBad = function() error("boom") end } },
  })
  luaunit.assertEquals(results.passed, 0)
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertEquals(results.suites[1].tests[1].status, "fail")
  luaunit.assertStrContains(results.suites[1].tests[1].message, "boom")
end

function TestInsimRunner:testLuaunitAssertionsWorkUnchangedInsideACoroutine()
  local results = runToCompletion({
    { name = "Asserting", suite = {
        testPasses = function() luaunit.assertEquals(1, 1) end,
        testFails = function() luaunit.assertEquals(1, 2) end,
      } },
  })
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertEquals(results.failed, 1)
end

function TestInsimRunner:testOnlyKeysStartingWithTestAreRun()
  local ran = {}
  runToCompletion({
    { name = "Selective", suite = {
        testOne = function() ran[#ran + 1] = "one" end,
        helper = function() ran[#ran + 1] = "helper" end,
      } },
  })
  luaunit.assertEquals(ran, { "one" })
end

function TestInsimRunner:testSetUpAndTearDownRunAroundEachTest()
  local order = {}
  runToCompletion({
    { name = "Lifecycle", suite = {
        setUp = function() order[#order + 1] = "setUp" end,
        tearDown = function() order[#order + 1] = "tearDown" end,
        testA = function() order[#order + 1] = "A" end,
        testB = function() order[#order + 1] = "B" end,
      } },
  })
  luaunit.assertEquals(order,
    { "setUp", "A", "tearDown", "setUp", "B", "tearDown" })
end

function TestInsimRunner:testTearDownStillRunsAfterTheTestBodyRaises()
  local torn = false
  local results = runToCompletion({
    { name = "Cleanup", suite = {
        tearDown = function() torn = true end,
        testRaises = function() error("nope") end,
      } },
  })
  luaunit.assertTrue(torn, "tearDown must run even when the body failed")
  luaunit.assertEquals(results.failed, 1)
end

function TestInsimRunner:testAFailingSetUpFailsTheTestAndSkipsTheBody()
  local bodyRan = false
  local results = runToCompletion({
    { name = "BadSetUp", suite = {
        setUp = function() error("setup exploded") end,
        testNeverRuns = function() bodyRan = true end,
      } },
  })
  luaunit.assertFalse(bodyRan)
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "setup exploded")
end

function TestInsimRunner:testWaitForResumesOnceThePredicateHolds()
  local flipAt = 100 + 5
  local results = runToCompletion({
    { name = "Waiting", suite = {
        testWaits = function()
          waitFor(function() return timer.getTime() >= flipAt end, 60)
        end,
      } },
  })
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertTrue(timer.getTime() >= flipAt)
end

function TestInsimRunner:testWaitForFailsTheTestWhenItsTimeoutPasses()
  local results = runToCompletion({
    { name = "TimingOut", suite = {
        testNeverSatisfied = function() waitFor(function() return false end, 10) end,
      } },
  })
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "timed out")
end

function TestInsimRunner:testWaitSecondsElapsesRoughlyTheRequestedSimTime()
  local started = timer.getTime()
  local finished
  local results = runToCompletion({
    { name = "Sleeping", suite = {
        testSleeps = function() waitSeconds(8); finished = timer.getTime() end,
      } },
  })
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertTrue(finished - started >= 8,
    "expected at least 8s of sim time, got " .. tostring(finished - started))
end

function TestInsimRunner:testTheOverallBudgetAbandonsATestThatNeverFinishes()
  local results = runToCompletion({
    { name = "Runaway", suite = {
        testLoopsForever = function()
          while true do
            waitFor(function() return false end, InsimRunner.DEFAULT_BUDGET * 2)
          end
        end,
      } },
  })
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "budget")
end

function TestInsimRunner:testOneFailureDoesNotStopLaterTestsOrSuites()
  local results = runToCompletion({
    { name = "First", suite = { testBoom = function() error("x") end } },
    { name = "Second", suite = { testFine = function() end } },
  })
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertEquals(#results.suites, 2)
  luaunit.assertEquals(results.suites[2].tests[1].status, "pass")
end

function TestInsimRunner:testStartArmsARepeatingTickAndCallsBackOnCompletion()
  local seen
  InsimRunner.start({ { name = "Async", suite = { testOk = function() end } } },
    function(results) seen = results end)
  for _ = 1, 20 do
    dcsStub.fireDueTimers()
    dcsStub.advanceClock(InsimRunner.TICK)
  end
  luaunit.assertNotNil(seen, "onComplete was never called")
  luaunit.assertEquals(seen.passed, 1)
end

function TestInsimRunner:testARaisingPredicateFailsOnlyThatTestAndRunsItsTearDown()
  local torn = false
  local results = runToCompletion({
    { name = "RaisingPredicate", suite = {
        tearDown = function() torn = true end,
        testPredicateRaises = function()
          waitFor(function() error("attempt to index a destroyed unit") end, 60)
        end,
      } },
    { name = "Later", suite = { testStillRuns = function() end } },
  })
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "predicate raised")
  luaunit.assertStrContains(results.suites[1].tests[1].message, "destroyed unit")
  luaunit.assertTrue(torn, "tearDown must still run after a predicate raises")
  luaunit.assertEquals(results.suites[2].tests[1].status, "pass")
end

function TestInsimRunner:testAMalformedYieldFailsOnlyThatTest()
  local results = runToCompletion({
    { name = "BadYield", suite = {
        testYieldsGarbage = function() coroutine.yield("not a descriptor") end,
      } },
    { name = "Later", suite = { testStillRuns = function() end } },
  })
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertEquals(results.passed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "not a wait descriptor")
end

function TestInsimRunner:testASetUpPredicateRaiseSkipsTheBodyButStillRunsTearDown()
  local bodyRan, torn = false, false
  local results = runToCompletion({
    { name = "SetUpPredicateRaises", suite = {
        setUp = function()
          waitFor(function() error("unit already destroyed") end, 60)
        end,
        tearDown = function() torn = true end,
        testNeverRuns = function() bodyRan = true end,
      } },
  })
  luaunit.assertFalse(bodyRan, "a setUp that failed must not be followed by the body")
  luaunit.assertTrue(torn, "tearDown must still run after a failed setUp")
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "predicate raised")
end

function TestInsimRunner:testASetUpMalformedYieldSkipsTheBodyButStillRunsTearDown()
  local bodyRan, torn = false, false
  local results = runToCompletion({
    { name = "SetUpYieldsGarbage", suite = {
        setUp = function() coroutine.yield("not a descriptor") end,
        tearDown = function() torn = true end,
        testNeverRuns = function() bodyRan = true end,
      } },
  })
  luaunit.assertFalse(bodyRan, "a setUp that failed must not be followed by the body")
  luaunit.assertTrue(torn, "tearDown must still run after a failed setUp")
  luaunit.assertEquals(results.failed, 1)
  luaunit.assertStrContains(results.suites[1].tests[1].message, "not a wait descriptor")
end

os.exit(luaunit.LuaUnit.run())
