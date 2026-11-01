return function(result, lu)
	lu.assertTrue(result.liveFirst, "the autonomous site was not live before the target came")
	lu.assertEquals(result.active[1], true)
	local fired = false
	for _, value in ipairs(result.firing) do
		fired = fired or value == true
	end
	lu.assertTrue(fired, "the autonomous site never fired")
end
