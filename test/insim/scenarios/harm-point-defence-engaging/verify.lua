return function(result, lu)
	-- woken for the waker, then live on it through the HARM: its point defence can take the HARM, so
	-- it is never silenced, and never sent dark
	lu.assertEquals(result.activeSite, { false, true }, "the SA-2 did not stay live once woken")
	lu.assertEquals(result.defending, { false }, "the SA-2 went silent although its point defence could take the HARM")
	-- live for the HARM, then released once the HARM is forgotten
	lu.assertEquals(result.activePointDefence, { false, true, false }, "the SA-15 was not live once, for the HARM")
	lu.assertEquals(
		result.pointDefenceLatched,
		{ false, true, false },
		"the SA-15's latch was not set and released once"
	)
	lu.assertEquals(result.harm, { false, true, false }, "the SA-2 never learnt of the HARM, or never forgot it")
end
