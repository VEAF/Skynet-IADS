local CASES = {
	"samConnectionNode",
	"ewConnectionNode",
	"ewPowerSource",
	"ewDestroyed",
	"commandCentre",
	"commandCentrePower",
	"commandCentreNode",
}

return function(result, lu)
	for _, name in ipairs(CASES) do
		local r = result[name]
		lu.assertNotNil(r, name .. " did not run")
		lu.assertTrue(r.held, name .. ": the site was not held by the network before")
		lu.assertTrue(r.autonomous, name .. ": the site was not autonomous after")
	end
end
