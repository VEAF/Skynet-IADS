return function(result, lu)
	-- the group that is no SAM and the static carry the prefix, and are not sites
	lu.assertEquals(result.samNames, { "iads-builds/SAM-SA10", "iads-builds/SAM-SA6", "iads-builds/SAM-SA8" })
	lu.assertEquals(result.ew, 3)

	lu.assertEquals(result.sa10.nato, "SA-10")
	lu.assertTrue(result.sa10.searchRadars >= 1)
	lu.assertTrue(result.sa10.trackingRadars >= 1)
	lu.assertEquals(result.sa10.launchers, 2)

	-- one unit, radar and launcher in one
	lu.assertEquals(result.sa8, { nato = "SA-8", launchers = 1, searchRadars = 1, trackingRadars = 0 })

	lu.assertEquals(result.sa6.nato, "SA-6")
	lu.assertEquals(result.sa6.launchers, 2)

	lu.assertEquals(result.ew1l13, { nato = "Box Spring", workingRadar = true, awacs = false })
	lu.assertEquals(result.awacs.awacs, true)
	lu.assertEquals(result.awacs.workingRadar, true)
end
