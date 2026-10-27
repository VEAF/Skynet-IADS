return function(result, lu)
	-- lit when the intruder crossed the radius, and quiet once the persistence ran out: both halves
	lu.assertEquals(result.active, { false, true, false })
end
