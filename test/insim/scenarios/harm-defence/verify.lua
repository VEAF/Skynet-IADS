return function(result, lu)
	local identified = false
	for _, value in ipairs(result.harm) do
		identified = identified or value == true
	end
	lu.assertTrue(identified, "no HARM was ever identified")
	-- silenced, and back once the defence is over
	lu.assertEquals(result.active, { true, false, true })
end
