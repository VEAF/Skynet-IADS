return function(result, lu)
	local identified, defended = false, false
	for _, value in ipairs(result.harm) do
		identified = identified or value == true
	end
	for _, value in ipairs(result.defending) do
		defended = defended or value == true
	end
	lu.assertTrue(identified, "no HARM was ever identified")
	lu.assertFalse(defended, "the site went silent although its point defence could take the HARM")
	-- dark until the attacker comes, then live to engage it, through the HARM. Whether it fires
	-- again meanwhile is the DCS AI's choice (siteShotsAfterHarm, measured, not judged)
	lu.assertEquals(result.active, { false, true })
	-- live for the HARM, and dark again once it is gone
	lu.assertEquals(result.pointDefence, { false, true, false })
end
