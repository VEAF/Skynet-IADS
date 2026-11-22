return function(result, lu)
	-- silenced, back once the silence is over, and nothing after: a flap shows as more values
	lu.assertEquals(result.activeSite, { true, false, true }, "the SA-6 was not silenced and back exactly once")
	lu.assertEquals(result.harm, { false, true, false }, "the SA-6 never learnt of the HARM, or never forgot it")
end
