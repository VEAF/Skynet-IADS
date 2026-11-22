return function(result, lu)
	-- woken for the waker, then live through the HARM: never silenced, never sent dark
	lu.assertEquals(result.activeSite, { false, true }, "the SA-10 did not stay live once woken")
	lu.assertEquals(result.defending, { false }, "the SA-10 went silent although it can engage the HARM")
	lu.assertEquals(result.harm, { false, true, false }, "the SA-10 never learnt of the HARM, or never forgot it")
end
