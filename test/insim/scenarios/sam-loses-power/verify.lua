return function(result, lu)
	lu.assertTrue(result.powerLost, "the site still counts its power source as working")
	lu.assertTrue(result.dark, "the site stayed live: the dead event never reached it")
	lu.assertEquals(result.usable, 0)
end
