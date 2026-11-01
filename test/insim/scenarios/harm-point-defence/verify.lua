return function(result, lu)
	local identified = false
	for _, value in ipairs(result.harm) do
		identified = identified or value == true
	end
	lu.assertTrue(identified, "no HARM was ever identified")
	-- the point defence has missiles for the HARM, so the site stays live and the point defence engages
	lu.assertEquals(result.site, { true })
	lu.assertEquals({ result.pointDefence[1], result.pointDefence[2] }, { false, true })
end
