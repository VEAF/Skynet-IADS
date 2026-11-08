local function woke(values)
	for _, value in ipairs(values) do
		if value == true then
			return true
		end
	end
	return false
end

return function(result, lu)
	lu.assertTrue(woke(result.bomb.torM2), "bomb: the Tor M2 did not wake")
	lu.assertFalse(woke(result.bomb.sa10), "bomb: the SA-10 woke for a bomb it cannot engage")
	lu.assertFalse(woke(result.bomb.sa6), "bomb: the SA-6 woke for a bomb it cannot engage")
	lu.assertTrue(woke(result.missile.torM2), "missile: the Tor M2 did not wake")
	lu.assertTrue(woke(result.missile.sa10), "missile: the SA-10 did not wake")
	lu.assertFalse(woke(result.missile.sa6), "missile: the SA-6 woke for a missile it cannot engage")
end
