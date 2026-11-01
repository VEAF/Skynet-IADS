return function(result, lu)
	-- one live period, exactly: a site raised and lowered every cycle shows more
	lu.assertEquals(result.active, { false, true, false })
	local fired = false
	for _, value in ipairs(result.firing) do
		fired = fired or value == true
	end
	lu.assertTrue(fired, "the SA-6 never had a missile in flight")
end
