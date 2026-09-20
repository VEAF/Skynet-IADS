--- Offline tests for the test/insim runner, driven against dcs-stub's controllable clock and
--- timer. This is the whole reason the runner is testable outside DCS: dcsStub.advanceClock and
--- dcsStub.fireDueTimers reproduce timer.getTime and timer.scheduleFunction's re-arm contract.
local base = debug.getinfo(1, "S").source:match("^@(.+)[\\/]") or "."
luaunit = dofile(base .. "/../common/luaunit.lua")
dofile(base .. "/dcs-stub.lua")
dofile(base .. "/../insim/runner/log.lua")
dofile(base .. "/../insim/runner/wait.lua")
dofile(base .. "/../insim/runner/runner.lua")
dofile(base .. "/../insim/tools/insim-test-tools.lua")
dofile(base .. "/../insim/runner/report.lua")

TestInsimLog = {}

function TestInsimLog:setUp()
  dcsStub.reset()
  dcsStub.setClock(100)
  InsimLog.reset()
end

local function loggedText()
  local texts = {}
  for _, entry in ipairs(dcsStub.logs) do
    texts[#texts + 1] = entry.text
  end
  return table.concat(texts, " || ")
end

function TestInsimLog:testLogStampsTheLineWithSecondsSinceTheRunStarted()
  dcsStub.advanceClock(41.3)
  log("target detected")

  local entries = InsimLog.entries()
  luaunit.assertEquals(#entries, 1)
  luaunit.assertStrContains(entries[1], "41.3")
  luaunit.assertStrContains(entries[1], "target detected")
end

function TestInsimLog:testLogReachesTheDcsLogImmediatelyAndTagged()
  log("halfway")
  -- Immediately, not at the end of the run: a hung run must still leave its trace in dcs.log.
  luaunit.assertStrContains(loggedText(), "SKYNET_INSIM")
  luaunit.assertStrContains(loggedText(), "halfway")
end

function TestInsimLog:testLogFormatsWhenGivenArguments()
  log("added %s at %d m", "SKY-AIR-F18-01", 6000)
  luaunit.assertStrContains(InsimLog.entries()[1], "added SKY-AIR-F18-01 at 6000 m")
end

function TestInsimLog:testLogLeavesALoneMessageUnformatted()
  -- A bare percent is not a format directive when no arguments follow, and string.format
  -- would raise on it.
  log("100% of the fixtures are live")
  luaunit.assertStrContains(InsimLog.entries()[1], "100% of the fixtures are live")
end

function TestInsimLog:testLogPrefixesTheScenarioContextWhenSet()
  InsimLog.setContext("Detection")
  log("SAM went live")
  luaunit.assertStrContains(InsimLog.entries()[1], "[Detection] SAM went live")
end

function TestInsimLog:testAnnouncePutsTheLineOnScreenAsWellAsInTheLog()
  InsimLog.announce("PASS Detection.testThing (12.0s)")
  luaunit.assertEquals(#dcsStub.outTexts, 1)
  luaunit.assertStrContains(dcsStub.outTexts[1].text, "PASS Detection.testThing")
  luaunit.assertStrContains(loggedText(), "PASS Detection.testThing")
end

function TestInsimLog:testResetClearsTheTimelineAndRestartsTheClock()
  log("from the previous run")
  dcsStub.advanceClock(500)
  InsimLog.reset()
  log("from this one")

  local entries = InsimLog.entries()
  luaunit.assertEquals(#entries, 1)
  luaunit.assertStrContains(entries[1], "from this one")
  luaunit.assertStrContains(entries[1], "0.0")
end

function TestInsimLog:testResetClearsTheContextSoOneScenarioNeverTagsAnother()
  InsimLog.setContext("Detection")
  InsimLog.reset()
  log("no owner")
  luaunit.assertNotStrContains(InsimLog.entries()[1], "Detection")
end

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

function TestInsimRunner:testEachOutcomeRecordsHowLongTheTestTook()
  local results = runToCompletion({
    { name = "Timed", suite = { testSleeps = function() waitSeconds(8) end } },
  })

  -- The number that tells a green run from a nearly-timed-out one.
  local outcome = results.suites[1].tests[1]
  luaunit.assertTrue(outcome.duration >= 8, "duration was " .. tostring(outcome.duration))
  luaunit.assertTrue(outcome.duration < 9, "duration was " .. tostring(outcome.duration))
end

function TestInsimRunner:testAFailureRecordsWhichPhaseRaised()
  -- setUp and tearDown failures are otherwise indistinguishable in the results file.
  local results = runToCompletion({
    { name = "Broken", suite = {
        setUp = function() error("no fixture") end,
        testThing = function() end,
      } },
  })

  luaunit.assertEquals(results.suites[1].tests[1].phase, "setUp")
end

function TestInsimRunner:testATearDownFailureIsAttributedToTearDownNotTheBody()
  -- The body passed; only cleanup broke. Blaming the body sends you debugging the wrong half.
  local results = runToCompletion({
    { name = "Leaky", suite = {
        testThing = function() end,
        tearDown = function() error("destroyIfLive: no such group") end,
      } },
  })

  local outcome = results.suites[1].tests[1]
  luaunit.assertEquals(outcome.status, "fail")
  luaunit.assertEquals(outcome.phase, "tearDown")
end

function TestInsimRunner:testTheTimelineNamesEveryTestAndItsResult()
  local results = runToCompletion({
    { name = "Mixed", suite = {
        testGood = function() end,
        testBad = function() luaunit.assertTrue(false) end,
      } },
  })

  local timeline = table.concat(results.log, " || ")
  luaunit.assertStrContains(timeline, "PASS Mixed.testGood")
  luaunit.assertStrContains(timeline, "FAIL Mixed.testBad")
end

function TestInsimRunner:testTheTimelineOpensWithTheRunAndClosesWithTheTotals()
  local results = runToCompletion({
    { name = "Sync", suite = { testOk = function() end } },
  })

  local timeline = table.concat(results.log, " || ")
  luaunit.assertStrContains(timeline, "run start")
  luaunit.assertStrContains(timeline, "run complete: 1 passed, 0 failed")
end

function TestInsimRunner:testTheTimelineSaysHowLongAWaitActuallyTook()
  local flipAt
  local results = runToCompletion({
    { name = "Waity", suite = {
        setUp = function() flipAt = timer.getTime() + 5 end,
        testWaits = function() waitFor(function() return timer.getTime() >= flipAt end, 60) end,
      } },
  })

  local timeline = table.concat(results.log, " || ")
  luaunit.assertStrContains(timeline, "waitFor")
  luaunit.assertStrContains(timeline, "satisfied after")
end

function TestInsimRunner:testEachResultIsAnnouncedOnScreenAsItHappens()
  -- Otherwise the screen says nothing between "running 1 suite(s)" and the final summary,
  -- which for a long scenario is minutes of silence.
  runToCompletion({
    { name = "Sync", suite = { testOk = function() end } },
  })

  luaunit.assertEquals(#dcsStub.outTexts, 1)
  luaunit.assertStrContains(dcsStub.outTexts[1].text, "PASS Sync.testOk")
end

function TestInsimRunner:testScenarioLogLinesAreTaggedWithTheirSuite()
  local results = runToCompletion({
    { name = "Detection", suite = { testLogs = function() log("target airborne") end } },
  })

  luaunit.assertStrContains(table.concat(results.log, " || "), "[Detection] target airborne")
end

TestInsimReport = {}

function TestInsimReport:setUp()
  dcsStub.reset()
  dcsStub.setClock(100)
  self.results = {
    passed = 2,
    failed = 1,
    suites = {
      { name = "Detection", tests = {
          { name = "testDetects", status = "pass" },
          { name = "testGoesDark", status = "fail", message = "waitFor timed out after 60s" },
        } },
      { name = "Power", tests = { { name = "testLosesPower", status = "pass" } } },
    },
  }
end

function TestInsimReport:testSummaryLeadsWithTheCountsAndNamesFailures()
  local text = InsimReport.summaryText(self.results)
  luaunit.assertStrContains(text, "2 passed")
  luaunit.assertStrContains(text, "1 failed")
  luaunit.assertStrContains(text, "testGoesDark")
end

function TestInsimReport:testSummaryOfAGreenRunSaysSo()
  local text = InsimReport.summaryText({ passed = 3, failed = 0, suites = {} })
  luaunit.assertStrContains(text, "3 passed")
  luaunit.assertStrContains(text, "ALL PASSED")
end

function TestInsimReport:testDetailLinesIncludeEveryTestAndEachFailureMessage()
  local lines = table.concat(InsimReport.detailLines(self.results), "\n")
  luaunit.assertStrContains(lines, "Detection")
  luaunit.assertStrContains(lines, "testDetects")
  luaunit.assertStrContains(lines, "testLosesPower")
  luaunit.assertStrContains(lines, "waitFor timed out after 60s")
end

function TestInsimReport:testDetailLinesAreTaggedForLogGrepping()
  for _, line in ipairs(InsimReport.detailLines(self.results)) do
    luaunit.assertStrContains(line, "SKYNET_INSIM")
  end
end

function TestInsimReport:testResultsFileTextLoadsBackAsTheSameCounts()
  local chunk, err = loadstring(InsimReport.resultsFileText(self.results))
  luaunit.assertNotNil(chunk, tostring(err))
  local loaded = chunk()
  luaunit.assertEquals(loaded.passed, 2)
  luaunit.assertEquals(loaded.failed, 1)
  luaunit.assertEquals(loaded.suites[1].tests[2].message, "waitFor timed out after 60s")
end

function TestInsimReport:testEmitPutsTheSummaryOnScreenAndDetailInTheLog()
  InsimReport.emit(self.results, nil)
  luaunit.assertEquals(#dcsStub.outTexts, 1)
  luaunit.assertStrContains(dcsStub.outTexts[1].text, "1 failed")
  luaunit.assertTrue(dcsStub.outTexts[1].duration > 0)

  local logged = {}
  for _, entry in ipairs(dcsStub.logs) do
    logged[#logged + 1] = entry.text
  end
  luaunit.assertStrContains(table.concat(logged, "\n"), "SKYNET_INSIM")
end

function TestInsimReport:testEmitStillReportsWhenTheResultsFileCannotBeWritten()
  -- A path whose directory does not exist, which is the state of a fresh checkout: the results
  -- directory is created by nothing until the first successful write.
  InsimReport.emit(self.results, "Z:/no/such/repo/for/skynet/insim")

  luaunit.assertEquals(#dcsStub.outTexts, 1, "the screen summary must still appear")
  luaunit.assertStrContains(dcsStub.outTexts[1].text, "1 failed")

  local logged = {}
  for _, entry in ipairs(dcsStub.logs) do
    logged[#logged + 1] = entry.text
  end
  local allLogged = table.concat(logged, "\n")
  luaunit.assertStrContains(allLogged, "SKYNET_INSIM")
  luaunit.assertStrContains(allLogged, "cannot write")
end

local createdRepos = {}

--- A throwaway repo tree, so emit's real file writing is exercised rather than mocked.
local function tempRepo()
  local base = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("[\\/]*$", "")
  local dir = string.format("%s/skynet-insim-%d-%d", base, os.time(), math.random(1000000))
  createdRepos[#createdRepos + 1] = dir
  lfs.mkdir(dir)
  lfs.mkdir(dir .. "/test")
  lfs.mkdir(dir .. "/test/insim")
  lfs.mkdir(dir .. "/test/insim/results")
  return dir
end

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then
    return nil
  end
  local text = handle:read("*a")
  handle:close()
  return text
end

local function filesIn(dir)
  local names = {}
  local ok = pcall(function()
    for entry in lfs.dir(dir) do
      if entry ~= "." and entry ~= ".." then
        names[#names + 1] = entry
      end
    end
  end)
  return ok and names or {}
end

local function removeTree(dir)
  for entry in lfs.dir(dir) do
    if entry ~= "." and entry ~= ".." then
      local path = dir .. "/" .. entry
      if lfs.attributes(path, "mode") == "directory" then
        removeTree(path)
      else
        os.remove(path)
      end
    end
  end
  lfs.rmdir(dir)
end

--- Runs after every report test, including a failing one, so the suite leaves no temp trees.
function TestInsimReport:tearDown()
  for _, dir in ipairs(createdRepos) do
    pcall(removeTree, dir)
  end
  createdRepos = {}
end

function TestInsimReport:testTheResultsFileCarriesTheTimeline()
  self.results.log = { "t=   0.0 run start: 1 suite(s), 2 test(s)",
    "t=  41.3 [Detection] SAM went live" }

  local loaded = loadstring(InsimReport.resultsFileText(self.results))()

  luaunit.assertEquals(#loaded.log, 2)
  luaunit.assertStrContains(loaded.log[2], "SAM went live")
end

function TestInsimReport:testTheArchiveNameCarriesTheStampAndTheOutcome()
  local green = InsimReport.archiveName({ passed = 2, failed = 0 }, "20260920-123845")
  luaunit.assertStrContains(green, "20260920-123845")
  luaunit.assertStrContains(green, "PASS")
  luaunit.assertStrContains(green, ".lua")
end

function TestInsimReport:testTheArchiveNameSaysFailWhenAnythingFailed()
  local red = InsimReport.archiveName({ passed = 1, failed = 1 }, "20260920-123845")
  luaunit.assertStrContains(red, "FAIL")
  luaunit.assertNotStrContains(red, "PASS")
end

function TestInsimReport:testEmitWritesAnArchiveAlongsideLastRun()
  local repo = tempRepo()

  InsimReport.emit(self.results, repo)

  local lastRun = readFile(repo .. "/test/insim/results/last-run.lua")
  luaunit.assertNotNil(lastRun, "last-run.lua was not written")
  luaunit.assertEquals(loadstring(lastRun)().failed, 1)

  local archived = filesIn(repo .. "/test/insim/results/archive")
  luaunit.assertEquals(#archived, 1, "expected exactly one archived run")
  luaunit.assertStrContains(archived[1], "FAIL")

  local archive = readFile(repo .. "/test/insim/results/archive/" .. archived[1])
  luaunit.assertEquals(archive, lastRun, "the archive and last-run must hold the same run")
end

function TestInsimReport:testASecondRunArchivesSeparatelyRatherThanOverwriting()
  local repo = tempRepo()

  InsimReport.emit(self.results, repo)
  InsimReport.emit({ passed = 9, failed = 0, suites = {} }, repo)

  local archived = filesIn(repo .. "/test/insim/results/archive")
  luaunit.assertEquals(#archived, 2, "the earlier run was overwritten")
  luaunit.assertEquals(loadstring(
    readFile(repo .. "/test/insim/results/last-run.lua"))().passed, 9)
end

function TestInsimReport:testTheWrittenRunRecordsWhenItFinished()
  local repo = tempRepo()

  InsimReport.emit(self.results, repo)

  local loaded = loadstring(readFile(repo .. "/test/insim/results/last-run.lua"))()
  luaunit.assertNotNil(loaded.finishedAt, "a run with no date cannot be placed later")
  luaunit.assertStrMatches(loaded.finishedAt, "%d%d%d%d%-%d%d%-%d%d .*")
end

os.exit(luaunit.LuaUnit.run())
