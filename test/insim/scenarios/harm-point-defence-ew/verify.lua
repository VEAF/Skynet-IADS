return function(result, lu)
	-- the point defence has missiles for the HARM, so the site stays live throughout: a flap, as
	-- before the latch, shows as more values
	lu.assertEquals(result.activeSite, { true }, "the SA-6 went dark")
	-- live for the HARM, then released once the HARM is forgotten
	lu.assertEquals(result.activePointDefence, { false, true, false }, "the SA-15 was not live once, for the HARM")
	lu.assertEquals(
		result.pointDefenceLatched,
		{ false, true, false },
		"the SA-15's latch was not set and released once"
	)
	lu.assertEquals(result.harm, { false, true, false }, "the SA-6 never learnt of the HARM, or never forgot it")
end
