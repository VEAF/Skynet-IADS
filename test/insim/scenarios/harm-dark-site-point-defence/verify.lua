return function(result, lu)
	-- dark when told of the HARM, and dark throughout: it never had a target, nor a scan from goLive()
	lu.assertEquals(result.activeSite, { false }, "the SA-2 went live")
	-- live for the HARM, then released once the HARM is forgotten, rather than live for good
	lu.assertEquals(result.activePointDefence, { false, true, false }, "the SA-15 was not live once, for the HARM")
	lu.assertEquals(
		result.pointDefenceLatched,
		{ false, true, false },
		"the SA-15's latch was not set and released once"
	)
	-- the SA-2 learnt of the HARM, and forgot it
	lu.assertEquals(result.harm, { false, true, false }, "the SA-2 never learnt of the HARM, or never forgot it")
end
