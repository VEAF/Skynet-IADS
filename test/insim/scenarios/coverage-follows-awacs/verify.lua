return function(result, lu)
	-- held while the AWACS covered it, and handed back once it had left: both halves
	lu.assertEquals(result.autonomous, { false, true })
end
