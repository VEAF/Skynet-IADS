local ctx = ...
local iads = ctx.state.iads

local start = timer.getTime()
local detected = Hotload.waitFor(function()
	return #iads:getContacts() > 0
end, 150)

return { detected = detected, after = timer.getTime() - start }
