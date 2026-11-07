return function(result, lu)
	local identified, defended = false, false
	for _, value in ipairs(result.harm) do
		identified = identified or value == true
	end
	for _, value in ipairs(result.defending) do
		defended = defended or value == true
	end
	lu.assertTrue(identified, "no HARM was ever identified")
	lu.assertTrue(defended, "the site never went silent to evade the HARM")
	-- dark until the attacker comes, live to engage it, dark under the HARM, back up after it
	lu.assertEquals(
		{ result.active[1], result.active[2], result.active[3], result.active[4] },
		{ false, true, false, true }
	)
end
